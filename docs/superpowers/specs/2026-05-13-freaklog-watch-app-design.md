# FreakLog Watch App — Design Spec

**Date:** 2026-05-13
**Status:** Approved
**Owner:** isi (pilz)

## Goal

Add a modern watchOS 10+ companion app to FreakLog covering view, log, browse, and harm-reduction info. Watch and iPhone share data through the existing CloudKit container; shared business logic, model, and timeline rendering move into a new local Swift Package consumed by all targets (iOS app, existing Live Activity widget, new watch app, new watch widget).

## Non-Goals

- WatchConnectivity-based sync (CloudKit only — confirmed scope choice).
- iCloud-disabled fallback beyond a "Enable iCloud sync on iPhone" empty state on watch.
- Watch-side creation of custom substances or custom units (read on watch v3, create on iPhone).
- Watch-side webhooks, location, stats charts, tolerance chart visualisation.
- XCUI/snapshot tests for v1.

## Architecture

### Targets after the work

| Target | Type | Status |
|---|---|---|
| `FreakLog` | iOS app | Existing — refactored to import `FreakLogCore` |
| `LiveActivityExtension` | iOS app extension (existing Timeline widget) | Existing — refactored to import `FreakLogCore` |
| `FreakLogTests` | iOS unit tests | Existing — slim down as logic moves out |
| `FreakLogCore` | Local Swift Package (iOS 16, watchOS 10) | **New** |
| `FreakLog Watch App` | watchOS 10 SwiftUI app | **New** |
| `FreakLog Watch Widgets` | watchOS WidgetKit extension (complications + Smart Stack) | **New** |

### `FreakLogCore` package layout

```
FreakLogCore/
├── Package.swift                    platforms: .iOS(.v16), .watchOS(.v10)
├── Sources/FreakLogCore/
│   ├── Model/                       Main.xcdatamodeld + generated NSManagedObject helpers
│   ├── Persistence/                 PersistenceController (configurable: CloudKit on/off, read-only)
│   ├── Decoding/                    Substance, Roa, Interactions, SubstanceRepo, Tolerance
│   ├── Timeline/                    TimelineModel, *Drawable, EffectTimeline (cross-platform SwiftUI)
│   ├── Logic/                       ExperienceLogic, InteractionChecker, ToleranceChartCalculator,
│   │                                SubstanceColor
│   ├── Helpers/                     Date/String extensions, SharedConstants, GlobalFunctions
│   └── Resources/
│       ├── substances.json
│       └── Localizable.strings (moved from app)
└── Tests/FreakLogCoreTests/
```

Stays in iOS app target only: `Authenticator`, `LocationManager`, `AlertToast`/`ToastViewModel`,
`Webhooks/*`, `Add Ingestion/*`, `Settings/*`, `Search/*`, `Stats/*`, `Safer/*`, `Journal/*`,
`Main/Content/*`, `App Intents/*`, `AppDelegate`, `FreakLog.swift`.

### Watch app structure

```
FreakLog Watch App/
├── FreakLogWatchApp.swift           @main
├── Root/
│   ├── RootTabView.swift            TabView: Active | Journal | Substances | Settings
│   └── WatchAuthenticator.swift     LAContext passcode + wrist-detect
├── Active/
│   ├── ActiveExperienceView.swift   header + EffectTimeline + ingestion list + redose button
│   ├── EmptyActiveView.swift
│   └── ActiveExperienceViewModel.swift
├── Journal/
│   ├── JournalListView.swift        paginated 30-at-a-time
│   ├── ExperienceDetailView.swift
│   └── IngestionDetailView.swift
├── AddIngestion/
│   ├── AddIngestionFlow.swift       NavigationStack
│   ├── SubstancePickerView.swift
│   ├── RoutePickerView.swift
│   ├── DoseDialView.swift           digital-crown rotary
│   ├── TimePickerView.swift
│   └── RedoseSheet.swift
├── Substances/
│   ├── SubstanceListView.swift
│   ├── SubstanceInfoView.swift
│   └── InteractionsView.swift
├── TimedNote/
│   └── AddTimedNoteView.swift
└── Settings/
    └── WatchSettingsView.swift
```

### Watch widget bundle

```
FreakLog Watch Widgets/
├── FreakLogWatchWidgetsBundle.swift
├── ActiveExperienceWidget.swift     SmartStack rectangular + Lock Screen
├── Complications/
│   ├── PhaseComplication.swift      circular/corner/inline → "Peak · 1h12m"
│   └── MiniTimelineComplication.swift  rectangular → tiny EffectTimeline
└── Provider/
    └── ActiveExperienceProvider.swift  TimelineProvider, refresh every 5 min
```

## Data Flow & Sync

1. Watch boot: `PersistenceController` (in `FreakLogCore`) initialised with
   `cloudKitEnabled: true`, container `iCloud.woof.freaklog` (or `-debug`).
2. Reads: `@FetchRequest` against `viewContext`. `ActiveExperienceViewModel` observes
   `NSManagedObjectContextDidSave` + `NSPersistentStoreRemoteChange`.
3. Writes: identical Core Data create/edit on watch as iOS; `viewContext.save()` triggers
   CloudKit push; iPhone receives via remote-change notification.
4. Conflict policy: `NSMergeByPropertyObjectTrumpMergePolicy` (already configured in iOS).
5. Watch widgets: same Core Data stack but read-only
   (`NSReadOnlyPersistentStoreOption`, mirroring existing iOS `#if APP_WIDGET` guard);
   refreshed via `WidgetCenter.shared.reloadAllTimelines()` on every save in the watch app.
6. iCloud disabled fallback: watch shows "Enable iCloud sync on iPhone" empty state.

## Auth / Privacy

- Watch app reuses same biometric-gate concept as iOS but via a new
  `WatchAuthenticator` wrapping `LAContext` directly (passcode-only on watchOS;
  wrist-on counts as continuity unlock).
- Setting `isAuthenticationRequired` mirrored from iOS via shared `UserDefaults`
  through CloudKit-replicated NSUbiquitousKeyValueStore (already implied by the
  shared experience).

## Testing Strategy

- `FreakLogCoreTests` (new) — host-platform unit tests for `TimelineModel`,
  `InteractionChecker`, `ToleranceChartCalculator`, `Experience.isCurrent`,
  `Ingestion.pureSubstanceDose`, in-memory persistence CRUD.
- `FreakLog Watch AppTests` (new watchOS unit test bundle) — `ActiveExperienceViewModel`
  state, `WatchAuthenticator` gating, redose-flow dose increments, complication
  entry generation.
- TDD discipline: every behavior task in the plan is failing-test → minimal-impl
  → passing-test → commit.
- Migration safety for Phase 1: capture iOS unit-test baseline before code move,
  re-run after each extraction step.

## Phase Plan (executed sequentially as one mega-plan)

| Phase | Outcome | Independently shippable |
|---|---|---|
| 1. Extract `FreakLogCore` | iOS app + Live Activity widget consume the package; behaviour identical | Yes |
| 2. Watch v1 — read-only + complications/Smart Stack | Watch shows Active Experience, journal browse, detail screens, all 4 complication families, Smart Stack widget | Yes |
| 3. Watch v2 — write | Add ingestion, redose-from-active, timed notes, start new experience | Yes |
| 4. Watch v3 — safer-use & polish | Substance info/interactions browser, custom-units (read), watch settings | Yes |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Core Data model file move breaks CloudKit schema | Keep `Main.xcdatamodeld` filename and entity hashes identical; load via `Bundle.module`; verify `initializeCloudKitSchema` still no-ops |
| `EffectTimeline` SwiftUI APIs not all available on watchOS | Audit (290 lines) for iOS-only APIs (`UIBezierPath`, hover gestures); wrap with `#if os(iOS)` or substitute |
| `SubstanceRepo.shared` loads ~1 MB JSON at cold launch | Acceptable; same as iOS today |
| CloudKit container provisioning for new bundle IDs | Plan documents the manual Apple Dev portal step (`woof.freaklog.watchkitapp` + watch widget bundle IDs added to `iCloud.woof.freaklog` container) |
| `Authenticator` depends on UIKit | New `WatchAuthenticator` wraps `LAContext` directly; iOS `Authenticator` untouched |
| Plan length | Phase-end checkpoint commits so work can pause between phases |

## Open Questions

None — scoping settled in brainstorm.
