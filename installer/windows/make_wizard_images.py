"""Renders the installer's wizard images in PingDuck's brand.

    python installer/windows/make_wizard_images.py        (needs Pillow)

Writes installer/windows/branding/: the left panel of the Welcome and Finish
pages (wizard-*.png, 164x314 at 100%) and the corner logo of the other pages
(wizard-small-*.png, 55x55), each at the DPI scales Inno Setup picks from.
The duck is the one in pingduck_app/tool/make_brand_assets.py (same geometry).
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))

INK = (0x11, 0x18, 0x27, 255)
EMERALD = (0x05, 0x96, 0x69, 255)
AMBER = (0xD9, 0x77, 0x06, 255)
WHITE = (255, 255, 255, 255)
MUTED = (0x94, 0xA3, 0xB8, 255)
GRID = (0x1F, 0x29, 0x37, 255)
FONTS = os.path.join(REPO, 'pingduck_app', 'assets', 'fonts')
OUT = os.path.join(HERE, 'branding')
SCALES = [100, 125, 150, 175, 200, 250]
SS = 4


def quad(p0, p1, p2, steps=48):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        pts.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    return pts


def duck(draw, ox, oy, s):
    """The duck in the s-by-s box at (ox, oy), as make_brand_assets.duck."""
    P = lambda fx, fy: (ox + fx * s, oy + fy * s)
    r = 0.2 * s
    cx, cy = P(0.52, 0.42)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=EMERALD)
    outline = [P(0.34, 0.5)] + quad(P(0.34, 0.5), P(0.22, 0.76), P(0.5, 0.78)) + quad(P(0.5, 0.78), P(0.74, 0.78), P(0.7, 0.56))
    draw.polygon(outline, fill=EMERALD)
    draw.polygon([P(0.68, 0.38), P(0.84, 0.44), P(0.68, 0.5)], fill=AMBER)
    er = 0.035 * s
    ex, ey = P(0.56, 0.38)
    draw.ellipse([ex - er, ey - er, ex + er, ey + er], fill=INK)


def font(name, px):
    return ImageFont.truetype(os.path.join(FONTS, name), int(px))


def panel(scale):
    """Carbon panel: dot grid, the duck disc, wordmark and tagline."""
    w, h = 164 * scale // 100, 314 * scale // 100
    W, H = w * SS, h * SS
    u = W / 164  # one design pixel
    img = Image.new('RGBA', (W, H), INK)
    d = ImageDraw.Draw(img)

    # The scan grid from the app's radar, fading out towards the bottom.
    step = 12 * u
    y = step / 2
    while y < H:
        x = step / 2
        while x < W:
            r = 1.1 * u
            d.ellipse([x - r, y - r, x + r, y + r], fill=GRID)
            x += step
        y += step
    # A few "found" devices lit in emerald.
    for gx, gy in [(1, 3), (9, 2), (11, 6), (2, 9), (12, 21), (3, 23), (10, 24)]:
        x, y = step / 2 + gx * step, step / 2 + gy * step
        r = 2.2 * u
        d.ellipse([x - r, y - r, x + r, y + r], fill=EMERALD)

    # Duck disc with a ping ring.
    disc = 76 * u
    cx, cy = W / 2, 108 * u
    ring = disc / 2 + 10 * u
    d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], outline=EMERALD, width=int(2 * u))
    d.ellipse([cx - disc / 2, cy - disc / 2, cx + disc / 2, cy + disc / 2], fill=WHITE)
    inset = disc * 0.08
    duck(d, cx - disc / 2 + inset, cy - disc / 2 + inset, disc - 2 * inset)

    # Wordmark and tagline (Space Grotesk / Inter, as the app's headings).
    def centered(text, f, y, fill):
        tw = d.textlength(text, font=f)
        d.text(((W - tw) / 2, y), text, font=f, fill=fill)

    centered('PingDuck', font('SpaceGrotesk-700.ttf', 24 * u), 176 * u, WHITE)
    centered('Every device on your', font('Inter-400.ttf', 10 * u), 212 * u, MUTED)
    centered('network, around the clock.', font('Inter-400.ttf', 10 * u), 226 * u, MUTED)
    centered('FOR WINDOWS', font('SpaceGrotesk-600.ttf', 8.5 * u), 286 * u, EMERALD)

    return img.resize((w, h), Image.LANCZOS).convert('RGB')


def small(scale):
    """The DuckLogo disc, as on the app's title bar."""
    s = 55 * scale // 100
    big = Image.new('RGBA', (s * SS, s * SS), (0, 0, 0, 0))
    S = s * SS
    d = ImageDraw.Draw(big)
    d.ellipse([0, 0, S, S], fill=INK)
    duck(d, S * 0.08, S * 0.08, S * 0.84)
    return big.resize((s, s), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
for scale in SCALES:
    for name, img in [(f'wizard-{scale}.png', panel(scale)), (f'wizard-small-{scale}.png', small(scale))]:
        img.save(os.path.join(OUT, name))
        print('wrote', name, img.size)
