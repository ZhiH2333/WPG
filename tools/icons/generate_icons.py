#!/usr/bin/env python3
"""从 wpg.icon（Apple Icon Composer 文档）生成全平台应用图标。

设计要点
--------
* Apple 平台走**原生**链路：调用 Xcode 自带的 `ictool`（Icon Composer CLI）渲染
  iOS / macOS 的 Default、Dark、TintedLight、TintedDark、ClearLight、ClearDark 六种外观。
  这样深色、着色（iOS 18+ Tinted）、清晰（iOS 26 Clear）图标在 iOS/iPadOS/macOS 上
  由系统原生适配，而不是我们自己调色。
* macOS 额外保留 `wpg.icon` 本体：Godot 4.6 的 `application/liquid_glass_icon`
  会把它交给 `actool` 编译成 Assets.car，得到 macOS 26 液态玻璃图标（含深浅色/着色）。
* Android / Windows / Web / Linux 从原生渲染派生。前景素材用 icon.json 描述的
  图层几何精确重建（缩放 1.21、平移 (-53, 70) 点），因此元素的**比例与位置与
  Icon Composer 完全一致**，只是按各平台规范重新排布背景与圆角。
* 全部产物写入 `icons/`。生成出来的子目录带 `.gdignore`：它们是导出期素材，不应被
  Godot 当游戏资源导入（否则每种外观的 1~2 MB PNG 会被打进每个平台的 PCK）。
  `icons/` 根目录保持可导入，因为 `logo.png` 是运行时要用到的 boot splash。

用法
----
    python3 tools/icons/generate_icons.py            # 重新生成全部图标
    python3 tools/icons/generate_icons.py --list     # 只列出分组，不写文件
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ICON_BUNDLE = ROOT / "wpg.icon"
OUT_DIR = ROOT / "icons"

# Icon Composer 文档的正方形画布（supported-platforms.squares = shared）。
CANVAS = 1024

ICTOOL_CANDIDATES = (
    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool",
    "/Applications/Icon Composer.app/Contents/Executables/ictool",
)

# iOS App Icon 规格：(文件名后缀, 像素尺寸, 点尺寸, 缩放)。
# 与 Godot 4.6 iOS 导出插件的图标表一一对应。
IOS_ICON_SIZES: Tuple[Tuple[str, int, str, str], ...] = (
    ("Icon-20@2x", 40, "20x20", "2x"),
    ("Icon-20@3x", 60, "20x20", "3x"),
    ("Icon-29@2x", 58, "29x29", "2x"),
    ("Icon-29@3x", 87, "29x29", "3x"),
    ("Icon-38@2x", 76, "38x38", "2x"),
    ("Icon-38@3x", 114, "38x38", "3x"),
    ("Icon-40@2x", 80, "40x40", "2x"),
    ("Icon-40@3x", 120, "40x40", "3x"),
    ("Icon-60@2x", 120, "60x60", "2x"),
    ("Icon-60@3x", 180, "60x60", "3x"),
    ("Icon-64@2x", 128, "64x64", "2x"),
    ("Icon-64@3x", 192, "64x64", "3x"),
    ("Icon-68@2x", 136, "68x68", "2x"),
    ("Icon-76@2x", 152, "76x76", "2x"),
    ("Icon-83.5@2x", 167, "83.5x83.5", "2x"),
    ("Icon-1024", 1024, "1024x1024", "1x"),
)

# macOS .iconset 规格：(文件名, 像素尺寸)。
MACOS_ICONSET = (
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
)

WINDOWS_ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)

# Android 自适应图标：108 dp 画布，只有中间 72 dp（安全区）保证可见。
ANDROID_ADAPTIVE_PX = 432
ANDROID_SAFE_RATIO = 72.0 / 108.0

ANDROID_MIPMAPS = (
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
)

# 开屏字标在 icons/splash.png 画布里占的宽度比例（0.5 = 比原来的满宽小一半）。
# ui/boot_screen.gd 用的是同一张图，所以它不需要知道这个值。
SPLASH_LOGO_RATIO = 0.5


class IconError(RuntimeError):
    """生成过程中不可恢复的错误。"""


# --------------------------------------------------------------------------- #
# 原生渲染
# --------------------------------------------------------------------------- #

def find_ictool() -> Path:
    override = os.environ.get("ICTOOL", "").strip()
    if override:
        path = Path(override)
        if path.is_file():
            return path
        raise IconError("ICTOOL 指向的文件不存在：%s" % override)
    for candidate in ICTOOL_CANDIDATES:
        path = Path(candidate)
        if path.is_file():
            return path
    found = shutil.which("ictool")
    if found:
        return Path(found)
    raise IconError(
        "找不到 ictool（Icon Composer CLI）。请安装 Xcode 26+，"
        "或用 ICTOOL=/path/to/ictool 指定。"
    )


class ComposerRenderer:
    """调用 ictool 渲染 wpg.icon，并缓存结果。"""

    def __init__(self, ictool: Path, bundle: Path) -> None:
        self.ictool = ictool
        self.bundle = bundle
        self._cache: Dict[Tuple[str, str, int], Image.Image] = {}
        self._tmp = Path(tempfile.mkdtemp(prefix="wpg-icons-"))

    def close(self) -> None:
        shutil.rmtree(self._tmp, ignore_errors=True)

    def render(self, platform: str, rendition: str, size: int = CANVAS) -> Image.Image:
        key = (platform, rendition, size)
        cached = self._cache.get(key)
        if cached is not None:
            return cached.copy()

        out = self._tmp / ("%s-%s-%d.png" % (platform, rendition, size))
        proc = subprocess.run(
            [
                str(self.ictool),
                str(self.bundle),
                "--export-image",
                "--output-file",
                str(out),
                "--platform",
                platform,
                "--rendition",
                rendition,
                "--width",
                str(size),
                "--height",
                str(size),
                "--scale",
                "1",
            ],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0 or not out.is_file():
            raise IconError(
                "ictool 渲染失败（%s/%s %dpx）：%s"
                % (platform, rendition, size, (proc.stderr or proc.stdout or "").strip()[:400])
            )
        image = Image.open(out).convert("RGBA")
        out.unlink(missing_ok=True)
        if image.size != (size, size):
            image = image.resize((size, size), Image.Resampling.LANCZOS)
        self._cache[key] = image.copy()
        return image


# --------------------------------------------------------------------------- #
# 图层几何：精确复现 Icon Composer 的合成
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class LayerGeometry:
    """icon.json 里可见图层的几何，单位为 1024 画布上的像素。"""

    image: Image.Image
    offset_x: float
    offset_y: float
    width: float
    height: float


def load_layer_geometry(bundle: Path = ICON_BUNDLE) -> LayerGeometry:
    """读取 icon.json 的可见图层，推导它在 1024 画布上的位置。

    与 ictool 输出逐像素比对验证过：缩放 1.21、平移 (-53, 70) 点，
    即 top-left = 512 - (w*1.21)/2 + tx, 512 - (h*1.21)/2 + ty。
    """
    config = json.loads((bundle / "icon.json").read_text(encoding="utf-8"))
    group = (config.get("groups") or [{}])[0]
    visible = [
        layer
        for layer in group.get("layers", [])
        if not layer.get("hidden", False) and layer.get("image-name")
    ]
    if not visible:
        raise IconError("wpg.icon/icon.json 里没有可见图层")
    # 数组靠后的图层在上层，取最上面那个带图像的。
    layer = visible[-1]

    image = Image.open(bundle / "Assets" / layer["image-name"]).convert("RGBA")
    position = layer.get("position") or {}
    scale = float(position.get("scale", 1.0))
    tx, ty = (float(v) for v in position.get("translation-in-points", [0.0, 0.0]))
    width = image.width * scale
    height = image.height * scale
    return LayerGeometry(
        image=image,
        offset_x=CANVAS / 2.0 - width / 2.0 + tx,
        offset_y=CANVAS / 2.0 - height / 2.0 + ty,
        width=width,
        height=height,
    )


def layer_alpha(geometry: LayerGeometry) -> Image.Image:
    """图层在 1024 画布上的 alpha 蒙版（用于把背景色从渲染图里分离出来）。"""
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    scaled = geometry.image.resize(
        (max(1, round(geometry.width)), max(1, round(geometry.height))),
        Image.Resampling.LANCZOS,
    )
    mask.paste(scaled.getchannel("A"), (round(geometry.offset_x), round(geometry.offset_y)))
    return mask


def compose_layer(
    geometry: LayerGeometry,
    canvas: int,
    box_origin: float,
    box_size: float,
) -> Image.Image:
    """把图层放到 canvas 上。

    box_origin / box_size 描述「1024 画布」映射到目标图的位置与边长。图层允许溢出
    该方框（Android 自适应图标需要，否则会在安全区边界留下硬切口）。
    """
    k = box_size / float(CANVAS)
    width = max(1, round(geometry.width * k))
    height = max(1, round(geometry.height * k))
    scaled = geometry.image.resize((width, height), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(scaled, (round(box_origin + geometry.offset_x * k), round(box_origin + geometry.offset_y * k)))
    return out


def compose_full_bleed(geometry: LayerGeometry, color: Tuple[int, int, int]) -> Image.Image:
    """满幅不透明合成：纯色底 + 图层按原位摆放，不做圆角裁切。

    用于 App Store、Google Play、PWA 与 apple-touch-icon —— 这些位置由系统自己
    套用圆角/圆形蒙版，提前切圆角会导致二次裁切。
    """
    canvas = Image.new("RGBA", (CANVAS, CANVAS), color + (255,))
    k = 1.0
    scaled = geometry.image.resize(
        (max(1, round(geometry.width * k)), max(1, round(geometry.height * k))),
        Image.Resampling.LANCZOS,
    )
    canvas.alpha_composite(scaled, (round(geometry.offset_x), round(geometry.offset_y)))
    return canvas


def background_color(rendered: Image.Image, alpha: Image.Image) -> Tuple[int, int, int]:
    """从原生渲染里采样纯背景色（用于 Android 自适应图标背景层）。

    渲染图带极轻的内高光渐变，这里取背景像素的中位数，得到平台侧需要的纯色。
    """
    render = rendered.convert("RGBA")
    pixels = render.load()
    mask = alpha.load()
    samples: List[Tuple[int, int, int]] = []
    step = 3
    margin = 24
    for y in range(margin, CANVAS - margin, step):
        for x in range(margin, CANVAS - margin, step):
            if pixels[x, y][3] < 250:  # 圆角外的透明区
                continue
            if mask[x, y] > 8:  # 被图层覆盖
                continue
            # 排除贴着圆角边缘的阴影过渡带
            neighbours = (
                pixels[min(x + 12, CANVAS - 1), y][3],
                pixels[x, min(y + 12, CANVAS - 1)][3],
                pixels[max(x - 12, 0), y][3],
                pixels[x, max(y - 12, 0)][3],
            )
            if min(neighbours) < 250:
                continue
            samples.append(pixels[x, y][:3])
    if not samples:
        raise IconError("无法从渲染图采样背景色")
    samples.sort(key=lambda c: c[0] + c[1] + c[2])
    return samples[len(samples) // 2]


# --------------------------------------------------------------------------- #
# 通用工具
# --------------------------------------------------------------------------- #

def resize(image: Image.Image, size: int) -> Image.Image:
    if image.size == (size, size):
        return image.copy()
    return image.resize((size, size), Image.Resampling.LANCZOS)


def write_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def write_ico(image: Image.Image, path: Path, sizes: Sequence[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "ICO", sizes=[(s, s) for s in sizes])


def flatten(image: Image.Image, color: Tuple[int, int, int]) -> Image.Image:
    """把带透明通道的图标压到不透明底色上（App Store / maskable / 旧版启动图标需要）。"""
    base = Image.new("RGBA", image.size, color + (255,))
    base.alpha_composite(image.convert("RGBA"))
    return base


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------- #
# 各平台产物
# --------------------------------------------------------------------------- #

class IconBuilder:
    """把 wpg.icon 的原生渲染翻译成各平台需要的形状。"""

    def __init__(self, renderer: ComposerRenderer) -> None:
        self.geometry = load_layer_geometry()

        self.light = renderer.render("iOS", "Default")
        self.dark = renderer.render("iOS", "Dark")
        self.tinted = renderer.render("iOS", "TintedDark")

        self.macos = {
            name: renderer.render("macOS", name) for name in ("Default", "Dark", "TintedDark")
        }

        alpha = layer_alpha(self.geometry)
        self.bg_light = background_color(self.light, alpha)
        self.bg_dark = background_color(self.dark, alpha)
        self.bg_tinted = background_color(self.tinted, alpha)

        # 满幅不透明版本：给由系统自己套蒙版的位置（App Store / Play / PWA / apple-touch-icon）。
        self.bleed_light = compose_full_bleed(self.geometry, self.bg_light)
        self.bleed_dark = compose_full_bleed(self.geometry, self.bg_dark)
        self.bleed_tinted = compose_full_bleed(self.geometry, self.bg_tinted)

    # -- 通用 -----------------------------------------------------------------

    def app_icon(self) -> None:
        """project.godot 的 application/config/icon（编辑器 / Linux 窗口 / Web favicon）。

        该文件会被 Godot 当资源导入并打进 PCK，所以放在项目根目录。
        """
        write_png(resize(self.bleed_light, 512), ROOT / "icon.png")

    def splash(self) -> None:
        """开屏底图：把 icons/logo.png 放进一张透明画布，字标只占宽度的一半。

        Godot 的 boot_splash 没有「缩放百分比」，只能靠留白把字标改小。画布取 logo 的
        整数倍并居中，`ui/boot_screen.gd` 用同一张图、同一套 Keep Width 规则绘制，
        所以引擎启动图切到开屏场景时画面不会跳。
        """
        source = OUT_DIR / "logo.png"
        if not source.is_file():
            raise IconError("找不到开屏素材 %s" % source.relative_to(ROOT))
        logo = Image.open(source).convert("RGBA")
        canvas = Image.new(
            "RGBA",
            (
                max(1, round(logo.width / SPLASH_LOGO_RATIO)),
                max(1, round(logo.height / SPLASH_LOGO_RATIO)),
            ),
            (0, 0, 0, 0),
        )
        canvas.alpha_composite(
            logo, ((canvas.width - logo.width) // 2, (canvas.height - logo.height) // 2)
        )
        write_png(canvas, OUT_DIR / "splash.png")

    # -- Apple ----------------------------------------------------------------

    def apple(self) -> None:
        self._ios()
        self._macos()

    def _ios(self) -> None:
        out = OUT_DIR / "ios"
        write_png(self.light, out / "icon-1024.png")
        write_png(self.dark, out / "icon-1024_dark.png")
        write_png(self.tinted, out / "icon-1024_tinted.png")
        # 走 App Store 的 1024 必须不透明；用满幅版本，且不让 Godot 用 boot splash 底色补。
        write_png(self.bleed_light, out / "appstore-1024.png")
        write_png(self.bleed_dark, out / "appstore-1024_dark.png")
        write_png(self.bleed_tinted, out / "appstore-1024_tinted.png")

        # 完整 AppIcon.appiconset（含 iOS 18 深色 / 着色外观），Xcode 原生工程可直接使用。
        appiconset = out / "AppIcon.appiconset"
        contents: Dict[str, object] = {"images": [], "info": {"author": "wpg", "version": 1}}
        images: List[Dict[str, object]] = contents["images"]  # type: ignore[assignment]
        for name, size, points, scale in IOS_ICON_SIZES:
            for suffix, source, appearance in (
                ("", self.bleed_light, None),
                ("_dark", self.bleed_dark, "dark"),
                ("_tinted", self.bleed_tinted, "tinted"),
            ):
                filename = "%s%s.png" % (name, suffix)
                write_png(resize(source, size), appiconset / filename)
                entry: Dict[str, object] = {
                    "filename": filename,
                    "idiom": "universal",
                    "platform": "ios",
                    "size": points,
                }
                if scale != "1x":
                    entry["scale"] = scale
                if appearance:
                    entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
                images.append(entry)
        write_json(appiconset / "Contents.json", contents)

    def _macos(self) -> None:
        out = OUT_DIR / "macos"
        write_png(self.macos["Default"], out / "icon-1024.png")
        write_png(self.macos["Dark"], out / "icon-1024_dark.png")

        iconutil = shutil.which("iconutil")
        if iconutil is None:
            raise IconError("找不到 iconutil，无法生成 macOS icon.icns（需要 macOS）")
        with tempfile.TemporaryDirectory(prefix="wpg-iconset-") as tmp:
            iconset = Path(tmp) / "AppIcon.iconset"
            for filename, size in MACOS_ICONSET:
                write_png(resize(self.macos["Default"], size), iconset / filename)
            target = out / "icon.icns"
            target.parent.mkdir(parents=True, exist_ok=True)
            proc = subprocess.run(
                [iconutil, "-c", "icns", str(iconset), "-o", str(target)],
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0 or not target.is_file():
                raise IconError("iconutil 失败：%s" % (proc.stderr or proc.stdout).strip()[:400])

    # -- Android --------------------------------------------------------------

    def android(self) -> None:
        out = OUT_DIR / "android"
        # 旧版（非自适应）启动图标：保留原生圆角与透明边角。
        legacy = self.light
        write_png(resize(legacy, 192), out / "ic_launcher_192.png")
        # Play 商店要求满幅不透明 512。
        write_png(resize(self.bleed_light, 512), out / "play_store_512.png")

        # 自适应图标：108dp 画布，1024 画布映射到中间 72dp 安全区（其余由蒙版裁切）。
        box_size = ANDROID_ADAPTIVE_PX * ANDROID_SAFE_RATIO
        box_origin = ANDROID_ADAPTIVE_PX * (1.0 - ANDROID_SAFE_RATIO) / 2.0
        foreground = compose_layer(self.geometry, ANDROID_ADAPTIVE_PX, box_origin, box_size)
        write_png(foreground, out / "ic_launcher_foreground_432.png")
        write_png(
            Image.new("RGBA", (ANDROID_ADAPTIVE_PX, ANDROID_ADAPTIVE_PX), self.bg_light + (255,)),
            out / "ic_launcher_background_432.png",
        )
        write_png(self._monochrome(ANDROID_ADAPTIVE_PX, box_origin, box_size), out / "ic_launcher_monochrome_432.png")

        # 各密度 mipmap，供 Gradle 原生工程直接替换。
        for density, px in ANDROID_MIPMAPS:
            write_png(resize(legacy, px), out / ("mipmap-%s" % density) / "ic_launcher.png")
            write_png(
                resize(foreground, round(px * ANDROID_ADAPTIVE_PX / 192.0)),
                out / ("mipmap-%s" % density) / "ic_launcher_foreground.png",
            )

    def _monochrome(self, canvas: int, box_origin: float, box_size: float) -> Image.Image:
        """Android 13+ 主题图标：单色剪影，深色五官留作镂空以保留辨识度。"""
        import numpy as np

        layer = compose_layer(self.geometry, canvas, box_origin, box_size)
        data = np.asarray(layer).astype("int16")
        rgb = data[..., :3]
        alpha = data[..., 3]
        luminance = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
        solid = (alpha > 128) & (luminance > 60)
        out = np.zeros((canvas, canvas, 4), dtype="uint8")
        out[..., 0:3] = 255
        out[..., 3] = np.where(solid, 255, 0).astype("uint8")
        return Image.fromarray(out)

    # -- Windows --------------------------------------------------------------

    def windows(self) -> None:
        out = OUT_DIR / "windows"
        write_ico(self.light, out / "icon.ico", WINDOWS_ICO_SIZES)
        write_ico(self.light, out / "console_wrapper.ico", (16, 24, 32, 48))
        write_png(resize(self.light, 256), out / "icon-256.png")

    # -- Web ------------------------------------------------------------------

    def web(self) -> None:
        """Web 的图标全部用满幅不透明版本。

        apple-touch-icon 与 PWA 图标由 iOS / Chrome 自己套圆角，提前切角会被二次裁切；
        favicon 在 16px 下满幅也比圆角更容易辨认。
        """
        out = OUT_DIR / "web"
        write_ico(self.bleed_light, out / "favicon.ico", (16, 32, 48))
        for size in (16, 32, 48):
            write_png(resize(self.bleed_light, size), out / ("favicon-%d.png" % size))
        # 深浅色 favicon：Web 导出后处理会注入 prefers-color-scheme 的 <link>。
        write_png(resize(self.bleed_light, 128), out / "favicon-light.png")
        write_png(resize(self.bleed_dark, 128), out / "favicon-dark.png")
        write_png(resize(self.bleed_light, 180), out / "apple-touch-icon.png")
        for size in (144, 180, 512):
            write_png(resize(self.bleed_light, size), out / ("icon-%d.png" % size))
        # maskable 要求内容落在中间 80% 安全圆内，否则被裁圆时会切到脸。
        maskable = Image.new("RGBA", (512, 512), self.bg_light + (255,))
        inner = resize(self.bleed_light, round(512 * 0.8))
        maskable.alpha_composite(inner, ((512 - inner.width) // 2, (512 - inner.height) // 2))
        write_png(maskable, out / "maskable-512.png")


# --------------------------------------------------------------------------- #
# 入口
# --------------------------------------------------------------------------- #

GENERATORS = ("app_icon", "splash", "apple", "android", "windows", "web")

# 这些子目录只供导出期读取（Godot 用 res:// 直接读原始文件，不经过资源导入），
# 必须带 .gdignore，否则每种外观的 1024 PNG 都会被当资源打进每个平台的 PCK。
# `icons/` 根目录保持可导入：logo.png 是 boot splash，运行时要从 PCK 里加载。
EXPORT_ONLY_DIRS = ("ios", "macos", "android", "windows", "web")


def ensure_gdignore() -> None:
    for name in EXPORT_ONLY_DIRS:
        folder = OUT_DIR / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ".gdignore").touch()


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="从 wpg.icon 生成全平台应用图标")
    parser.add_argument("--list", action="store_true", help="只列出分组，不写文件")
    parser.add_argument("--only", choices=GENERATORS, action="append", help="只生成指定分组（可重复）")
    args = parser.parse_args(argv)

    ictool = find_ictool()
    renderer = ComposerRenderer(ictool, ICON_BUNDLE)
    try:
        builder = IconBuilder(renderer)
        targets: Iterable[str] = tuple(args.only) if args.only else GENERATORS
        print("ictool: %s" % ictool)
        print(
            "背景色：浅色 %s / 深色 %s / 着色 %s"
            % (builder.bg_light, builder.bg_dark, builder.bg_tinted)
        )
        if args.list:
            for name in targets:
                print("  would generate: %s" % name)
            return 0
        for name in targets:
            getattr(builder, name)()
            print("  ✓ %s" % name)
        ensure_gdignore()
    finally:
        renderer.close()
    print("图标已写入 %s，项目图标写入 %s" % (OUT_DIR.relative_to(ROOT), (ROOT / "icon.png").relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except IconError as exc:
        print("错误：%s" % exc, file=sys.stderr)
        sys.exit(1)
