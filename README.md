# ChromAtlas

Offline-first travel and color explorer for iOS/iPadOS 18+ (SwiftUI + SceneKit). Everything runs on device, with no network code and no third-party dependencies.

## Build

```bash
xcodegen generate
open ChromAtlas.xcodeproj
```

Run the tests with `xcodebuild -scheme ChromAtlas -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`.

In the Simulator, tap **Explore the Demo Atlas**. It loads a deterministic synthetic library of about 6,900 photos, 14 trips and 24 countries. Real photos go through the same geo/solar/trip pipeline.

## Layout

| Area | Files |
| --- | --- |
| Color | `Core/Color`: OKLab, k-means (k=3) on 32×32 samples, named hue zones |
| Geo | `Core/Geo`: SQLite R*Tree reverse geocoder, haversine and great circles, country/region tables |
| Solar | `Core/Solar`: NOAA solar elevation → Daylight / Golden / Blue / Night; hemisphere-aware seasons |
| Trips | `Core/Trips`: home-base detection, trip runs, spatio-temporal DBSCAN stops, layover suppression, flight/ground legs, badges |
| Query | `Core/Filter`: columnar in-memory index (100k assets ≈ 3.5 ms in Release on the simulator) |
| Indexing | `Core/Indexing`: PhotoKit batches, `.fastFormat` 64 px, `isNetworkAccessAllowed = false`, thermal throttling, `BGProcessingTask`, change observer |
| Store | `Core/Store`: `asset_index` schema from the PRD |
| UI | `UI/`: globe + HUDs, timeline + chapter chips, wheel + luminance + harmony, pills, flanking grids, share card, map mode |

## Known gaps vs. PRD

- **Geo data.** The bundled seed has about 420 cities, and the country comes from the nearest city (within 350 km), not from polygons. To use GeoNames `cities15000`, run `Scripts/build_geodb.py`. Natural Earth admin polygons are not wired in yet.
- **Globe landmasses** are hand-simplified outlines (`WorldOutlines.swift`).
- The **< 45 s for 25k photos** indexing target is unmeasured; it needs a real device and library.
