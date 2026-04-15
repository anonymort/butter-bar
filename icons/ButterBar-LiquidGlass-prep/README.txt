Butter Bar — Liquid Glass prep package for macOS 26 / Icon Composer

What this package contains
- ButterBar-LiquidGlass-master.svg
- 01-background.png
- 02-bar.png
- 03-butter.png
- 04-glyph-gloss.png
- ButterBar-LiquidGlass-preview.png
- flattened PNG exports at 16/32/64/128/256/512/1024

Important limitation
This package does NOT include a true .icon file.
Apple's new .icon format is created with Icon Composer and integrates with Xcode.
I can prepare the layered source assets, but generating a production .icon file requires Apple's toolchain.

Suggested Icon Composer mapping
- Background layer: 01-background.png
- Mid / base content layer: 02-bar.png
- Foreground content layer: 03-butter.png
- Foreground detail / gloss layer: 04-glyph-gloss.png

Recommended workflow
1. Open Icon Composer.
2. Create a new icon and import these transparent layers in order.
3. Tune Liquid Glass properties and lighting in Icon Composer.
4. Save the resulting AppIcon.icon.
5. Drag the .icon file into your Xcode project and make sure the target's App Icon name matches the file name.

Design notes
- The mark stays inside a conservative safe area for macOS masking.
- The play glyph remains large enough to survive downscaling.
- The layered split is intended to give Icon Composer surfaces something meaningful to refract/specularly highlight.

