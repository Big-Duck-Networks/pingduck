"""Renders the PingDuck duck mark into the launcher-icon and splash sources.

    python tool/make_brand_assets.py        (needs Pillow)

Same geometry as DuckLogo in lib/core/widgets/pd_widgets.dart. Writes to
assets/branding/; then run flutter_launcher_icons and flutter_native_splash.
"""
import os

from PIL import Image, ImageDraw

INK = (0x11, 0x18, 0x27, 255)
EMERALD = (0x05, 0x96, 0x69, 255)
AMBER = (0xD9, 0x77, 0x06, 255)
WHITE = (255, 255, 255, 255)
OUT = 'assets/branding'
SS = 4  # supersampling for smooth edges


def quad(p0, p1, p2, steps=48):
    """Points along a quadratic Bezier."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


def duck(draw, ox, oy, s, body=EMERALD, beak=AMBER, eye=INK):
    """Draws the duck inside the s-by-s box at (ox, oy), as DuckLogo does."""
    P = lambda fx, fy: (ox + fx * s, oy + fy * s)
    r = 0.2 * s
    cx, cy = P(0.52, 0.42)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=body)
    outline = [P(0.34, 0.5)] + quad(P(0.34, 0.5), P(0.22, 0.76), P(0.5, 0.78)) + quad(P(0.5, 0.78), P(0.74, 0.78), P(0.7, 0.56))
    draw.polygon(outline, fill=body)
    draw.polygon([P(0.68, 0.38), P(0.84, 0.44), P(0.68, 0.5)], fill=beak)
    er = 0.035 * s
    ex, ey = P(0.56, 0.38)
    draw.ellipse([ex - er, ey - er, ex + er, ey + er], fill=eye)


def render(size, paint):
    big = Image.new('RGBA', (size * SS, size * SS), (0, 0, 0, 0))
    paint(ImageDraw.Draw(big), size * SS)
    return big.resize((size, size), Image.LANCZOS)


def save(name, img):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))
    print('wrote', os.path.join(OUT, name), img.size)


# iOS and legacy Android: full-bleed carbon square (iOS forbids transparency),
# duck enlarged since the OS applies its own corner mask.
def full_icon(d, S):
    d.rectangle([0, 0, S, S], fill=INK)
    m = S * 0.06
    duck(d, m, m, S - 2 * m)


save('icon.png', render(1024, full_icon).convert('RGB'))


# Android adaptive foreground: transparent. flutter_launcher_icons insets it
# by 16% per side, which puts this near-full-bleed duck inside the safe zone.
def foreground(d, S):
    box = S * 0.92
    duck(d, (S - box) / 2, (S - box) / 2, box)


save('icon_foreground.png', render(1024, foreground))


# Android 13 themed icon: single colour silhouette (the OS tints it).
def monochrome(d, S):
    box = S * 0.92
    duck(d, (S - box) / 2, (S - box) / 2, box, body=WHITE, beak=WHITE, eye=(0, 0, 0, 0))


save('icon_monochrome.png', render(1024, monochrome))


# Splash: the DuckLogo disc. Android 12+ masks it to a circle within 2/3 of
# the 960px image, so the disc fills that circle.
def splash(d, S):
    pad = S / 6
    d.ellipse([pad, pad, S - pad, S - pad], fill=INK)
    inner = S - 2 * pad
    duck(d, pad, pad, inner)


save('splash.png', render(960, splash))


# Windows: the DuckLogo disc on transparency, as multi-size .ico files for the
# exe/taskbar (windows/runner/resources) and the tray (an app asset).
def windows_icon(d, S):
    d.ellipse([0, 0, S, S], fill=INK)
    duck(d, S * 0.08, S * 0.08, S * 0.84)


disc = render(256, windows_icon)
for path, sizes in [
    (os.path.join(OUT, '..', '..', 'windows', 'runner', 'resources', 'app_icon.ico'), [16, 24, 32, 48, 64, 128, 256]),
    (os.path.join(OUT, 'tray.ico'), [16, 20, 24, 32, 48]),
]:
    disc.save(path, sizes=[(s, s) for s in sizes])
    print('wrote', os.path.normpath(path), sizes)
