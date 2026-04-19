# -*- coding: utf-8 -*-
"""
Generate the default OG / Twitter share card.

Output: static/og-image.png (1200x630, Anthropic-inspired).
Rerun whenever the site title / subtitle / accent color change.

Usage:
    python scripts/gen-og-image.py
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "static" / "og-image.png"

W, H = 1200, 630

# Anthropic-inspired palette
BG = (240, 238, 230)      # cream #F0EEE6
TEXT = (25, 25, 25)       # near-black #191919
MUTED = (110, 100, 90)    # warm grey
ACCENT = (217, 119, 87)   # Anthropic Clay #D97757

# Fonts (Windows built-in Microsoft JhengHei for CJK)
FONT_TC = "C:/Windows/Fonts/msjh.ttc"
FONT_TC_BOLD = "C:/Windows/Fonts/msjhbd.ttc"


def draw_asterisk(draw, cx, cy, size, color):
    """Anthropic-style 6-point asterisk = 3 rotated bars."""
    for angle_deg in (0, 60, 120):
        rad = math.radians(angle_deg)
        bar_w = size * 0.18
        bar_h = size * 2.0
        corners = [
            (-bar_w / 2, -bar_h / 2),
            (bar_w / 2, -bar_h / 2),
            (bar_w / 2, bar_h / 2),
            (-bar_w / 2, bar_h / 2),
        ]
        rotated = []
        for x, y in corners:
            rx = cx + x * math.cos(rad) - y * math.sin(rad)
            ry = cy + x * math.sin(rad) + y * math.cos(rad)
            rotated.append((rx, ry))
        draw.polygon(rotated, fill=color)


def load_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        # Fallback to PIL default (will be Latin-only but prevents hard fail)
        return ImageFont.load_default()


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    title_font = load_font(FONT_TC_BOLD, 108)
    subtitle_font = load_font(FONT_TC, 40)
    small_font = load_font(FONT_TC, 26)

    # Accent asterisk: top-left, scaled
    draw_asterisk(draw, 140, 140, 52, ACCENT)

    # Thin accent underline under asterisk area (horizontal rule)
    draw.rectangle([140 - 60, 220, 140 + 60, 224], fill=ACCENT)

    # Main title — centered vertically a bit above mid
    title = "AI 輔助維運工程"
    tb = draw.textbbox((0, 0), title, font=title_font)
    tw = tb[2] - tb[0]
    th = tb[3] - tb[1]
    draw.text(((W - tw) / 2, H / 2 - th - 30), title, fill=TEXT, font=title_font)

    # Subtitle
    subtitle = "為 infra 工程師而寫的 Claude Code 系列"
    sb = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    sw = sb[2] - sb[0]
    draw.text(((W - sw) / 2, H / 2 + 40), subtitle, fill=MUTED, font=subtitle_font)

    # Bottom-right: author + URL
    author = "Scott Teng · eeit.github.io/ai-devops-blog"
    ab = draw.textbbox((0, 0), author, font=small_font)
    aw = ab[2] - ab[0]
    draw.text((W - aw - 60, H - 58), author, fill=MUTED, font=small_font)

    img.save(OUT, "PNG", optimize=True)
    print(f"OK: {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
