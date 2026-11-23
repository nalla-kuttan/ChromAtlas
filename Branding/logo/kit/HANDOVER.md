# ChromAtlas logo — handover

## What's here
| Folder | Contents |
|---|---|
| `master/` | Source SVGs. Symbol: colour, black, white (thinned), small-size cut. Wordmark: ink, white. Lockups: horizontal and stacked, each on-dark, on-light, black, white |
| `png/` | Transparent PNGs of the symbol (1024) and lockups/wordmarks (2400 wide) |
| `variants/` | One-colour symbols (black, white, Blue Hour) and a square avatar master |
| `web/` | `favicon.ico`, `favicon.svg`, 16/32/48 PNGs, apple-touch-icon, 192/512/maskable icons, `site.webmanifest`, `head-snippet.html`. All built from the small-size cut |
| `app-icon/` | iOS 1024 icons: light (opaque, no alpha), dark (transparent), tinted (greyscale), plus their SVGs |
| `../presentation/` | `board.html` and `slides/*.png`: brief, the mark, mockups (home screen, social, web, tab, sticker, tee) |
| `../build/make_logo.py` | Rebuilds every master from parameters (band widths, tilt, palette, kerning) |

## Changes to the app project
- `ChromAtlas/Resources/Assets.xcassets/AppIcon.appiconset/` previously had an empty 1024 slot. It now holds
  AppIcon.png, AppIcon-dark.png and AppIcon-tinted.png. `actool` compiles it with no warnings.
- `ChromAtlas/Resources/Assets.xcassets/LogoLockup.imageset/` (new): the on-dark horizontal lockup as a vector asset.
- `ChromAtlas/UI/Share/ShareCardView.swift`: the share card header uses `Image("LogoLockup")` at 44 pt high.

## Test results
- `svg_audit.py`: every master scores 98–100. No live text, rasters, filters or near-miss angles.
- Size ladder 16–256 px, pixel test at 16/32/48 on light and dark, one-colour, reversed, photo and pattern
  backgrounds, squint test: the band stays visible down to 16 px, especially with the small-size cut.
- Greyscale: amber and blue separate clearly by value.

## Open items and honest risks
- **Trademark:** I didn't find a match in the reference library, but that is not clearance. Run a professional
  search (USPTO/EUIPO/WIPO plus a reverse image search) before launch.
- **Familiarity:** a two-colour circle split by a white curve sits in the same broad family as some beverage and
  sports-ball marks. The near-vertical crescent, the tilt and the amber/blue pairing keep it distinct. Check it again
  side by side on the App Store shelf.
- **Print colour:** Blue Hour is outside the CMYK gamut. Get a printer's proof and a Pantone match before print.
- **Share card:** wired in. `ShareCard` now shows the `LogoLockup` asset (a tightly cropped vector copy of
  `lockup-horizontal-on-dark.svg`, preserved as a vector) in place of the live "CHROMATLAS" text. Verified in the
  iPhone 17 Pro simulator.
