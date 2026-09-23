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
- Burst sets: photos within ~3 s (or sharing a camera burst id) hold one horizontal
  position and are swiped vertically. Seeing a burst marks all of it.
- Videos show a poster frame, their length and a play control. Never autoplay.
- Favorite button toggles instantly, no confirmation dialog, no auto-advance
- **A moment is whole.** Nothing counts as reviewed until the explicit last step at
  the end marks the whole moment at once. Swiping past a photo spends nothing.
- What is remembered while swiping is the **position**, per moment, so the next visit
  opens on the photo the user stopped at. Leaving is free and never confirmed.
- Finished moments go to an archive in Browse and can be walked back into, or put back
  in the queue. There is no global reset.
- Progress indicator shows overall library completion — should feel like momentum, not pressure
- Screenshots are excluded by default, with a setting to include them

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

`ReviewStore` holds two separate things: `reviewedIDs`, the photos in moments that have
been through the last step, and `positions`, a moment id → asset id map of where the user
stopped. Keeping them apart is what lets a moment stay whole while still resuming
correctly. `unmark(_:)` puts photos back.

`PhotoCluster.isReviewed` means `assetsToReview` is empty. `LibraryService.pending` is
the queue, `archive` is everything finished; `clusters` holds both.

`LibraryService` observes the photo library, but only sets a flag. The reload happens
when the app returns to the foreground, because Faver's own favorite writes are library
changes too and reloading on each would re-cluster everything on every heart tap.

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

`groupIntoUnits` folds each cluster's photos into `ReviewUnit`s — one photo, or a burst.
Computed once when the cluster is built, stored on `PhotoCluster.units`, and used as the
review pager's positions. `assetsToReview` stays flat and is what counts are taken from.

`PhotoCluster` and `ReviewUnit` are `@unchecked Sendable` so clustering can run off the
main actor.

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