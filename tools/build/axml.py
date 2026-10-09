#!/usr/bin/env python3
"""极简 Android 二进制 XML（AXML）读取器。

只做一件事：从 APK 里的 `AndroidManifest.xml`（二进制）中读出**实际声明**的
`<uses-permission>`。存在的理由很具体：`export_presets.cfg` 里的
`permissions/*` 是导出输入，不是证据。历史上 `permissions/internet` 一直是
`false`，但 CI 只检查了「APK 里有 AndroidManifest.xml」，所以配置错了也没人发现。
直接解析编译后的 manifest 才能证明权限真的进了包。

只依赖标准库。不认识的 chunk 直接跳过，格式不对就抛 `AxmlError`（让调用方
FAIL，而不是静默放过）。
"""

from __future__ import annotations

import zipfile
from pathlib import Path
from typing import Dict, Iterator, List, Tuple

RES_STRING_POOL_TYPE = 0x0001
RES_XML_TYPE = 0x0003
RES_XML_START_ELEMENT_TYPE = 0x0102
RES_XML_RESOURCE_MAP_TYPE = 0x0180
RES_XML_END_ELEMENT_TYPE = 0x0103
RES_XML_START_NAMESPACE_TYPE = 0x0100
RES_XML_END_NAMESPACE_TYPE = 0x0101

TYPE_STRING = 0x03

UTF8_FLAG = 0x00000100

NO_INDEX = 0xFFFFFFFF


class AxmlError(ValueError):
    """二进制 manifest 结构不符合预期。"""


def _u16(data: bytes, off: int) -> int:
    return int.from_bytes(data[off : off + 2], "little")


def _u32(data: bytes, off: int) -> int:
    return int.from_bytes(data[off : off + 4], "little")


def _require(data: bytes, off: int, size: int) -> None:
    if off < 0 or size < 0 or off + size > len(data):
        raise AxmlError("越界读取：offset=%d size=%d 总长=%d" % (off, size, len(data)))


def _decode_length8(data: bytes, off: int) -> Tuple[int, int]:
    """UTF-8 字符串 pool 的变长长度（首字节高位续接）。返回 (值, 新偏移)。"""
    _require(data, off, 1)
    value = data[off]
    off += 1
    if value & 0x80:
        _require(data, off, 1)
        value = ((value & 0x7F) << 8) | data[off]
        off += 1
    return value, off


def _decode_utf8_string(data: bytes, pool_start: int, string_off: int) -> str:
    off = pool_start + string_off
    byte_len, off = _decode_length8(data, off)
    _char_len, off = _decode_length8(data, off)  # 第二段是 UTF-16 字符数，用不到
    _require(data, off, byte_len)
    return data[off : off + byte_len].decode("utf-8", errors="replace")


def _decode_utf16_string(data: bytes, pool_start: int, string_off: int) -> str:
    off = pool_start + string_off
    _require(data, off, 2)
    length = _u16(data, off)
    off += 2
    if length & 0x8000:
        _require(data, off, 2)
        length = ((length & 0x7FFF) << 16) | _u16(data, off)
        off += 2
    _require(data, off, length * 2)
    return data[off : off + length * 2].decode("utf-16-le", errors="replace")


def _read_string_pool(data: bytes, chunk_off: int) -> List[str]:
    header_size = _u16(data, chunk_off + 2)
    string_count = _u32(data, chunk_off + 8)
    flags = _u32(data, chunk_off + 16)
    strings_start = _u32(data, chunk_off + 20)
    utf8 = bool(flags & UTF8_FLAG)
    offsets_off = chunk_off + header_size
    _require(data, offsets_off, string_count * 4)
    pool_start = chunk_off + strings_start
    decode = _decode_utf8_string if utf8 else _decode_utf16_string
    strings: List[str] = []
    for index in range(string_count):
        strings.append(decode(data, pool_start, _u32(data, offsets_off + index * 4)))
    return strings


def _decode_value(data: bytes, name: str, raw: int, data_type: int, value: int, strings: List[str]) -> str:
    if data_type == TYPE_STRING and value != NO_INDEX:
        if value >= len(strings):
            raise AxmlError("属性 %s 的字符串索引越界：%d" % (name, value))
        return strings[value]
    if raw != NO_INDEX:
        if raw >= len(strings):
            raise AxmlError("属性 %s 的 raw 索引越界：%d" % (name, raw))
        return strings[raw]
    return str(value)


def _parse_start_element(data: bytes, chunk_off: int, strings: List[str]) -> Tuple[str, Dict[str, str]]:
    # chunk header 8B → lineNumber 4B → comment 4B → ResXMLTree_attrExt
    ext = chunk_off + 16
    name_index = _u32(data, ext + 4)
    attribute_start = _u16(data, ext + 8)
    attribute_size = _u16(data, ext + 10)
    attribute_count = _u16(data, ext + 12)
    if name_index >= len(strings):
        raise AxmlError("元素名索引越界：%d" % name_index)
    attributes: Dict[str, str] = {}
    base = ext + attribute_start
    for index in range(attribute_count):
        attr = base + index * attribute_size
        _require(data, attr, attribute_size)
        attr_name_index = _u32(data, attr + 4)
        raw_value = _u32(data, attr + 8)
        data_type = data[attr + 15]
        typed_value = _u32(data, attr + 16)
        attr_name = strings[attr_name_index] if attr_name_index < len(strings) else ""
        attributes[attr_name] = _decode_value(
            data, attr_name, raw_value, data_type, typed_value, strings
        )
    return strings[name_index], attributes


def elements(data: bytes) -> Iterator[Tuple[str, Dict[str, str]]]:
    """遍历 manifest 里的 START_ELEMENT，产出 (元素名, 属性表)。"""
    if len(data) < 8 or _u16(data, 0) != RES_XML_TYPE:
        raise AxmlError("不是 AXML（缺少 RES_XML 头）")
    total = _u32(data, 4)
    end = min(total, len(data)) if total else len(data)
    strings: List[str] = []
    off = 8
    while off + 8 <= end:
        chunk_type = _u16(data, off)
        chunk_size = _u32(data, off + 4)
        if chunk_size < 8:
            raise AxmlError("chunk size 非法：%d" % chunk_size)
        if chunk_type == RES_STRING_POOL_TYPE:
            strings = _read_string_pool(data, off)
        elif chunk_type == RES_XML_START_ELEMENT_TYPE:
            if not strings:
                raise AxmlError("START_ELEMENT 出现在字符串池之前")
            yield _parse_start_element(data, off, strings)
        off += chunk_size


def declared_permissions(data: bytes) -> List[str]:
    """返回 manifest 里 `<uses-permission>` / `<uses-permission-sdk-23>` 声明的权限名。"""
    permissions: List[str] = []
    for name, attributes in elements(data):
        if name in ("uses-permission", "uses-permission-sdk-23"):
            permission = attributes.get("name")
            if permission:
                permissions.append(permission)
    return permissions


def apk_permissions(apk_path: Path) -> List[str]:
    """从 APK（zip）里读出编译后的 AndroidManifest.xml 声明的权限。"""
    with zipfile.ZipFile(apk_path) as archive:
        names = archive.namelist()
        if "AndroidManifest.xml" not in names:
            raise AxmlError("APK 里没有 AndroidManifest.xml")
        return declared_permissions(archive.read("AndroidManifest.xml"))
