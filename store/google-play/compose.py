"""Builds the Google Play graphics from the raw app captures.

    python store/google-play/compose.py      (needs Pillow and Google Chrome)

Inputs: raw/*.png from integration_test/store_screenshots_test.dart, the app's
fonts and brand icon. Outputs, in this folder: screenshots/*.png (1080x1920),
feature-graphic.png (1024x500), all opaque RGB as Google requires. Also checks
listing.md's name and short description against Google's limits.
"""
import base64
import pathlib
import re
import subprocess
import tempfile

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parents[1] / 'pingduck_app'
FONTS = APP / 'assets' / 'fonts'
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
STATUS_CROP = 140  # blank status-bar strip at the top of each raw capture (px)

SHOTS = [
    ('01_overview', 'LATENCY MAP', 'Who&rsquo;s on your Wi&#8209;Fi?', 'Find every device on your network in seconds.'),
    ('02_devices', 'DEVICE LIST', 'Every device, named', 'Makers, services and latency at a glance.'),
    ('03_inspect', 'NODE INSPECT', 'Inspect any device', 'When it was seen, what it runs and how fast it answers.'),
    ('04_diagnostics', 'DIAGNOSTICS', 'Ping and port scan', 'Jitter, loss and open ports, with hints for risky ones.'),
    ('05_networks', 'MY NETWORKS', 'Remembers every network', 'Home, office or cabin, each with its own devices.'),
    ('06_account', 'PRIVATE BY DESIGN', 'No sign-up needed', 'Your device list stays on your phone. No ads, no tracking.'),
]


def data_uri(path: pathlib.Path) -> str:
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def font_faces() -> str:
    faces = []
    for family, prefix in (('Space Grotesk', 'SpaceGrotesk'), ('Inter', 'Inter')):
        for weight in (400, 500, 600, 700):
            url = (FONTS / f'{prefix}-{weight}.ttf').as_uri()
            faces.append(f"@font-face{{font-family:'{family}';font-weight:{weight};src:url('{url}')}}")
    return '\n'.join(faces)


BASE_CSS = font_faces() + '''
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #f8f9fa; color: #111827; overflow: hidden;
  background-image: linear-gradient(#e2e5e8 1px, transparent 1px), linear-gradient(90deg, #e2e5e8 1px, transparent 1px);
  background-size: 54px 54px; }
.chip { display: inline-block; border: 2px solid #a7f3d0; background: #ecfdf5; color: #059669;
  font: 600 26px/1 'Space Grotesk'; letter-spacing: 3px; padding: 10px 16px; }
h1 { font: 700 84px/1.02 'Space Grotesk'; letter-spacing: -2px; }
p.sub { font: 400 34px/1.35 Inter; color: #475569; }
'''

STATUS_BAR = '''<div class="status"><span>9:41</span><svg width="74" height="26" viewBox="0 0 74 26">
<path d="M2 10a20 20 0 0 1 28 0l-3 3a16 16 0 0 0-22 0zM8 16a11 11 0 0 1 16 0l-3 3a7 7 0 0 0-10 0zM16 23l3-3a4 4 0 0 0-6 0z" fill="#111827"/>
<rect x="38" y="5" width="32" height="16" rx="4" fill="none" stroke="#111827" stroke-width="2.5"/><rect x="41" y="8" width="26" height="10" rx="2" fill="#111827"/></svg></div>'''


def screenshot_html(raw: pathlib.Path, eyebrow: str, title: str, sub: str, index: int) -> str:
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>{BASE_CSS}
.copy {{ position: absolute; left: 90px; right: 90px; top: 96px; }}
.copy h1 {{ margin-top: 30px; }} .copy p.sub {{ margin-top: 22px; }}
.phone {{ position: absolute; left: 150px; top: 440px; width: 780px; height: 1700px; background: #ffffff;
  border: 16px solid #111827; border-radius: 76px; overflow: hidden; box-shadow: 18px 18px 0 0 #059669; }}
.status {{ height: 64px; display: flex; align-items: center; justify-content: space-between; padding: 6px 46px 0;
  font: 600 28px Inter; }}
.screen {{ width: 100%; display: block; }}
</style></head><body>
<div class="copy"><span class="chip">{index:02d} &middot; {eyebrow}</span><h1>{title}</h1><p class="sub">{sub}</p></div>
<div class="phone">{STATUS_BAR}<img class="screen" src="{data_uri(raw)}"></div>
</body></html>'''


def feature_html(icon: pathlib.Path, radar: pathlib.Path) -> str:
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>{BASE_CSS}
body {{ background-size: 40px 40px; }}
.left {{ position: absolute; left: 56px; top: 64px; width: 520px; }}
.brand {{ display: flex; align-items: center; gap: 16px; }}
.brand img {{ width: 64px; height: 64px; border-radius: 32px; }}
.word {{ font: 700 34px/1 'Space Grotesk'; letter-spacing: 1px; color: #059669; }}
.word small {{ display: block; font: 600 13px/1 'Space Grotesk'; letter-spacing: 5px; color: #475569; margin-top: 7px; }}
h1 {{ font-size: 62px; margin-top: 40px; }}
p.sub {{ font-size: 23px; margin-top: 18px; }}
.radar {{ position: absolute; right: 56px; top: 50px; width: 400px; height: 400px; background: #fff;
  border: 3px solid #111827; box-shadow: 10px 10px 0 0 #059669; overflow: hidden; }}
.radar img {{ width: 100%; height: 100%; object-fit: cover; }}
</style></head><body>
<div class="left">
  <div class="brand"><img src="{data_uri(icon)}"><div class="word">PINGDUCK<small>LAN RECON</small></div></div>
  <h1>Who&rsquo;s on your Wi&#8209;Fi?</h1>
  <p class="sub">Every device on your network, with its maker, latency and open ports.</p>
</div>
<div class="radar"><img src="{data_uri(radar)}"></div>
</body></html>'''


def render(html: str, out: pathlib.Path, width: int, height: int) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / 'page.html'
        page.write_text(html, encoding='utf-8')
        png = pathlib.Path(tmp) / 'out.png'
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
                        '--force-device-scale-factor=1', f'--window-size={width},{height}',
                        f'--screenshot={png}', page.as_uri()], check=True, capture_output=True)
        image = Image.open(png).convert('RGB')
        assert image.size == (width, height), image.size
        image.save(out, optimize=True)


def check_listing() -> None:
    text = (HERE / 'listing.md').read_text(encoding='utf-8')
    for label, heading, limit in (('name', 'App name', 30), ('short description', 'Short description', 80),
                                  ('full description', 'Full description', 4000)):
        block = re.search(rf'## {heading}.*?```\n(.*?)\n```', text, re.S).group(1)
        print(f'{label}: {len(block)}/{limit}')
        assert len(block) <= limit, f'{label} is over the limit'


def main() -> None:
    check_listing()
    out_dir = HERE / 'screenshots'
    out_dir.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, eyebrow, title, sub) in enumerate(SHOTS, 1):
            raw = Image.open(HERE / 'raw' / f'{name}.png').convert('RGB')
            cropped = pathlib.Path(tmp) / f'{name}.png'
            raw.crop((0, STATUS_CROP, raw.width, raw.height)).save(cropped)
            render(screenshot_html(cropped, eyebrow, title, sub, i), out_dir / f'{name}.png', 1080, 1920)
            print('wrote', out_dir / f'{name}.png')

        # The latency map panel from the overview capture.
        overview = Image.open(HERE / 'raw' / '01_overview.png').convert('RGB')
        radar = pathlib.Path(tmp) / 'radar.png'
        overview.crop((88, 1455, 1192, 2559)).save(radar)
        render(feature_html(APP / 'assets' / 'branding' / 'icon.png', radar), HERE / 'feature-graphic.png', 1024, 500)
        print('wrote', HERE / 'feature-graphic.png')


if __name__ == '__main__':
    main()
