"""Generate placeholder PWA icons for Wired-Part.

Creates SVG placeholder icons in frontend/public/icons/.
For production, replace with real brand PNG icons and update
manifest.json to reference them.

To convert SVG → PNG (requires Inkscape or ImageMagick):
    inkscape icon-512.svg -w 512 -h 512 -o icon-512.png
    inkscape icon-192.svg -w 192 -h 192 -o icon-192.png

Usage: python scripts/generate-icons.py
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICONS_DIR = ROOT / "frontend" / "public" / "icons"

ICON_SVG_TEMPLATE = """\
<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <rect width="{size}" height="{size}" rx="{corner}" fill="#1E293B"/>
  <rect x="{pad}" y="{pad}" width="{inner}" height="{inner}" rx="{inner_corner}" fill="#3B82F6"/>
  <text x="{cx}" y="{ty}" font-family="system-ui, -apple-system, sans-serif" font-size="{fs}" font-weight="700" fill="#FFFFFF" text-anchor="middle">WP</text>
</svg>"""


def main():
    ICONS_DIR.mkdir(parents=True, exist_ok=True)

    for size in [192, 512]:
        pad = size // 8
        inner = size - 2 * pad
        svg = ICON_SVG_TEMPLATE.format(
            size=size,
            corner=size // 8,
            pad=pad,
            inner=inner,
            inner_corner=size // 16,
            cx=size // 2,
            ty=int(size * 0.6),
            fs=int(size * 0.375),
        )
        path = ICONS_DIR / f"icon-{size}.svg"
        path.write_text(svg, encoding="utf-8")
        print(f"Created {path}")

    print("Done! Replace these with real brand icons before release.")


if __name__ == "__main__":
    main()
