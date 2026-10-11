#!/usr/bin/env python3
"""用两台不能直连的 Linux 容器证明数据走 TURN。

这不是两台桌面设备，也不是公网验收。
Docker 不可用时返回 2（BLOCKED），不记为通过。
直连对照若意外成功，返回 1，避免把 host candidate 当成中继。
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from typing import Dict, List

ROOT: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NETWORK: str = "wpgwebrtc"
TURN_NAME: str = "wpgwebrtc-turn"
SIGNAL_NAME: str = "wpgwebrtc-signal"
IMAGE: str = "wpgwebrtc-peer"
TURN_USER: str = "wpg"
TURN_SECRET: str = "wpgturnsecret"
GODOT_VERSION: str = "4.6.2"


def main() -> int:
    if shutil.which("docker") is None:
        print("TURN_ISOLATION BLOCKED docker CLI missing")
        return 2
    if not _docker_ok():
        print("TURN_ISOLATION BLOCKED docker daemon is not running")
        return 2
    arch: str = _docker_arch()
    if arch not in ("aarch64", "arm64", "x86_64", "amd64"):
        print("TURN_ISOLATION BLOCKED unsupported docker arch %s" % arch)
        return 2
    work: str = tempfile.mkdtemp(prefix="wpg-turn-")
    try:
        _cleanup()
        subprocess.check_call(["docker", "network", "create", NETWORK], stdout=subprocess.DEVNULL)
        _build_peer_image()
        godot: str = _ensure_godot(arch)
        turn_ip: str = _start_turn()
        signal_port: str = _start_signal()
        signal_ip: str = _container_ip(SIGNAL_NAME)
        _wait_health(signal_port)
        direct: Dict[str, object] = _run_case("direct", work, godot, turn_ip, signal_ip, 8000, 20)
        if str(direct.get("status", "")) == "DATA_OK" or bool(direct.get("data_was_open", False)):
            _dump_debug()
            print("TURN_ISOLATION FAIL direct path was not blocked")
            return 1
        turned: Dict[str, object] = _run_case("turn", work, godot, turn_ip, signal_ip, 20000, 40)
        relay: int = int(turned.get("relay_candidates", 0))
        if turned.get("status") != "DATA_OK" or relay < 1 or not turned.get("pong_seen") or not turned.get("ping_seen"):
            _dump_debug()
            print("TURN_ISOLATION FAIL turn status=%s relay=%s error=%s" % (turned.get("status"), relay, turned.get("error", "")))
            return 1
        print("TURN_ISOLATION PASS relay_candidates=%s direct_blocked=yes" % relay)
        return 0
    except Exception as err:
        _dump_debug()
        print("TURN_ISOLATION FAIL %s" % err)
        return 1
    finally:
        _cleanup()
        shutil.rmtree(work, ignore_errors=True)


def _docker_ok() -> bool:
    proc: subprocess.CompletedProcess = subprocess.run(
        ["docker", "info"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc.returncode == 0


def _docker_arch() -> str:
    proc: subprocess.CompletedProcess = subprocess.run(
        ["docker", "info", "-f", "{{.Architecture}}"],
        text=True,
        capture_output=True,
        check=True,
    )
    return proc.stdout.strip()


def _build_peer_image() -> None:
    subprocess.check_call(
        ["docker", "build", "-t", IMAGE, os.path.join(ROOT, "docker")],
        stdout=subprocess.DEVNULL,
    )


def _ensure_godot(arch: str) -> str:
    linux_arch: str = "arm64" if arch in ("aarch64", "arm64") else "x86_64"
    name: str = "Godot_v%s-stable_linux.%s" % (GODOT_VERSION, linux_arch)
    cache: str = os.path.join(tempfile.gettempdir(), "wpg-godot-cache")
    os.makedirs(cache, exist_ok=True)
    destination: str = os.path.join(cache, name)
    if not os.path.isfile(destination):
        url: str = "https://github.com/godotengine/godot/releases/download/%s-stable/%s.zip" % (GODOT_VERSION, name)
        archive: str = os.path.join(cache, name + ".zip")
        urllib.request.urlretrieve(url, archive)
        subprocess.check_call(["unzip", "-q", archive, "-d", cache])
    os.chmod(destination, 0o755)
    return destination


def _start_turn() -> str:
    # 新版 coturn 不认识 --no-dtls，带上会直接退出。
    # 容器退出后 Docker 会把空 IP 渲染成 "invalid IP"，不能拿来当 TURN 地址。
    script: str = (
        "IP=$(hostname -i | awk '{print $1}'); "
        "exec turnserver -n --log-file=stdout --listening-port=3478 "
        "--min-port=49160 --max-port=49200 --lt-cred-mech "
        "--user=%s:%s --realm=wpg.local --fingerprint "
        "--external-ip=$IP --relay-ip=$IP --listening-ip=0.0.0.0"
        % (TURN_USER, TURN_SECRET)
    )
    subprocess.check_call(
        [
            "docker", "run", "-d", "--name", TURN_NAME, "--network", NETWORK,
            "--entrypoint", "sh", "coturn/coturn", "-c", script,
        ],
        stdout=subprocess.DEVNULL,
    )
    deadline: float = time.monotonic() + 15
    while time.monotonic() < deadline:
        if _container_status(TURN_NAME) == "running":
            ip: str = _container_ip(TURN_NAME)
            if _is_ipv4(ip):
                return ip
        time.sleep(0.2)
    raise RuntimeError("coturn did not stay up")


def _is_ipv4(value: str) -> bool:
    parts: List[str] = value.split(".")
    if len(parts) != 4:
        return False
    for part in parts:
        if not part.isdigit() or int(part) > 255:
            return False
    return True


def _container_status(name: str) -> str:
    proc: subprocess.CompletedProcess = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Status}}", name],
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def _start_signal() -> str:
    proc: subprocess.CompletedProcess = subprocess.run(
        [
            "docker", "run", "-d", "--name", SIGNAL_NAME, "--network", NETWORK,
            "-p", "127.0.0.1::8787",
            "-v", "%s:/srv:ro" % os.path.join(ROOT, "signaling"),
            "python:3.12-slim",
            "python3", "/srv/server.py", "--host", "0.0.0.0", "--port", "8787",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    del proc
    inspect: subprocess.CompletedProcess = subprocess.run(
        ["docker", "port", SIGNAL_NAME, "8787/tcp"],
        text=True,
        capture_output=True,
        check=True,
    )
    return inspect.stdout.strip().rsplit(":", 1)[-1]


def _wait_health(port: str) -> None:
    deadline: float = time.monotonic() + 20
    url: str = "http://127.0.0.1:%s/v1/health" % port
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                body: Dict[str, object] = json.loads(response.read().decode("utf-8"))
            if body.get("ok") is True:
                return
        except Exception:
            pass
        time.sleep(0.1)
    raise RuntimeError("signaling health failed")


def _run_case(
    mode: str,
    work: str,
    godot: str,
    turn_ip: str,
    signal_ip: str,
    timeout_ms: int,
    budget: int,
) -> Dict[str, object]:
    case_dir: str = os.path.join(work, mode)
    os.makedirs(case_dir, exist_ok=True)
    host_name: str = "wpgwebrtc-%s-host" % mode
    guest_name: str = "wpgwebrtc-%s-guest" % mode
    _remove(host_name)
    _remove(guest_name)
    _start_peer(host_name, mode, "host", godot, turn_ip, signal_ip, timeout_ms, case_dir)
    _start_peer(guest_name, mode, "guest", godot, turn_ip, signal_ip, timeout_ms, case_dir)
    host_ip: str = _await_ip(host_name)
    guest_ip: str = _await_ip(guest_name)
    _write(os.path.join(case_dir, "host.drop"), guest_ip)
    _write(os.path.join(case_dir, "guest.drop"), host_ip)
    host_code: int = _docker_wait(host_name, budget)
    guest_code: int = _docker_wait(guest_name, budget)
    host_result: Dict[str, object] = _read_result(os.path.join(case_dir, "host.json"))
    guest_result: Dict[str, object] = _read_result(os.path.join(case_dir, "guest.json"))
    if mode == "direct":
        if host_result.get("status") == "DATA_OK" or guest_result.get("status") == "DATA_OK":
            return {"status": "DATA_OK", "data_was_open": True}
        return {"status": "BLOCKED_DIRECT", "data_was_open": False, "host_exit": host_code, "guest_exit": guest_code}
    if host_code != 0 or guest_code != 0:
        return host_result or {"status": "FAILED", "relay_candidates": 0}
    if host_result.get("status") != "DATA_OK":
        return host_result
    relay: int = int(host_result.get("relay_candidates", 0)) + int(guest_result.get("relay_candidates", 0))
    host_result["relay_candidates"] = relay
    host_result["ping_seen"] = bool(host_result.get("ping_seen")) and bool(guest_result.get("ping_seen"))
    host_result["pong_seen"] = bool(host_result.get("pong_seen")) and bool(guest_result.get("pong_seen"))
    return host_result


def _start_peer(
    name: str,
    mode: str,
    role: str,
    godot: str,
    turn_ip: str,
    signal_ip: str,
    timeout_ms: int,
    case_dir: str,
) -> None:
    args: List[str] = [
        "docker", "run", "-d", "--name", name, "--network", NETWORK,
        "--cap-add", "NET_ADMIN",
        "-v", "%s:/opt/godot/godot:ro" % godot,
        "-v", "%s:/work" % ROOT,
        "-v", "%s:/results" % case_dir,
        IMAGE,
        "sh", "-c", _peer_command(mode, role, turn_ip, signal_ip, timeout_ms),
    ]
    subprocess.check_call(args, stdout=subprocess.DEVNULL)


def _peer_command(mode: str, role: str, turn_ip: str, signal_ip: str, timeout_ms: int) -> str:
    room_file: str = " --room-file=/results/host.room" if role == "host" else ""
    room_arg: str = "" if role == "host" else ' --room="$ROOM"'
    turn_args: str = ""
    if mode == "turn":
        turn_args = " --turn-url=turn:%s:3478 --turn-user=%s --turn-credential=%s" % (turn_ip, TURN_USER, TURN_SECRET)
    wait: str = "while [ ! -s /results/%s.drop ]; do sleep 0.05; done; " % role
    if role == "guest":
        wait += "while [ ! -s /results/host.room ]; do sleep 0.05; done; ROOM=$(cat /results/host.room); "
    return (
        wait +
        "PEER=$(cat /results/%s.drop); "
        "iptables -I OUTPUT -d \"$PEER\" -j DROP; "
        "iptables -I INPUT -s \"$PEER\" -j DROP; "
        "ip6tables -P OUTPUT DROP || true; "
        "ip6tables -P INPUT DROP || true; "
        "exec /opt/godot/godot --headless --path /work -- "
        "--role=%s --scenario=data --mode=%s --signaling=http://%s:8787 "
        "--connect-timeout-ms=%d --result-file=/results/%s.json%s%s%s"
        % (role, role, mode, signal_ip, timeout_ms, role, room_file, room_arg, turn_args)
    )


def _write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def _wait_room(path: str, budget: int) -> str:
    deadline: float = time.monotonic() + budget
    while time.monotonic() < deadline:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            with open(path, "r", encoding="utf-8") as handle:
                room: str = handle.read().strip()
            if room:
                return room
        time.sleep(0.05)
    return ""


def _docker_wait(name: str, budget: int) -> int:
    proc: subprocess.CompletedProcess = subprocess.run(
        ["docker", "wait", name],
        text=True,
        capture_output=True,
        timeout=budget,
    )
    if proc.returncode != 0:
        return 1
    try:
        return int(proc.stdout.strip())
    except ValueError:
        return 1


def _read_result(path: str) -> Dict[str, object]:
    if not os.path.isfile(path):
        return {}
    with open(path, "r", encoding="utf-8") as handle:
        parsed: object = json.loads(handle.read())
    if isinstance(parsed, dict):
        return parsed
    return {}


def _await_ip(name: str) -> str:
    deadline: float = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            return _container_ip(name)
        except Exception:
            time.sleep(0.1)
    raise RuntimeError("no ip for %s" % name)


def _container_ip(name: str) -> str:
    proc: subprocess.CompletedProcess = subprocess.run(
        ["docker", "inspect", "-f", "{{(index .NetworkSettings.Networks \"%s\").IPAddress}}" % NETWORK, name],
        text=True,
        capture_output=True,
        check=True,
    )
    ip: str = proc.stdout.strip()
    if not _is_ipv4(ip):
        raise RuntimeError("no ip for %s" % name)
    return ip


def _dump_debug() -> None:
    names: List[str] = [
        TURN_NAME,
        SIGNAL_NAME,
        "wpgwebrtc-direct-host",
        "wpgwebrtc-direct-guest",
        "wpgwebrtc-turn-host",
        "wpgwebrtc-turn-guest",
    ]
    for name in names:
        proc: subprocess.CompletedProcess = subprocess.run(
            ["docker", "logs", "--tail", "30", name],
            text=True,
            capture_output=True,
        )
        text: str = "\n".join((proc.stdout + proc.stderr).splitlines()[-12:])
        if text.strip():
            print("LOG %s" % name)
            print(text)


def _remove(name: str) -> None:
    subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _cleanup() -> None:
    for name in (TURN_NAME, SIGNAL_NAME, "wpgwebrtc-direct-host", "wpgwebrtc-direct-guest", "wpgwebrtc-turn-host", "wpgwebrtc-turn-guest"):
        _remove(name)
    subprocess.run(["docker", "network", "rm", NETWORK], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    sys.exit(main())
