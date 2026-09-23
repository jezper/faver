# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What Faver is
Faver is an iOS app that helps users work through their entire photo library to mark favorites,
in small sessions whenever they have a spare moment — on the bus, before bed, whenever.
The goal is a complete pass of an unfavorited library over time, surfacing what matters
without pressure.

## Core principles — never compromise these
- **No deletion. Ever.** Read and favorites-write access only. Never request delete permissions.
- **Speed and frictionlessness above everything.** Every interaction should feel instant.
- **Pick up where you left off.** The app always resumes exactly where the user stopped.
- **No configuration before starting.** The user opens the app and is immediately in it.

## Interaction model
- Full screen, one photo or video at a time
- Swipe left to advance, swipe right to go back — free movement within a cluster
- Favorite button toggles instantly, no confirmation dialog, no auto-advance
- Leaving is free and never confirmed: every photo is recorded as seen when it is
  the one on screen, so the next visit resumes on the photo the user stopped at
- Progress indicator shows overall library completion — should feel like momentum, not pressure

**Not built yet.** Burst sets (photos within ~3 s grouped, swiped vertically) are in
the design but nowhere in the code. Videos are fetched but shown as frozen stills with
no play control and no indication they are videos.

## UX rules
- No confirmation dialogs on the favorite toggle.

Other behaviour/quality/design/a11y rules: inherited from global ~/.claude/CLAUDE.md.

## QA focus areas
When testing or looking for edge cases, prioritize:
- Cluster boundary logic
- Session resume accuracy
- Permission handling on first launch
- iCloud photo handling (never stall waiting for iCloud)

## Project
Faver is an iOS 26 app (Swift/SwiftUI). No external dependencies — plain Xcode project,
no SPM packages, no CocoaPods, no linter.

## Build commands
```bash
# Build for simulator (fastest, no signing needed)
xcodebuild -project Faver/Faver.xcodeproj -scheme Faver \
  -sdk iphonesimulator -configuration Debug build

# Build for device (requires signing)
xcodebuild -project Faver/Faver.xcodeproj -scheme Faver \
  -configuration Debug build
```

There are no unit tests and no lint step.

```bash
# Ship to TestFlight (build number comes from Apple)
./scripts/testflight.sh

# Where the builds are
./scripts/status.sh
```

## Architecture
### Data flow
`LibraryService` (`@MainActor ObservableObject`) is the single source of truth. It owns
`clusters: [PhotoCluster]`, `totalAssets`, `isLoading` and `minSize`. Views take it as
`let library: LibraryService`, except `SettingsView`, which needs `@ObservedObject`.

`load()` is the main entry point. Fetching and clustering both run in one
`Task.detached`, so nothing touches PHAsset properties on the main actor. Reads
`clusterMode`, `smartSensitivity`, `clusterGap` and `minSetSize` from UserDefaults before
crossing the boundary.

After a review session ends, `onDismiss: { library.load() }` re-clusters so reviewed
photos disappear.

`ReviewStore` persists the ids of photos already seen, in UserDefaults.

### Clustering (Cluster.swift)
Two modes. Fixed calls `buildClusters(from:reviewedIDs:gapThreshold:)` with a hard
threshold from `ClusterGap` (1 h / 3 h / 8 h). Smart (`buildSmartClusters`) uses three
tiers:
- **Day gap**: ≥ 24 h always splits.
- **Time gap**: 90th percentile of gaps ≥ 60 s (bursts excluded), clamped 30 min – 18 h.
- **Location change**: both photos geotagged, paused past `SmartSensitivity.minPauseTime`
  (2 / 3 / 8 min) and moved past `locationThreshold` (1.5 / 3 / 5 km) → new venue.

`makeCluster` decides whether a window is worth showing. A window is skipped only if it
was curated before Faver ever saw it — it contains a favorite and none of its photos are
in `reviewedIDs`. Favorites made inside Faver must never hide photos the user has not
reached.

`PhotoCluster` is `@unchecked Sendable` so clustering can run off the main actor.

### Map (MapBrowseView.swift)
`gridCluster` divides the visible region into an 8×8 grid, keeping annotations at ~64 or
fewer. Pins are `MapSuperCluster` — leaf (1 cluster, opens a detail sheet) or aggregate
(several, zooms in ×4). Map style is `.standard`, not satellite.

### Geocoding cache (GeocodingCache.swift)
`actor GeocodingCache` is a session-scoped singleton. Key = lat/lon rounded to 2 decimal
places (~1 km). Same location only geocoded once per launch.

### Image loading
Two passes everywhere: a fast local one to get something on screen, then a sharper one.
Home and browse thumbnails never allow network access at all. The review screen does
allow it for the second pass only, after the local pass has already drawn something,
and cancels in-flight requests when the user swipes on.

### Visual
Targets iOS 26.2. Review controls and map pins use `.glassEffect` with regular glass —
not clear, which Apple suggests over photos but which cannot hold up over an arbitrary
camera roll. Navigation bars are left alone so they get system glass; do not add
`.toolbarBackground`.

Dark mode only, on purpose: a dark surround is the right environment for judging images.