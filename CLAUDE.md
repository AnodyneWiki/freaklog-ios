# FreakLog iOS

Psychoactive substance ingestion journal. Users log ingestions, track effects over time, see tolerance charts, and optionally fire webhooks (e.g. Discord) on each log.

## Tech stack

- **Swift / SwiftUI** — fully declarative UI, no UIKit views except for UIImpactFeedbackGenerator
- **CoreData + CloudKit** — `NSPersistentCloudKitContainer`; iCloud sync is opt-in (toggled at runtime via `isICloudSyncEnabledKey`)
- **AlertToast** — toast notifications
- **WrappingHStack** — used in suggestion chips
- **SwiftFormat** (airbnb config, `airbnb.swiftformat`) — auto-formatted; 2-space indent, max 130 chars

## Targets

| Target | Purpose |
|--------|---------|
| `FreakLog` | Main app |
| `TimelineWidget` | Live Activity widget (iOS 16.2+) |
| `FreakLogTests` | Unit tests (decoding, interaction logic) |

## Directory layout

```
FreakLog/
  FreakLog.swift          # @main App entry point; wires environment objects
  AppDelegate.swift       # CloudKit notifications, background task management
  Persistence.swift       # CoreData stack, ALL UserDefaults key constants
  Constants.swift         # App-wide constants (appName, URLs, legal substances list)
  Global Functions.swift  # Loose helpers: haptic, getColor, date utils, number parse
  CoreDataHelpers/        # Extensions on CoreData NSManagedObject subclasses
  Decoding/               # PsychonautWiki JSON models (Substance, Roa, etc.)
  Enums/                  # Value types shared across features
  Extensions/             # Swift stdlib extensions
  Add Ingestion/          # Full add-ingestion flow (choose substance → route → dose → finish)
  Journal/                # Journal tab: experience list, all-ingestions list, calendar
  Search/                 # Substance search + detail screens
  Settings/               # Export/import, webhooks, custom units, custom substances
  Stats/                  # Charts: substance usage, tolerance, experience frequency
  Safer/                  # Safer-use info, spray calculator
  Timeline/               # Canvas-drawn effect timeline (used in experience screens)
  Webhooks/               # WebhookManager, WebhookService (HTTP)
  Main/                   # Navigation, auth, live activity, toast
```

## CoreData entities

| Entity | Purpose |
|--------|---------|
| `Experience` | Groups ingestions into a session |
| `Ingestion` | Single substance administration |
| `SubstanceCompanion` | Persists chosen color per substance name |
| `CustomUnit` | User-defined unit (e.g. "1 spoon = 80mg ketamine") |
| `CustomSubstance` | User-defined substance not in PsychonautWiki |
| `ExperienceLocation` | Named lat/lon attached to an ingestion |
| `WebhookPreset` | Saved webhook endpoint + template |
| `WebhookMessage` | Record of a sent webhook (for editing/deleting) |
| `ShulginRating` | +/++ rating on an experience |
| `TimedNote` | Note with timestamp within an experience |
| `Spray` | Nasal spray calculator state |

CoreData helper extensions live in `CoreDataHelpers/`. Each entity has a corresponding `EntityName-CoreDataHelpers.swift` file with computed properties and convenience methods. `Unwrapped` suffix on a property means it falls back to a safe default instead of returning an optional.

## Key patterns

### Environment objects (injected at root in FreakLog.swift)
- `ToastViewModel` — call `toastViewModel.showSuccessToast()` / `showErrorToast(message:)` from any screen
- `LocationManager` — CLLocationManager wrapper; also manages search and `selectedLocation` state
- `Authenticator` — biometric lock state
- `managedObjectContext` — SwiftUI environment key for CoreData

### Navigation
`GlobalNavigationDestination` enum is the single type used as `NavigationLink` values throughout the app. Add a new case there when adding a new destination. Each tab's stack is built by `ContentScreen.view(for:)`; `Navigator.pathKeyPath(for:)` maps a `Tab` to its path.

### Logic separation
Pure logic that doesn't need a SwiftUI context lives in `ExperienceLogic.swift` (static methods). Use these instead of duplicating logic on the entity extension:
- `ExperienceLogic.chartData(for:)` → tolerance chart data
- `ExperienceLogic.interactions(from:)` → drug interaction pairs
- `ExperienceLogic.substancesUsed(from:)` → distinct substances
- `ExperienceLogic.timelineModel(from:...)` → timeline render model
- `ExperienceLogic.myIngestions(from:)` → filter to user's own ingestions
- `ExperienceLogic.dynamicTimelineModel(from:range:...)` → timeline for the configured dynamic range (`DynamicRangeOption`)

### "My" vs "other" ingestions
`consumerName == nil`, empty or whitespace-only = the user themselves. Anything else = someone else. Use `Ingestion.isMine` (or `ExperienceLogic.myIngestions/otherIngestions`) rather than checking `consumerName` directly, and store entered names with `Ingestion.storedConsumerName(_:)` (nil for the user).

### Substance color
Each substance name maps to a `SubstanceColor` via the `SubstanceCompanion` entity. To look up a color by substance name, call the global `getColor(for: substanceName)`. Returns `SubstanceColor.fallback` (purple) if no companion exists. Use `ColorPickerScreen(selectedColor:usedColors:)` to pick a color and `SubstanceColor.suggested(avoiding:)` for a new substance's default.

### Fetching
All fetch requests are built by the static factories on `PersistenceController` (`ingestionsRequest()`, `experiencesRequest()`, `customRoasRequest(for:)`, …) or its instance getters. Use them in `@FetchRequest(fetchRequest:)` instead of writing predicates inline. `PersistenceController.shared.getExperiences(near: date)` is the single place that knows the time-range predicate for "nearby experiences".

### Dose and duration data
Always look up dose/duration with `PersistenceController.shared.resolvedRoa(for:route:)` (or `resolvedDose`/`resolvedDuration`). It merges PsychonautWiki data with the user's `CustomRoa` overrides and custom substance data, and is backed by an in-memory cache, so it is cheap to call from views. `CustomRoa` rows are keyed by `substanceName` + route; `CustomRoaCodable` is the value form used for editing and export/import. A duration phase with a single value is a fixed time. The editor starts from `CustomRoaCodable.psychonautWikiValues(for:route:)` and only saves an override when the values differ from it.

### Deleting ingestions
Delete ingestions, experiences and custom units through `IngestionDeletion.delete(ingestions:)` / `delete(experience:)` / `delete(customUnit:)`. It deletes locally right away, then removes sent webhook messages and notifies leaderboard servers in the background; it also ends the live activity of a deleted current experience. For bulk deletes elsewhere, collect `remoteCleanUp(for:)` before deleting and call it afterwards.

### Adding and editing ingestions
The add (`FinishIngestionScreen`) and edit (`EditIngestionScreen`) forms share `ExperiencePickerRow`, `ConsumerRow`, `LocationButton` and `EstimateFields` (the estimate toggle with ± deviation field). Create experiences with `Experience.create(at:title:in:)` and set locations with `Ingestion.setLocation(_:)`; `ExperienceLocation.make(from:in:)` / `update(from:)` convert anything that is a `LocationValue` (`Location`, `LocationCodable`). Time labels for ingestions, notes and ratings under each `TimeDisplayStyle` come from `EventTimeText`.

### Live activities
Check `LiveActivities.areAvailable` (iOS 16.2+, not on Mac, allowed by the user) rather than repeating the checks.

### Administration site strings
`AdministrationSiteSelection` holds the route-specific site (nostril, vein, muscle, subcutaneous site). `siteString(for:)` converts it into the string stored on `Ingestion.administrationSite` and `init(route:storedSite:)` parses it back. Use `AdministrationSitePicker` for the picker.

### WebhookManager
All webhook HTTP calls go through `WebhookManager.shared`. It handles send, edit, and delete (for ingestion deletion and preset deletion). Message content is built from the saved ingestion by `WebhookDataSnapshot(ingestion:)`, so send and edit always agree. Deletion helpers (`executeDeletions`, `buildPresetDeletionTargets`) are private; call the public `deleteWebhookMessages(for:)`, `deleteMessage(_:)` or `deletePreset(_:deletingMessages:)`.

### Timeline drawing
The timeline is drawn with SwiftUI Canvas in `Timeline/`. `TimelineModel` is the pure-data input. `getSubstanceIngestionGroups()` (`Timeline/Preparation/SubstanceIngestionGroup.swift`, app only) builds the `SubstanceIngestionGroup` payload with resolved durations and dose weights already filled in, so the timeline and the live activity widget never look up substance data themselves. Build live activity state with `Experience.liveActivityState(...)`.

## UserDefaults keys
All keys are static constants on `PersistenceController`. Never hard-code key strings — add them there. Store enum settings as typed `@AppStorage` values (e.g. `SaveableTimeDisplayStyle`) instead of raw strings. One-off data migrations go in the list in `PersistenceController.runPendingMigrations()`.

## Formatting rules
- SwiftFormat enforces style automatically (`airbnb.swiftformat`)
- 2-space indent
- Max 130 characters per line
- No trailing whitespace
- Imports sorted; `@testable` imports at bottom
- `redundantSelf` removed (no `self.` prefix unless required)
- No block comments (`/* */`) — use line comments
- `guard else` on next line; `else` on same line for `if`

## Known issues / intentional workarounds
- `@preconcurrency import CoreData` and `@preconcurrency import CoreLocation` appear on some files — this suppresses Swift concurrency warnings while full Sendable conformance is pending. Do not remove without fixing the underlying concurrency issues.
- `swiftlint:disable` blocks in `Settings-ViewModel.swift` (import function) and a few other files are justified by the genuinely complex/long functions — do not split them artificially just to remove the disable.

## What not to do
- Do not add new global `print()` statements for non-error paths. Errors that reach `catch` blocks may log via `print` but routine flow should not.
- Do not add new `?? ""` unwrapping properties to CoreData helpers unless the empty string case is semantically meaningful. Use the existing `Unwrapped` properties or inline `?? ""`.
- Do not create a new `ChartData`-style struct in entity extensions — use `ExperienceLogic` for shared logic types.
- Do not duplicate the `DeletionTarget` pattern in WebhookManager — use `buildPresetDeletionTargets` / `executeDeletions`.
- Do not add a new fetch-request-then-filter pattern for experiences near a time — use `PersistenceController.shared.getExperiences(near:)`.
- Do not read `substance.getDose/getDuration` directly outside previews — use the resolver so custom overrides apply.
