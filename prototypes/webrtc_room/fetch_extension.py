#!/usr/bin/env python3
"""按 UPSTREAM.txt 下载并校验 webrtc-native 1.2.2，解压到本原型。"""

from __future__ import annotations

import hashlib
import os
import sys
import urllib.request
import zipfile
from typing import Dict

ROOT: str = os.path.dirname(os.path.abspath(__file__))
PIN: str = os.path.join(ROOT, "addons", "webrtc_native", "UPSTREAM.txt")
MARKER: str = os.path.join(
    ROOT,
    "addons",
    "webrtc_native",
    "lib",
    "libwebrtc_native.macos.template_debug.universal.framework",
    "libwebrtc_native.macos.template_debug.universal.dylib",
)


def main() -> int:
    pin: Dict[str, str] = _read_pin(PIN)
    if os.path.isfile(MARKER):
        _ensure_extension_list()
        print("EXTENSION_PRESENT")
        return 0
    archive: str = os.path.join(ROOT, pin["file"])
    urllib.request.urlretrieve(pin["url"], archive)
    digest: str = hashlib.sha256(open(archive, "rb").read()).hexdigest()
    if digest != pin["sha256"]:
        os.remove(archive)
        print("EXTENSION_HASH_MISMATCH")
        return 1
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(ROOT)
    os.remove(archive)
    _ensure_extension_list()
    print("EXTENSION_FETCHED %s" % pin["tag"])
    return 0


def _ensure_extension_list() -> None:
    folder: str = os.path.join(ROOT, ".godot")
    os.makedirs(folder, exist_ok=True)
    path: str = os.path.join(folder, "extension_list.cfg")
    line: str = "res://addons/webrtc_native/webrtc_native.gdextension\n"
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(line)


def _read_pin(path: str) -> Dict[str, str]:
    pin: Dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line: str = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            pin[key] = value
    return pin


if __name__ == "__main__":
    sys.exit(main())
