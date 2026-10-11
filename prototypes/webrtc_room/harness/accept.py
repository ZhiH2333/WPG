#!/usr/bin/env python3
"""WebRTC 房间码原型验收。

退出码：
  0  两台不同网络的桌面设备双向数据，并且 TURN 中继路径已被证明
  1  已执行的检查失败
  2  必要的跨网或 TURN 证明没有做成（不是通过）
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from typing import Dict, List, Optional, Tuple

ROOT: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO: str = os.path.dirname(os.path.dirname(ROOT))
GODOT: str = os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/godot")
PYTHON: str = sys.executable


def _ensure_extension_list() -> None:
    folder: str = os.path.join(ROOT, ".godot")
    os.makedirs(folder, exist_ok=True)
    path: str = os.path.join(folder, "extension_list.cfg")
    line: str = "res://addons/webrtc_native/webrtc_native.gdextension\n"
    current: str = ""
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as handle:
            current = handle.read()
    if current != line:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(line)


def main() -> int:
    _ensure_extension_list()
    results: List[Tuple[str, str, str]] = []
    server: Optional[subprocess.Popen] = None
    try:
        results.append(run_script("signaling", [PYTHON, os.path.join(ROOT, "signaling", "test_server.py")]))
        results.append(run_godot_scenario("selftest", ["--scenario=selftest"], 20))
        results.append(run_godot_scenario("extension", ["--scenario=extension"], 20))
        results.append(check_parent_does_not_load_extension())
        server, base = start_signaling()
        work = tempfile.mkdtemp(prefix="wpg-webrtc-")
        results.append(run_pair(base, work, "timeout", 12, expect_data=False))
        results.append(run_pair(base, work, "cancel", 12, expect_data=False))
        results.append(run_pair(base, work, "data", 20, expect_data=True))
        results.append(run_pair(base, work, "disconnect", 25, expect_data=True))
    finally:
        stop_process(server)
    local_failed: bool = any(state == "FAIL" for _name, state, _detail in results)
    turn_state, turn_detail = run_turn()
    results.append(("turn", turn_state, turn_detail))
    results.append(("cross_network", "BLOCKED", "没有第二台处于另一个网络的桌面设备"))
    for name, state, detail in results:
        print("%s %s %s" % (name, state, detail))
    if local_failed or turn_state == "FAIL":
        print("ACCEPTANCE FAIL")
        return 1
    print("ACCEPTANCE BLOCKED")
    return 2


def run_script(name: str, cmd: List[str]) -> Tuple[str, str, str]:
    proc: subprocess.CompletedProcess = subprocess.run(
        cmd,
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    line: str = _last_useful(proc.stdout)
    if proc.returncode == 0:
        return name, "PASS", line
    return name, "FAIL", line or _last_useful(proc.stderr)


def run_godot_scenario(name: str, user_args: List[str], budget: int) -> Tuple[str, str, str]:
    proc, stdout_path, stderr_path = _spawn_godot(user_args, None)
    try:
        code: int = proc.wait(timeout=budget)
    except subprocess.TimeoutExpired:
        stop_process(proc)
        return name, "FAIL", "timeout"
    text: str = _read(stdout_path) + _read(stderr_path)
    if code == 0:
        return name, "PASS", _marker(text) or "exit 0"
    return name, "FAIL", _marker(text) or ("exit %s" % code)


def check_parent_does_not_load_extension() -> Tuple[str, str, str]:
    proc, stdout_path, stderr_path = _spawn_godot(["--quit-after", "1"], REPO, include_separator=False)
    try:
        proc.wait(timeout=25)
    except subprocess.TimeoutExpired:
        stop_process(proc)
        text = _read(stdout_path) + _read(stderr_path)
        if "webrtc_native" in text or "WebRTCLib" in text:
            return "parent_isolation", "FAIL", "main project referenced webrtc before timeout"
        return "parent_isolation", "BLOCKED", "main project did not exit"
    text = _read(stdout_path) + _read(stderr_path)
    if "webrtc_native" in text or "WebRTCLibPeerConnection" in text:
        return "parent_isolation", "FAIL", "main project loaded the prototype extension"
    return "parent_isolation", "PASS", "main project did not load webrtc-native"


def start_signaling() -> Tuple[subprocess.Popen, str]:
    proc: subprocess.Popen = subprocess.Popen(
        [PYTHON, os.path.join(ROOT, "signaling", "server.py"), "--host", "127.0.0.1", "--port", "0"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdout is not None
    line: str = proc.stdout.readline().strip()
    parts: List[str] = line.split()
    if len(parts) != 3 or parts[0] != "LISTEN" or proc.poll() is not None:
        stop_process(proc)
        raise RuntimeError("signaling did not listen: %s" % line)
    return proc, "http://127.0.0.1:%s" % parts[2]


def run_pair(base: str, work: str, scenario: str, budget: int, expect_data: bool) -> Tuple[str, str, str]:
    host_room: str = os.path.join(work, "%s-host.room" % scenario)
    host_result: str = os.path.join(work, "%s-host.json" % scenario)
    guest_result: str = os.path.join(work, "%s-guest.json" % scenario)
    timeout_ms: int = 800 if scenario == "timeout" else 8000 if scenario == "cancel" else 15000
    host_args: List[str] = _session_args("host", scenario, base, "", timeout_ms, host_room, host_result)
    host, host_out, host_err = _spawn_godot(host_args, None)
    if scenario == "timeout":
        state, detail = _wait_one(host, host_result, host_out, host_err, budget, "TIMEOUT", False)
        return scenario, state, detail
    room: str = _wait_room(host, host_room, 10)
    if room == "":
        stop_process(host)
        return scenario, "FAIL", "host did not publish a room code"
    guest_args: List[str] = _session_args("guest", scenario, base, room, timeout_ms, "", guest_result)
    guest, guest_out, guest_err = _spawn_godot(guest_args, None)
    host_state, host_detail = _wait_one(host, host_result, host_out, host_err, budget, _expected(scenario), expect_data)
    guest_state, guest_detail = _wait_one(guest, guest_result, guest_out, guest_err, budget, _expected(scenario), expect_data)
    if host_state == "PASS" and guest_state == "PASS":
        return scenario, "PASS", "room %s" % room
    return scenario, "FAIL", "host %s; guest %s" % (host_detail, guest_detail)


def run_turn() -> Tuple[str, str]:
    script: str = os.path.join(ROOT, "harness", "turn_isolation.py")
    if not os.path.isfile(script):
        return "BLOCKED", "missing turn harness"
    proc: subprocess.CompletedProcess = subprocess.run(
        [PYTHON, script],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=600,
    )
    line: str = _last_useful(proc.stdout) or _last_useful(proc.stderr)
    if proc.returncode == 0:
        return "PASS", line
    if proc.returncode == 2:
        return "BLOCKED", line
    return "FAIL", line


def _session_args(
    role: str,
    scenario: str,
    base: str,
    room: str,
    timeout_ms: int,
    room_file: str,
    result_file: str,
) -> List[str]:
    args: List[str] = [
        "--role=%s" % role,
        "--scenario=%s" % scenario,
        "--signaling=%s" % base,
        "--mode=direct",
        "--connect-timeout-ms=%d" % timeout_ms,
        "--result-file=%s" % result_file,
    ]
    if room:
        args.append("--room=%s" % room)
    if room_file:
        args.append("--room-file=%s" % room_file)
    return args


def _expected(scenario: str) -> str:
    if scenario == "data":
        return "DATA_OK"
    if scenario == "disconnect":
        return "DISCONNECTED_OK"
    if scenario == "cancel":
        return "CANCELLED"
    return "TIMEOUT"


def _wait_room(proc: subprocess.Popen, path: str, budget: int) -> str:
    deadline: float = time.monotonic() + budget
    while time.monotonic() < deadline:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            with open(path, "r", encoding="utf-8") as handle:
                room: str = handle.read().strip()
            if room:
                return room
        if proc.poll() is not None:
            return ""
        time.sleep(0.05)
    return ""


def _wait_one(
    proc: subprocess.Popen,
    result_path: str,
    stdout_path: str,
    stderr_path: str,
    budget: int,
    expected: str,
    expect_data: bool,
) -> Tuple[str, str]:
    try:
        code: int = proc.wait(timeout=budget)
    except subprocess.TimeoutExpired:
        stop_process(proc)
        return "FAIL", "timeout"
    if not os.path.isfile(result_path):
        return "FAIL", _marker(_read(stdout_path) + _read(stderr_path)) or ("exit %s" % code)
    with open(result_path, "r", encoding="utf-8") as handle:
        result: Dict[str, object] = json.loads(handle.read())
    status: str = str(result.get("status", ""))
    data_open: bool = bool(result.get("data_was_open", False))
    if code != 0 or status != expected:
        return "FAIL", "%s %s" % (status, result.get("error", ""))
    if expect_data and (not data_open or not result.get("pong_seen") or not result.get("ping_seen")):
        return "FAIL", "data flags missing"
    if not expect_data and data_open:
        return "FAIL", "data opened"
    if expected == "TIMEOUT":
        elapsed: int = int(result.get("elapsed_ms", 0))
        if elapsed < 700:
            return "FAIL", "returned before deadline %s" % elapsed
    return "PASS", status


def _spawn_godot(
    user_args: List[str],
    path: Optional[str],
    include_separator: bool = True,
) -> Tuple[subprocess.Popen, str, str]:
    project: str = path if path is not None else ROOT
    stdout_file = tempfile.NamedTemporaryFile(prefix="wpg-godot-out-", delete=False)
    stderr_file = tempfile.NamedTemporaryFile(prefix="wpg-godot-err-", delete=False)
    stdout_file.close()
    stderr_file.close()
    cmd: List[str] = [GODOT, "--headless", "--path", project]
    if include_separator:
        cmd.append("--")
    cmd.extend(user_args)
    proc: subprocess.Popen = subprocess.Popen(
        cmd,
        stdout=open(stdout_file.name, "w", encoding="utf-8"),
        stderr=open(stderr_file.name, "w", encoding="utf-8"),
    )
    return proc, stdout_file.name, stderr_file.name


def stop_process(proc: Optional[subprocess.Popen]) -> None:
    if proc is None or proc.poll() is not None:
        return
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()


def _read(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def _last_useful(text: str) -> str:
    lines: List[str] = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return ""
    return lines[-1][:240]


def _marker(text: str) -> str:
    for line in reversed(text.splitlines()):
        stripped: str = line.strip()
        if stripped.startswith("RESULT") or stripped.startswith("EXTENSION_") or stripped.startswith("SELFTEST_") or stripped.startswith("ERROR"):
            return stripped[:240]
    return _last_useful(text)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as err:
        print("harness FAIL %s" % err)
        sys.exit(1)
