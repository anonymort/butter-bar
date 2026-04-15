from pathlib import Path
import cairosvg
from PIL import Image

out = Path('/mnt/data/butter_bar_logo')
svg = out/'butter-bar-logo.svg'

svg_text = '''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-label="Butter Bar logo">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#1D1208"/>
      <stop offset="100%" stop-color="#3A2515"/>
    </linearGradient>
    <linearGradient id="butter" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#FFE999"/>
      <stop offset="60%" stop-color="#FFD85A"/>
      <stop offset="100%" stop-color="#F3BE2A"/>
    </linearGradient>
    <linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFF6C9" stop-opacity="0.95"/>
      <stop offset="100%" stop-color="#FFF6C9" stop-opacity="0"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="22" stdDeviation="26" flood-color="#160B03" flood-opacity="0.34"/>
    </filter>
  </defs>

  <!-- Big Sur style icon field -->
  <rect x="74" y="74" width="876" height="876" rx="196" fill="url(#bg)"/>

  <!-- subtle cinema shelf / bar -->
  <rect x="202" y="638" width="620" height="72" rx="36" fill="#6B4528" opacity="0.95"/>
  <rect x="214" y="648" width="596" height="20" rx="10" fill="#8E5E39" opacity="0.65"/>

  <!-- butter pat -->
  <g filter="url(#shadow)">
    <rect x="250" y="290" width="524" height="332" rx="92" fill="url(#butter)"/>
    <path d="M310 334h332c48 0 88 17 112 44 16 18 24 37 24 57v20H250v-39c0-45 20-82 60-108z" fill="url(#shine)" opacity="0.75"/>
  </g>

  <!-- play symbol carved into butter -->
  <path d="M470 386c0-18 20-29 35-18l110 79c13 9 13 28 0 37l-110 79c-15 11-35 0-35-18V386z" fill="#8A5A18" opacity="0.92"/>
  <path d="M483 404c0-9 10-15 17-10l85 61c6 4 6 13 0 17l-85 61c-7 5-17 0-17-10V404z" fill="#A56A20" opacity="0.5"/>

  <!-- tiny perforations hinting at a film strip, but sparse enough for small sizes -->
  <g fill="#C88819" opacity="0.75">
    <rect x="303" y="372" width="18" height="18" rx="5"/>
    <rect x="303" y="522" width="18" height="18" rx="5"/>
    <rect x="703" y="372" width="18" height="18" rx="5"/>
    <rect x="703" y="522" width="18" height="18" rx="5"/>
  </g>

  <!-- wordmark guide not included in icon master -->
</svg>'''
svg.write_text(svg_text)

# master PNG
master_png = out/'butter-bar-logo-1024.png'
cairosvg.svg2png(bytestring=svg_text.encode(), write_to=str(master_png), output_width=1024, output_height=1024)

# app iconset sizes
iconset = out/'ButterBar.iconset'
iconset.mkdir(exist_ok=True)
# name -> px
sizes = {
    'icon_16x16.png': 16,
    'icon_16x16@2x.png': 32,
    'icon_32x32.png': 32,
    'icon_32x32@2x.png': 64,
    'icon_128x128.png': 128,
    'icon_128x128@2x.png': 256,
    'icon_256x256.png': 256,
    'icon_256x256@2x.png': 512,
    'icon_512x512.png': 512,
    'icon_512x512@2x.png': 1024,
}
for name, px in sizes.items():
    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=str(iconset/name), output_width=px, output_height=px)

# convenience exports @1x/@2x/@3x from a 256 base
for scale, px in [(1,256),(2,512),(3,768)]:
    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=str(out/f'butter-bar-logo@{scale}x.png'), output_width=px, output_height=px)

# create ICNS via Pillow
img = Image.open(master_png).convert('RGBA')
img.save(out/'ButterBar.icns', sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])

# README / spec note
(out/'README.txt').write_text(
"Butter Bar logo package\n"
"- butter-bar-logo.svg: master vector source (1024 canvas)\n"
"- butter-bar-logo-1024.png: master raster export\n"
"- butter-bar-logo@1x.png / @2x.png / @3x.png: convenience raster exports\n"
"- ButterBar.iconset/: macOS app icon PNG set\n"
"- ButterBar.icns: macOS icon container\n\n"
"Design notes:\n"
"- Mark is kept well inside the safe area for Big Sur+ squircle masking.\n"
"- Core metaphor: a butter pat resting on a bar/shelf, with a carved play symbol.\n"
"- Contrast and silhouette were kept simple so the icon remains legible at 16 px.\n"
)
