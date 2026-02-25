# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What Faver is
Faver is an iOS app that helps users work through their entire photo library to mark favorites,
in small sessions whenever they have a spare moment — on the bus, before bed, whenever.
The goal is a complete pass of an unfavorited library over time, surfacing what matters
without pressure.

## My role
I am a UX designer, not a developer. Explain technical decisions in plain language when they
affect the experience. When you make architectural choices, briefly say why. Don't assume I
know Swift or Xcode conventions.

## Core principles — never compromise these
- **No deletion. Ever.** Read and favorites-write access only. Never request delete permissions.
- **Speed and frictionlessness above everything.** Every interaction should feel instant.
- **Pick up where you left off.** The app always resumes exactly where the user stopped.
- **No configuration before starting.** The user opens the app and is immediately in it.

## Interaction model
- Full screen, one photo or video at a time
- Swipe left to advance, swipe right to go back — free movement within a cluster
- Favorite button toggles instantly, no confirmation dialog, no auto-advance
- Informal burst detection: photos taken within ~3 seconds grouped as a set
- Within a burst set, swipe vertically; swipe horizontally to move between moments
- Progress indicator shows overall library completion — should feel like momentum, not pressure

## UX rules
- No confirmation dialogs on the favorite toggle
- Nothing that adds friction, cognitive load, or anxiety
- Keep the UI calm, focused, and fast
- When suggesting UI changes, think like a UX designer who values clarity and emotional tone

## QA focus areas
When testing or looking for edge cases, prioritize:
- Burst detection threshold edge cases
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

## Architecture
### Data flow
`PhotoLibraryService` (`@MainActor ObservableObject`) is the single source of truth. It owns
`clusters: [PhotoCluster]`, `totalCount`, and `isLoading`. Every view that reads library state
takes it as `@ObservedObject var photoLibrary: PhotoLibraryService`.

`loadAssets()` is the main entry point — runs off the main thread via `Task.detached`, posts
results back with `await MainActor.run`. Reads `clusterMode` and `clusterGap` from UserDefaults.

After a review session ends, `onDismiss: { photoLibrary.loadAssets() }` triggers a re-cluster
so reviewed photos disappear.

### Clustering (Cluster.swift)
Two modes. Fixed calls `buildClusters(from:reviewedIDs:gapThreshold:)` directly.
Smart (`buildSmartClusters`) does its own grouping pass with two boundary signals:
- **Time gap alone**: 90th-percentile of inter-photo gaps ≥ 60 s (bursts excluded),
  clamped 30 min – 48 h.
- **Location change**: if both consecutive photos have GPS, time gap ≥ 5 min, and
  distance > 1 km → new venue boundary even without a large time gap.
  Photos without GPS fall back to time-only.
- **Fixed**: hard `gapThreshold` from `ClusterGap` (1 h / 3 h / 8 h).

`PhotoCluster` is a pure value type holding assets still needing review (`assetsToReview`)
plus full window size (`totalInWindow`) for the progress bar.

### Map (MapBrowseView.swift)
Dynamic grid clustering keeps annotation count ≤ ~64 at any zoom level. `displayClusters`
divides the world into an 8×8 grid scaled to `currentSpan`. Pins are `MapSuperCluster` —
leaf (1 cluster, shows detail sheet) or aggregate (multiple clusters, zooms in ×4).

### Geocoding cache (GeocodingCache.swift)
`actor GeocodingCache` is a session-scoped singleton. Key = lat/lon rounded to 2 decimal
places (~1 km). Same location only geocoded once per launch.

### Thumbnail loading
Up to 4 thumbnails loaded in parallel using `withTaskGroup`. `isNetworkAccessAllowed = false`
ensures the app never stalls waiting for iCloud.

### Review flow
`ReviewView` uses `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))`. Each page
is an `AssetImageView` with black fill to prevent adjacent photo bleed. `photoLibrary.markReviewed`
called on `onAppear` and `onChange(of: currentIndex)`.

### Visual
Targets iOS 26 — uses `.glassEffect(in: Circle()/Capsule())` on review buttons and map pins
with no version guard. Navigation bars get glass automatically.
```

---

The technical sections are preserved exactly, and the product/UX intent is now at the top where Claude Code will read it first. To replace the file, open it in nano:
```
nano ~/Projects/faver/CLAUDE.md
```

Select all with **Ctrl + K** (hold it down to delete line by line) — or easier, just delete the file and recreate it:
```
rm ~/Projects/faver/CLAUDE.md && nano ~/Projects/faver/CLAUDE.md