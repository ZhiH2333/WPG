#!/usr/bin/env python3
"""AXML 读取器单元测试。

    python3 tools/test/test_axml.py

`tools/build/axml.py` 是导出校验里唯一直接读**编译后** manifest 的地方，它错
了就会让 CI 对权限给出错误结论（放行或误报）。这里用最小二进制 XML 覆盖最容
易写错的两处：UTF-8 字符串池的变长长度、START_ELEMENT 的属性偏移。
如果本机存在已导出的 APK，再顺带对真实产物跑一遍正向断言。
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path
from typing import List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "build"))

import axml  # noqa: E402

START_ELEMENT = 0x0102
STRING_POOL = 0x0001
XML_TYPE = 0x0003
UTF8_FLAG = 0x100
NO_INDEX = 0xFFFFFFFF
TYPE_STRING = 0x03
ATTR_SIZE = 20
EXT_FIXED = 20


def _string_pool(strings: Sequence[str]) -> bytes:
    data = bytearray()
    offsets: List[int] = []
    for text in strings:
        offsets.append(len(data))
        encoded = text.encode("utf-8")
        assert len(encoded) < 0x80 and len(text) < 0x80, "测试只覆盖短字符串"
        data.append(len(encoded))
        data.append(len(text))
        data += encoded
        data.append(0)
    while len(data) % 4:
        data.append(0)
    header_size = 0x1C
    offsets_bytes = b"".join(offset.to_bytes(4, "little") for offset in offsets)
    strings_start = header_size + len(offsets_bytes)
    chunk_size = strings_start + len(data)
    chunk = bytearray()
    chunk += STRING_POOL.to_bytes(2, "little")
    chunk += header_size.to_bytes(2, "little")
    chunk += chunk_size.to_bytes(4, "little")
    chunk += len(strings).to_bytes(4, "little")
    chunk += (0).to_bytes(4, "little")
    chunk += UTF8_FLAG.to_bytes(4, "little")
    chunk += strings_start.to_bytes(4, "little")
    chunk += (0).to_bytes(4, "little")
    chunk += offsets_bytes
    chunk += data
    return bytes(chunk)


def _start_element(name_index: int, attributes: Sequence[Tuple[int, int, int, int]]) -> bytes:
    ext = bytearray()
    ext += NO_INDEX.to_bytes(4, "little")
    ext += name_index.to_bytes(4, "little")
    ext += EXT_FIXED.to_bytes(2, "little")
    ext += ATTR_SIZE.to_bytes(2, "little")
    ext += len(attributes).to_bytes(2, "little")
    ext += (0).to_bytes(2, "little")
    ext += (0).to_bytes(2, "little")
    ext += (0).to_bytes(2, "little")
    assert len(ext) == EXT_FIXED
    for name_idx, raw, data_type, value in attributes:
        ext += NO_INDEX.to_bytes(4, "little")
        ext += name_idx.to_bytes(4, "little")
        ext += raw.to_bytes(4, "little")
        ext += (8).to_bytes(2, "little")
        ext += (0).to_bytes(1, "little")
        ext += data_type.to_bytes(1, "little")
        ext += value.to_bytes(4, "little")
    body = bytearray()
    body += (0).to_bytes(4, "little")
    body += NO_INDEX.to_bytes(4, "little")
    body += ext
    chunk = bytearray()
    chunk += START_ELEMENT.to_bytes(2, "little")
    chunk += (16).to_bytes(2, "little")
    chunk += (8 + len(body)).to_bytes(4, "little")
    chunk += body
    return bytes(chunk)


def build_manifest(permissions: Sequence[str]) -> bytes:
    strings = ["manifest", "uses-permission", "name", "application", *permissions]
    index = {text: position for position, text in enumerate(strings)}
    chunks = [_string_pool(strings)]
    chunks.append(_start_element(index["manifest"], []))
    for permission in permissions:
        chunks.append(
            _start_element(
                index["uses-permission"],
                [(index["name"], index[permission], TYPE_STRING, index[permission])],
            )
        )
    # 干扰项：另一个元素也叫 name 属性，但不该被当成权限。
    chunks.append(_start_element(index["application"], [(index["name"], NO_INDEX, TYPE_STRING, 0)]))
    body = b"".join(chunks)
    header = bytearray()
    header += XML_TYPE.to_bytes(2, "little")
    header += (8).to_bytes(2, "little")
    header += (8 + len(body)).to_bytes(4, "little")
    return bytes(header) + body


def main() -> int:
    failures: List[str] = []

    def check(label: str, condition: bool) -> None:
        if not condition:
            failures.append(label)

    data = build_manifest(["android.permission.INTERNET", "android.permission.ACCESS_WIFI_STATE"])
    check("解析出全部 uses-permission", axml.declared_permissions(data) == [
        "android.permission.INTERNET",
        "android.permission.ACCESS_WIFI_STATE",
    ])
    check("元素名可读", [name for name, _ in axml.elements(data)][0] == "manifest")
    check("非权限元素被忽略", "application" in [name for name, _ in axml.elements(data)])

    empty = build_manifest([])
    check("无权限时返回空表", axml.declared_permissions(empty) == [])

    try:
        axml.declared_permissions(b"not xml at all")
    except axml.AxmlError:
        pass
    else:
        failures.append("非法输入应抛 AxmlError")

    apks = sorted((ROOT / "artifacts").glob("*android.apk")) if (ROOT / "artifacts").is_dir() else []
    real = apks[-1] if apks else None
    if real is not None:
        declared = axml.apk_permissions(real)
        check("真机产物声明 INTERNET", "android.permission.INTERNET" in declared)
        with zipfile.ZipFile(real) as archive:
            check("真机产物 manifest 可解析", axml.declared_permissions(archive.read("AndroidManifest.xml")) == declared)

    if failures:
        for label in failures:
            print("[FAIL] %s" % label)
        print("[FAIL] AXML unit tests：%d/%d 失败" % (len(failures), len(failures)))
        return 1
    suffix = "（含真实 APK 正向断言）" if real is not None else "（未发现 APK，跳过正向断言）"
    print("[PASS] AXML unit tests%s" % suffix)
    return 0


if __name__ == "__main__":
    sys.exit(main())
