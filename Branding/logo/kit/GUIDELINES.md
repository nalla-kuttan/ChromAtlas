# ChromAtlas — Logo Guidelines

## 1. The logo
**Idea:** a globe crossed by the *terminator*, the moving line between day and night where golden hour and blue hour
happen. The axis is tilted 23.4°, the same as Earth's. The globe stands for places and the band for light, which is
the app's whole promise.

| Version | Use it for | Files |
|---|---|---|
| Horizontal lockup (primary) | Website header, App Store promo art, share cards, docs | `master/lockup-horizontal-*.svg` |
| Stacked lockup | Square or tall spaces: splash, posters, merch | `master/lockup-stacked-*.svg` |
| Symbol | App icon, avatars, favicon, anywhere space is tight | `master/symbol-*.svg` |
| Wordmark | When the symbol already appears nearby | `master/wordmark-*.svg` |

Each lockup comes in four versions: `on-dark` (colour symbol, white type), `on-light` (colour symbol, ink type),
`black`, and `white`. The `white` files use a slightly wider band to offset irradiation (white shapes on dark look
heavier than they are).

## 2. Construction
- Symbol: a circle of Ø208 in a 256 grid. The day piece ends at a half-ellipse (rx 8) through the poles, the night
  piece at a half-ellipse (rx 36). The band between them is the terminator, and the whole mark is rotated 23.4°.
- Wordmark: drawn from geometry, not typed. Cap height 100. Stems are 16, horizontals 14 (thinned optically) and
  curves 17. The A has a flat apex and the M has a flat vertex. Caps are tracked at 0.24 of the cap height, with
  kerning adjusted by eye. Source: `../build/make_logo.py`.
- Lockup: the symbol is 2.08 × the cap height. The gap between symbol and wordmark equals the width of the night
  crescent at the equator. The wordmark is centred optically, a hair above the symbol's centre.

## 3. Clear space
Keep a clear zone of **1 N** on every side, where **N = the width of the night crescent** (≈ ⅓ of the symbol's
diameter). The zone scales with the logo, so never use a fixed distance.

## 4. Minimum size
| Version | Screen | Print |
|---|---|---|
| Horizontal lockup | 140 px wide | 30 mm wide |
| Stacked lockup | 64 px wide | 15 mm wide |
| Symbol | 16 px. Below 32 px use `symbol-small.svg` (wider band, larger globe) | 5 mm |

## 5. Colour
| Name | Role | HEX | RGB | CMYK (approx.) |
|---|---|---|---|---|
| Golden Hour | Day side of the symbol; the app's accent | `#FFB861` | 255 184 97 | 0 28 62 0 |
| Blue Hour | Night side of the symbol | `#3E6BFF` | 62 107 255 | 76 58 0 0 |
| Night Ink | App background, app-icon tile, type on light | `#0C0E12` | 12 14 18 | 33 22 0 93 |

The CMYK values are straight conversions. Blue Hour is outside the CMYK gamut and prints duller, so get a
printer's proof and a Pantone match before any print run. No Pantone references are given yet.

**Approved pairings:**
- Colour symbol + white type on Night Ink. This is the home of the brand.
- Colour symbol + ink type on white or light neutrals.
- All-white on Night Ink, Blue Hour or a dark photo.
- All-black on light paper.

Blue Hour holds 4.4:1 contrast on both Night Ink and white. Golden Hour is only 1.7:1 on white, so on white
backgrounds the symbol depends on its blue half. Don't use the symbol on pale yellow or orange backgrounds.

## 6. Typography alongside the logo
The app UI uses SF Pro Rounded (the system font), which matches the app. Don't set "ChromAtlas" in any font as a
logo: always use the wordmark files.

## 7. App icon
`app-icon/AppIcon*.png` (1024 px, light/dark/tinted) is installed in
`ChromAtlas/Resources/Assets.xcassets/AppIcon.appiconset`. The light icon has a navy glow over Night Ink, like the
globe screen, and the symbol fills 66% of the tile. The dark icon has a transparent background, as iOS 18 expects.
The tinted icon is greyscale.

## 8. Don'ts
- Don't change the tilt, flip the symbol (day is always on the left) or rotate it.
- Don't fill the band. It's always the background showing through.
- Don't recolour outside the palette, swap amber and blue, or add gradients, shadows or outlines to the symbol.
- Don't stretch, squash or rearrange the lockups.
- Don't put the full-colour symbol on busy photos without a Night Ink container.
- Don't retype the wordmark.
