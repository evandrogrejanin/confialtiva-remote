#!/usr/bin/env python3
"""Renders the Confialtiva icons and logos from branding/*.svg into the paths the build uses.

Requires: pip install cairosvg pillow
Usage (from the repository root): python3 branding/generate_icons.py
"""
import io
import os

import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRANDING = os.path.join(ROOT, "branding")
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
LOGO_HEIGHT = 120  # the home page shows the logo at up to 300x60, so this is 2x
LOGO_TEXT_COLOR = "#0A1725"


def read(name):
    with open(os.path.join(BRANDING, name), "rb") as f:
        return f.read()


def render(svg, width=None, height=None):
    png = cairosvg.svg2png(bytestring=svg, output_width=width, output_height=height)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def out(path):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    print("writing", path)
    return full


def save_ico(svg, path):
    images = [render(svg, s, s) for s in ICO_SIZES]
    largest = images[-1]
    largest.save(out(path), format="ICO", sizes=[(s, s) for s in ICO_SIZES],
                 append_images=images[:-1])


def main():
    icon_svg = read("icon.svg")
    logo_svg = read("logo.svg")

    for path in ["res/icon.ico", "res/tray-icon.ico",
                 "flutter/windows/runner/resources/app_icon.ico",
                 "flutter/assets/icon.ico"]:
        save_ico(icon_svg, path)

    for path, size in [("res/32x32.png", 32), ("res/64x64.png", 64),
                       ("res/128x128.png", 128), ("res/128x128@2x.png", 256),
                       ("res/icon.png", 256), ("flutter/assets/icon.png", 256)]:
        render(icon_svg, size, size).save(out(path))

    with open(out("flutter/assets/icon.svg"), "wb") as f:
        f.write(icon_svg)

    render(logo_svg, height=LOGO_HEIGHT).save(out("flutter/assets/logo.png"))
    render(logo_svg, height=LOGO_HEIGHT).save(out("flutter/assets/logo_light.png"))
    dark_svg = logo_svg.replace(LOGO_TEXT_COLOR.encode(), b"#FFFFFF")
    render(dark_svg, height=LOGO_HEIGHT).save(out("flutter/assets/logo_dark.png"))


if __name__ == "__main__":
    main()
