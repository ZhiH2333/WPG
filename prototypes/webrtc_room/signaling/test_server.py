#!/usr/bin/env python3
"""房间码信令回归。失败返回非 0，不把跳过计为通过。"""

from __future__ import annotations

import json
import os
import sys
import threading
import urllib.error
import urllib.request
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import server as S  # noqa: E402

_failures: List[str] = []


def expect(condition: bool, label: str) -> None:
    if not condition:
        _failures.append(label)


def create_service(clock: Optional[S.ManualClock] = None, logs: Optional[List[str]] = None) -> S.RoomService:
    log = (lambda message: logs.append(message)) if logs is not None else None
    return S.RoomService(clock=clock, idle_timeout_sec=30.0, log=log)


def test_room_code_and_exchange() -> None:
    service: S.RoomService = create_service()
    created: Dict[str, str] = service.create_room()
    code: str = created["room_code"]
    expect(len(code) == S.ROOM_CODE_LENGTH, "code length")
    expect(all(ch in S.ROOM_ALPHABET for ch in code), "code alphabet")
    joined: Dict[str, str] = service.join_room(code)
    expect(joined["room_code"] == code, "join maps to same room")
    offer: Dict[str, int] = service.post_signal(
        code, created["token"], {"kind": "offer", "sdp": "v=0\r\noffer"}
    )
    guest_view: Dict[str, object] = service.get_signals(code, joined["token"], 0)
    messages: List[Dict[str, object]] = guest_view["messages"]  # type: ignore[assignment]
    expect(len(messages) == 1 and messages[0]["kind"] == "offer", "guest sees offer")
    host_view: Dict[str, object] = service.get_signals(code, created["token"], 0)
    expect(host_view["messages"] == [], "host does not see own offer")
    service.post_signal(code, joined["token"], {"kind": "answer", "sdp": "v=0\r\nanswer"})
    service.post_signal(
        code,
        created["token"],
        {"kind": "ice", "candidate": "candidate:1 1 UDP 1 1.2.3.4 9 typ host", "mid": "0"},
    )
    service.post_signal(
        code,
        joined["token"],
        {"kind": "ice", "candidate": "candidate:2 1 UDP 1 5.6.7.8 9 typ relay", "mid": "0"},
    )
    host_after: Dict[str, object] = service.get_signals(code, created["token"], offer["seq"])
    kinds: List[str] = [str(item["kind"]) for item in host_after["messages"]]  # type: ignore[index]
    expect(kinds == ["answer", "ice"], "host receives answer and guest ice")
    expect(offer["seq"] == 1, "first seq")


def test_rejections() -> None:
    service: S.RoomService = create_service()
    created: Dict[str, str] = service.create_room()
    code: str = created["room_code"]
    _expect_error(lambda: service.join_room("ZZZZZZ"), 404, "unknown room")
    _expect_error(lambda: service.post_signal(code, "nope", {"kind": "bye"}), 403, "bad token")
    service.join_room(code)
    _expect_error(lambda: service.join_room(code), 409, "second guest")
    _expect_error(lambda: service.post_signal(code, created["token"], {"kind": "snapshot", "sdp": "x"}), 400, "snapshot kind")
    _expect_error(
        lambda: service.post_signal(code, created["token"], {"kind": "offer", "sdp": "v=0", "snapshot": {}}),
        400,
        "extra snapshot key",
    )
    _expect_error(
        lambda: service.post_signal(code, created["token"], {"kind": "offer", "sdp": "x" * (S.MAX_SDP_BYTES + 1)}),
        413,
        "oversize sdp",
    )
    _expect_error(lambda: service.post_signal(code, created["token"], {"kind": "offer"}), 400, "missing sdp")
    _expect_error(
        lambda: service.post_signal(code, created["token"], {"kind": "ice", "candidate": ""}),
        400,
        "empty ice",
    )


def test_cancel_and_bye() -> None:
    service: S.RoomService = create_service()
    created: Dict[str, str] = service.create_room()
    code: str = created["room_code"]
    joined: Dict[str, str] = service.join_room(code)
    service.post_signal(code, joined["token"], {"kind": "bye"})
    host_view: Dict[str, object] = service.get_signals(code, created["token"], 0)
    messages: List[Dict[str, object]] = host_view["messages"]  # type: ignore[assignment]
    expect(len(messages) == 1 and messages[0]["kind"] == "bye", "bye delivered")
    expect(host_view["closed"] is True, "bye closes room")
    _expect_error(lambda: service.post_signal(code, created["token"], {"kind": "offer", "sdp": "v=0"}), 410, "post after bye")
    fresh: S.RoomService = create_service()
    created = fresh.create_room()
    fresh.cancel_room(created["room_code"], created["token"])
    _expect_error(lambda: fresh.join_room(created["room_code"]), 410, "cancel before join")


def test_idle_timeout_without_sleep() -> None:
    clock: S.ManualClock = S.ManualClock()
    service: S.RoomService = create_service(clock)
    created: Dict[str, str] = service.create_room()
    clock.advance(30.0)
    service.get_signals(created["room_code"], created["token"], 0)
    clock.advance(31.0)
    _expect_error(lambda: service.join_room(created["room_code"]), 404, "idle room expires")


def test_logs_omit_token_and_sdp() -> None:
    logs: List[str] = []
    service: S.RoomService = create_service(logs=logs)
    created: Dict[str, str] = service.create_room()
    secret_sdp: str = "v=0-secret-sdp-marker"
    service.post_signal(created["room_code"], created["token"], {"kind": "offer", "sdp": secret_sdp})
    text: str = "\n".join(logs)
    expect(created["token"] not in text, "token not logged")
    expect(secret_sdp not in text, "sdp not logged")
    expect("kind=offer" in text, "kind is logged")


def test_mailbox_limit() -> None:
    service: S.RoomService = create_service()
    created: Dict[str, str] = service.create_room()
    service.join_room(created["room_code"])
    for index in range(S.MAX_MESSAGES):
        service.post_signal(
            created["room_code"],
            created["token"],
            {"kind": "ice", "candidate": "candidate:%d typ host" % index, "mid": "0"},
        )
    _expect_error(
        lambda: service.post_signal(
            created["room_code"],
            created["token"],
            {"kind": "ice", "candidate": "candidate:overflow typ host", "mid": "0"},
        ),
        409,
        "mailbox full",
    )


def test_http_roundtrip() -> None:
    logs: List[str] = []
    service: S.RoomService = create_service(logs=logs)
    httpd: S.ThreadingHTTPServer = S.make_server(service, "127.0.0.1", 0)
    thread: threading.Thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    port: int = int(httpd.server_address[1])
    try:
        status, created = _http(port, "POST", "/v1/rooms", None, {})
        expect(status == 201, "http create")
        code: str = str(created["room_code"])
        token: str = str(created["token"])
        status, joined = _http(port, "POST", "/v1/rooms/%s/join" % code, None, {})
        expect(status == 200 and joined["role"] == "guest", "http join")
        status, posted = _http(
            port,
            "POST",
            "/v1/rooms/%s/signals" % code,
            token,
            {"kind": "offer", "sdp": "v=0"},
        )
        expect(status == 200 and posted["seq"] == 1, "http offer")
        status, inbox = _http(port, "GET", "/v1/rooms/%s/signals?after=0" % code, str(joined["token"]), None)
        messages: List[Dict[str, object]] = inbox["messages"]  # type: ignore[assignment]
        expect(status == 200 and messages[0]["sdp"] == "v=0", "http guest poll")
        status, missing = _http(port, "POST", "/v1/rooms/ABCDEF/join", None, {})
        expect(status == 404 and missing["error"] == "ROOM_NOT_FOUND", "http unknown")
        status, health = _http(port, "GET", "/v1/health", None, None)
        expect(status == 200 and health["ok"] is True, "http health")
    finally:
        httpd.shutdown()
        httpd.server_close()


def _expect_error(fn: object, status: int, label: str) -> None:
    try:
        fn()  # type: ignore[operator]
    except S.SignalError as err:
        expect(err.status == status, "%s status %s" % (label, err.status))
        return
    _failures.append("%s did not fail" % label)


def _http(
    port: int,
    method: str,
    path: str,
    token: Optional[str],
    body: Optional[Dict[str, object]],
) -> Tuple[int, Dict[str, object]]:
    data: Optional[bytes] = None if body is None else json.dumps(body).encode("utf-8")
    request: urllib.request.Request = urllib.request.Request(
        "http://127.0.0.1:%d%s" % (port, path),
        data=data,
        method=method,
    )
    if token:
        request.add_header("X-Room-Token", token)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read().decode("utf-8"))


def main() -> int:
    test_room_code_and_exchange()
    test_rejections()
    test_cancel_and_bye()
    test_idle_timeout_without_sleep()
    test_logs_omit_token_and_sdp()
    test_mailbox_limit()
    test_http_roundtrip()
    if _failures:
        print("SIGNAL_SERVER_FAIL %d" % len(_failures))
        for label in _failures:
            print("FAIL %s" % label)
        return 1
    print("SIGNAL_SERVER_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
