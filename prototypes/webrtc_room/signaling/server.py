#!/usr/bin/env python3
"""WPG WebRTC 房间码信令。

只做三件事：房间码到会话的映射、SDP/ICE 交换、会话取消与空闲回收。
不转发游戏快照、roster、Ready、seat 或 Combat 数据。
"""

from __future__ import annotations

import argparse
import hmac
import json
import secrets
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlsplit

ROOM_CODE_LENGTH: int = 6
ROOM_ALPHABET: str = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
IDLE_TIMEOUT_SEC: float = 180.0
MAX_SDP_BYTES: int = 32768
MAX_ICE_BYTES: int = 2048
MAX_MID_BYTES: int = 256
MAX_MESSAGES: int = 64
MAX_BODY_BYTES: int = 48 * 1024
SIGNAL_KINDS: Tuple[str, ...] = ("offer", "answer", "ice", "bye")
ALLOWED_SIGNAL_KEYS: Tuple[str, ...] = ("kind", "sdp", "candidate", "mid")


class Clock:
    """可替换的单调时钟。测试推进它，生产用 time.monotonic。"""

    def now(self) -> float:
        return time.monotonic()


class ManualClock(Clock):
    """测试时钟。不调用 sleep。"""

    def __init__(self) -> None:
        self._now: float = 0.0

    def now(self) -> float:
        return self._now

    def advance(self, seconds: float) -> None:
        self._now += seconds


@dataclass
class SignalMessage:
    seq: int
    sender: str
    kind: str
    sdp: str = ""
    candidate: str = ""
    mid: str = ""

    def public(self) -> Dict[str, object]:
        return {
            "seq": self.seq,
            "sender": self.sender,
            "kind": self.kind,
            "sdp": self.sdp,
            "candidate": self.candidate,
            "mid": self.mid,
        }


@dataclass
class Room:
    code: str
    host_token: str
    created_at: float
    last_activity: float
    guest_token: str = ""
    closed: bool = False
    next_seq: int = 1
    messages: List[SignalMessage] = field(default_factory=list)


class SignalError(Exception):
    def __init__(self, status: int, code: str) -> None:
        super().__init__(code)
        self.status: int = status
        self.code: str = code


LogFunc = Callable[[str], None]


class RoomService:
    """房间注册表。HTTP 层只负责搬 JSON。"""

    def __init__(
        self,
        clock: Optional[Clock] = None,
        idle_timeout_sec: float = IDLE_TIMEOUT_SEC,
        log: Optional[LogFunc] = None,
    ) -> None:
        self._clock: Clock = clock if clock is not None else Clock()
        self._idle_timeout_sec: float = idle_timeout_sec
        self._log: LogFunc = log if log is not None else (lambda _message: None)
        self._rooms: Dict[str, Room] = {}
        self._lock: threading.Lock = threading.Lock()

    def create_room(self) -> Dict[str, str]:
        with self._lock:
            self._sweep_locked()
            code: str = self._allocate_code_locked()
            now: float = self._clock.now()
            token: str = secrets.token_urlsafe(24)
            self._rooms[code] = Room(
                code=code,
                host_token=token,
                created_at=now,
                last_activity=now,
            )
            self._log("create code=%s" % code)
            return {"room_code": code, "token": token, "role": "host"}

    def join_room(self, code: str) -> Dict[str, str]:
        with self._lock:
            self._sweep_locked()
            room: Room = self._require_room_locked(code)
            if room.closed:
                raise SignalError(410, "ROOM_CLOSED")
            if room.guest_token:
                raise SignalError(409, "ROOM_FULL")
            token: str = secrets.token_urlsafe(24)
            room.guest_token = token
            room.last_activity = self._clock.now()
            self._log("join code=%s" % code)
            return {"room_code": code, "token": token, "role": "guest"}

    def post_signal(self, code: str, token: str, body: Dict[str, object]) -> Dict[str, int]:
        kind, sdp, candidate, mid = _parse_signal(body)
        with self._lock:
            self._sweep_locked()
            room: Room = self._require_room_locked(code)
            sender: str = self._role_for_token_locked(room, token)
            if room.closed:
                raise SignalError(410, "ROOM_CLOSED")
            if len(room.messages) >= MAX_MESSAGES:
                raise SignalError(409, "MAILBOX_FULL")
            message: SignalMessage = SignalMessage(
                seq=room.next_seq,
                sender=sender,
                kind=kind,
                sdp=sdp,
                candidate=candidate,
                mid=mid,
            )
            room.next_seq += 1
            room.messages.append(message)
            room.last_activity = self._clock.now()
            if kind == "bye":
                room.closed = True
            self._log("signal code=%s sender=%s kind=%s seq=%d" % (code, sender, kind, message.seq))
            return {"seq": message.seq}

    def get_signals(self, code: str, token: str, after: int) -> Dict[str, object]:
        with self._lock:
            self._sweep_locked()
            room: Room = self._require_room_locked(code)
            sender: str = self._role_for_token_locked(room, token)
            room.last_activity = self._clock.now()
            visible: List[Dict[str, object]] = [
                message.public()
                for message in room.messages
                if message.seq > after and message.sender != sender
            ]
            return {"messages": visible, "cursor": room.next_seq - 1, "closed": room.closed}

    def cancel_room(self, code: str, token: str) -> Dict[str, bool]:
        with self._lock:
            self._sweep_locked()
            room: Room = self._require_room_locked(code)
            sender: str = self._role_for_token_locked(room, token)
            if not room.closed and len(room.messages) < MAX_MESSAGES:
                message: SignalMessage = SignalMessage(seq=room.next_seq, sender=sender, kind="bye")
                room.next_seq += 1
                room.messages.append(message)
            room.closed = True
            room.last_activity = self._clock.now()
            self._log("cancel code=%s sender=%s" % (code, sender))
            return {"cancelled": True}

    def health(self) -> Dict[str, bool]:
        return {"ok": True}

    def _allocate_code_locked(self) -> str:
        for _attempt in range(8):
            code: str = "".join(secrets.choice(ROOM_ALPHABET) for _index in range(ROOM_CODE_LENGTH))
            if code not in self._rooms:
                return code
        raise SignalError(503, "CODE_EXHAUSTED")

    def _require_room_locked(self, code: str) -> Room:
        if not _is_room_code(code):
            raise SignalError(404, "ROOM_NOT_FOUND")
        room: Optional[Room] = self._rooms.get(code)
        if room is None:
            raise SignalError(404, "ROOM_NOT_FOUND")
        return room

    def _role_for_token_locked(self, room: Room, token: str) -> str:
        if token and hmac.compare_digest(token, room.host_token):
            return "host"
        if room.guest_token and token and hmac.compare_digest(token, room.guest_token):
            return "guest"
        raise SignalError(403, "BAD_TOKEN")

    def _sweep_locked(self) -> None:
        now: float = self._clock.now()
        expired: List[str] = [
            code
            for code, room in self._rooms.items()
            if now - room.last_activity > self._idle_timeout_sec
        ]
        for code in expired:
            del self._rooms[code]
            self._log("expire code=%s" % code)


def _is_room_code(code: str) -> bool:
    if len(code) != ROOM_CODE_LENGTH:
        return False
    return all(ch in ROOM_ALPHABET for ch in code)


def _parse_signal(body: Dict[str, object]) -> Tuple[str, str, str, str]:
    extra: List[str] = [key for key in body.keys() if key not in ALLOWED_SIGNAL_KEYS]
    if extra:
        raise SignalError(400, "BAD_SIGNAL")
    kind_raw: object = body.get("kind", "")
    if not isinstance(kind_raw, str) or kind_raw not in SIGNAL_KINDS:
        raise SignalError(400, "BAD_SIGNAL")
    sdp: str = _optional_text(body.get("sdp", ""), MAX_SDP_BYTES)
    candidate: str = _optional_text(body.get("candidate", ""), MAX_ICE_BYTES)
    mid: str = _optional_text(body.get("mid", ""), MAX_MID_BYTES)
    if kind_raw in ("offer", "answer"):
        if not sdp or candidate or mid:
            raise SignalError(400, "BAD_SIGNAL")
    elif kind_raw == "ice":
        if not candidate or sdp:
            raise SignalError(400, "BAD_SIGNAL")
    elif sdp or candidate or mid:
        raise SignalError(400, "BAD_SIGNAL")
    return kind_raw, sdp, candidate, mid


def _optional_text(value: object, limit: int) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise SignalError(400, "BAD_SIGNAL")
    if len(value.encode("utf-8")) > limit:
        raise SignalError(413, "TOO_LARGE")
    return value


class SignalHandler(BaseHTTPRequestHandler):
    service: RoomService = RoomService()
    server_version: str = "WPGSignal/1"

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        self._dispatch()

    def do_POST(self) -> None:
        self._dispatch()

    def do_DELETE(self) -> None:
        self._dispatch()

    def _dispatch(self) -> None:
        try:
            status, payload = self._route()
        except SignalError as err:
            status, payload = err.status, {"error": err.code}
        except json.JSONDecodeError:
            status, payload = 400, {"error": "BAD_JSON"}
        except Exception:
            status, payload = 500, {"error": "INTERNAL"}
        self._send_json(status, payload)

    def _route(self) -> Tuple[int, Dict[str, object]]:
        parts, query = _split_path(self.path)
        if self.command == "GET" and parts == ["v1", "health"]:
            return 200, self.service.health()
        if self.command == "POST" and parts == ["v1", "rooms"]:
            self._read_object(allow_empty=True)
            return 201, self.service.create_room()
        if len(parts) == 4 and parts[0] == "v1" and parts[1] == "rooms":
            code: str = parts[2]
            action: str = parts[3]
            if self.command == "POST" and action == "join":
                self._read_object(allow_empty=True)
                return 200, self.service.join_room(code)
            if action == "signals" and self.command == "POST":
                body: Dict[str, object] = self._read_object(allow_empty=False)
                return 200, self.service.post_signal(code, self._token(), body)
            if action == "signals" and self.command == "GET":
                after: int = _query_int(query, "after")
                return 200, self.service.get_signals(code, self._token(), after)
        if self.command == "DELETE" and len(parts) == 3 and parts[0] == "v1" and parts[1] == "rooms":
            return 200, self.service.cancel_room(parts[2], self._token())
        raise SignalError(404, "NOT_FOUND")

    def _token(self) -> str:
        raw: Optional[str] = self.headers.get("X-Room-Token")
        return raw.strip() if raw else ""

    def _read_object(self, allow_empty: bool) -> Dict[str, object]:
        length_raw: Optional[str] = self.headers.get("Content-Length")
        length: int = int(length_raw) if length_raw else 0
        if length < 0 or length > MAX_BODY_BYTES:
            raise SignalError(413, "TOO_LARGE")
        if length == 0:
            if allow_empty:
                return {}
            raise SignalError(400, "BAD_JSON")
        raw: bytes = self.rfile.read(length)
        parsed: object = json.loads(raw.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise SignalError(400, "BAD_JSON")
        return parsed

    def _send_json(self, status: int, payload: Dict[str, object]) -> None:
        encoded: bytes = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(encoded)


def _split_path(path: str) -> Tuple[List[str], Dict[str, List[str]]]:
    parsed = urlsplit(path)
    parts: List[str] = [part for part in parsed.path.split("/") if part]
    return parts, parse_qs(parsed.query)


def _query_int(query: Dict[str, List[str]], key: str) -> int:
    values: List[str] = query.get(key, [])
    if not values:
        return 0
    try:
        parsed: int = int(values[0])
    except ValueError:
        raise SignalError(400, "BAD_QUERY")
    if parsed < 0:
        raise SignalError(400, "BAD_QUERY")
    return parsed


def make_server(service: RoomService, host: str, port: int) -> ThreadingHTTPServer:
    handler: type = type("BoundSignalHandler", (SignalHandler,), {"service": service})
    httpd: ThreadingHTTPServer = ThreadingHTTPServer((host, port), handler)
    httpd.daemon_threads = True
    return httpd


def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(description="WPG WebRTC 房间码信令")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--verbose", action="store_true")
    args: argparse.Namespace = parser.parse_args()
    logs: LogFunc = (lambda message: print(message, flush=True)) if args.verbose else (lambda _message: None)
    service: RoomService = RoomService(log=logs)
    httpd: ThreadingHTTPServer = make_server(service, args.host, args.port)
    bound_host, bound_port = httpd.server_address[:2]
    print("LISTEN %s %s" % (bound_host, bound_port), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
