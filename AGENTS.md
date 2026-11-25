# FreakLog iOS

Psychoactive substance ingestion journal. Users log ingestions, track effects over time, see tolerance charts, and optionally fire webhooks (e.g. Discord) on each log.

## Version tags

Whenever you bump the app’s `MARKETING_VERSION`, create a signed, annotated Git tag named `vX.Y.Z` on the version bump commit. Use `FreakLog X.Y.Z` as the tag message.

## Tech stack

- **Swift / SwiftUI** — SwiftUI screens with UIKit bridges for system components such as PDFKit and package scanning
- **CoreData + CloudKit** — `NSPersistentCloudKitContainer`; iCloud sync is opt-in (toggled at runtime via `isICloudSyncEnabledKey`)
- **AlertToast** — toast notifications
- **WrappingHStack** — used in suggestion chips
- **SwiftFormat** — project configuration in `airbnb.swiftformat`

## Targets

| Target | Purpose |
|--------|---------|
| `FreakLog` | Main app |
| `TimelineWidget` | Live Activity, journal shortcuts, and the next-routine widget |
| `FreakLogTests` | Unit tests (decoding, interaction logic, export/import round trip) |
| `FreakLogWatch` | Watch app for quick logging (watchOS 10+), embedded in the main app |

## Directory layout

```
FreakLog/
  FreakLog.swift          # @main App entry point; wires environment objects
  AppDelegate.swift       # CloudKit notifications, background task management
  Persistence.swift       # CoreData stack, journal transactions, shared UserDefaults keys
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
  Stats/                  # Period filters, journal-day grouping, charts, pinned views, and goals
  Routines/               # Schedule recurrence, reminders, and linked occurrences
  Inventory/              # Saved products, stock changes, package lookup, and lab report attachments
  Safer/                  # Safer-use info, spray calculator
  Timeline/               # Canvas-drawn effect timeline (used in experience screens)
  Webhooks/               # WebhookManager, WebhookService (HTTP)
  Main/                   # Navigation, auth, live activity, toast
  Watch/                  # iPhone side of the watch app (WatchConnectivity)
  Assistant/              # LLM assistant: provider clients, tool loop, journal tools, chat and its settings
FreakLogWatch/            # Watch app (synchronized folder)
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
| `WebhookMessage` | Record of a sent webhook (for editing/deleting), about an ingestion or a timed note (v12) |
| `ShulginRating` | +/++ rating on an experience |
| `TimedNote` | Note with timestamp within an experience |
| `Spray` | Nasal spray calculator state |
| `CustomRoa` | Dose/duration per route: a custom substance's data or a PsychonautWiki override |
| `SubstanceOverride` | A substance's display name and categories, keyed by its stored name (model v9) |
| `Formulation` | Named preset of several substances logged together, e.g. a pill with two actives (model v10); its ingestions link to it with the amount taken (v11) |
| `FormulationComponent` | One substance of a formulation: route, dose per unit of the formulation, `position` for order |
| `RoutineRecord` | Schedule data and optional link to a custom unit or formulation |
| `RoutineOccurrence` | A stable scheduled or as-needed occurrence, linked to its logged entries |
| `StockContainer` | Stock for a saved product, stored in the container’s counting unit |
| `StockChange` | An opening count, adjustment, transfer, or usage linked to journal entries |

Most CoreData helper extensions live in `CoreDataHelpers/`. Routine and inventory helpers also live in their feature folders. `Unwrapped` suffix on a property means it falls back to a safe default instead of returning an optional.

## Key patterns

### Environment objects (injected at root in FreakLog.swift)
- `ToastViewModel` — call `toastViewModel.showSuccessToast()` / `showErrorToast(message:)` from any screen
- `LocationManager` — CLLocationManager wrapper; also manages search and `selectedLocation` state
- `Authenticator` — biometric lock state
- `managedObjectContext` — SwiftUI environment key for CoreData

### Navigation
`GlobalNavigationDestination` enum is the single type used as `NavigationLink` values throughout the app. Add a new case there when adding a new destination. Each tab's stack is built by `ContentScreen.view(for:)`; `Navigator.pathKeyPath(for:)` maps a `Tab` to its path. `Navigator.substanceInfoDestination(for:)` is the info page of a stored substance name (PsychonautWiki or custom), and `openInCurrentTab(_:)` pushes a destination from places that can't use a `NavigationLink`, like swipe actions (`SubstanceInfoSwipeAction` on ingestion rows).

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

### Substance names and categories
A substance's stored name is its key everywhere (ingestions, companions, units, `CustomRoa`, PsychonautWiki lookups), so show names with `PersistenceController.shared.displayName(for:)` (or `Substance.displayName`, `Ingestion.substanceDisplayName`, `CustomUnit.substanceDisplayName`) and keep using the stored name for lookups and navigation. PsychonautWiki substances can only get a display name; custom substances rename for real through `renameSubstance(from:to:)`, which also moves their `SubstanceOverride`. iCloud can bring one override row per device, so read the merged values with `substanceOverride(for:)` (`SubstanceOverrideCache.Entry.merged`) and write with `setSubstanceOverride`, which collapses the rows. Read categories with `PersistenceController.shared.categories(for:)` (the user's, else PsychonautWiki's), never `substance.categories`; `primaryCategory(for:)` is the drug class among them (skipping tags such as common), sent to leaderboards. Both are cached; changing an override also clears `InteractionChecker`'s cache. Searches over stored names add `substanceNames(withDisplayNameContaining:)`.

### AnodyneWiki
`AnodyneClient.shared` (actor) reads the JSON API of the AnodyneWiki instance at `AnodyneSubstance.baseURL` (anodyne.wiki unless changed in Settings > AnodyneWiki; build every AnodyneWiki URL from it): `lookup(_:otherNames:using:)` reads a substance and can fall back to the index’s titles and abbreviations. `indexEntries(using:)` supplies Browse AnodyneWiki, including its local class filters. Substance lookups last a week. The index and user-note refreshes have a daily cache. Only go online when the user asks (tapping load, opening an AnodyneWiki screen) or `AnodyneClient.isAutomaticLoadingEnabled`; otherwise use `cachedLookup(for:)` and `cachedUserNotes(matching:)` (the last saved notes, however old). `AnodyneLoadModel` does this for views. AnodyneWiki's dose tiers are statistics from logged doses; `Dosing.doseValues(for:)` turns them into editor values (common, strong and heavy start at their tier's lower bound, light stays empty). Substance pages are ordered by topic and combine both sources: PsychonautWiki sections take AnodyneWiki additions (`DosesSection(substance:anodyne:)` switches its ranges between both sources, remembered under `doseSourceKey`; `DurationSection(substance:anodyne:)`, `ToxicitySection`, `EffectsSection`, `InteractionsSection`), and `AnodyneTopicSections` holds the AnodyneWiki-only topics shared by the custom and AnodyneWiki-only screens. `userNotes(matching:)` reads the users' notes from all userpages (their `{sev '…'} {xeff '…'}` markup becomes plain text via `anodyneUserMarkupCleaned`). `MoleculeStructureView` draws the structure SVG natively; bump `AnodyneCacheFiles.lookupPrefix` when `AnodyneSubstance` gains fields. The lookup, index, and user-note caches belong to a single instance URL. Use the client’s request context to discard stale responses after an instance switch.

### Substance color
Each substance name maps to a `SubstanceColor` via the `SubstanceCompanion` entity. To look up a color by substance name, call the global `getColor(for: substanceName)`. Returns `SubstanceColor.fallback` (purple) if no companion exists. A `SubstanceColor` is a hex code (`#RRGGBB`), stored as its `rawValue`; `SubstanceColor(rawValue:)` also reads the palette names stored before (iCloud can still bring them from older versions, the one-off `migrateColorsToHex` rewrote local ones). The palette (`SubstanceColor.palette`, `.blue`, `.fireEngineRed`, …) is drawn in light and dark variants, any other code as it is; journal files write a palette name in `color` for older Android and iOS readers and put an exact custom color in `colorHex`. Use `ColorPickerScreen(selectedColor:usedColors:)` to pick a color (suggested swatches, the system color picker and a hex field, applied right away) and `SubstanceColor.suggested(avoiding:)` for a new substance's or note's default. Suggestions aren't taken from the palette: `distinctColors(from:count:)` generates them, each the candidate farthest in OKLab from the colors in use and the suggestions before it.

### Fetching
All fetch requests are built by the static factories on `PersistenceController` (`ingestionsRequest()`, `experiencesRequest()`, `customRoasRequest(for:)`, …) or its instance getters. Use them in `@FetchRequest(fetchRequest:)` instead of writing predicates inline. `PersistenceController.shared.getExperiences(near: date)` is the single place that knows the time-range predicate for "nearby experiences".

### Dose and duration data
Always look up dose/duration with `PersistenceController.shared.resolvedRoa(for:route:)` (or `resolvedDose`/`resolvedDuration`). It takes the user's `CustomRoa` overrides and custom substance data first, then PsychonautWiki's, then AnodyneWiki's from earlier loads (`AnodyneFallbackStore`, never online; `FreakLog.init` starts `preload()` off the main thread, and a lookup before it finishes loads the cache itself), and is backed by in-memory caches, so it is cheap to call from views. `CustomRoa` rows are keyed by `substanceName` + route; `CustomRoaCodable` is the value form used for editing and export/import. A duration phase with a single value is a fixed time. The editor starts from what the app shows without the user's data (PsychonautWiki's, filled in with AnodyneWiki's) and only creates an override when the values differ from it; an existing override is kept unless it matches the bundled PsychonautWiki data, because the AnodyneWiki part can be deleted with the cache (`CustomRoaCodable.needsSavedRow`). Older partial overrides were completed once by `migrateFillPartialSubstanceOverrides` (`CustomRoaCodable.fillingGaps(from:)`).

### Deleting ingestions
Use `IngestionDeletion.Request` for a selected ingestion. The UI uses `requestIngestionDeletion` and
`confirmIngestionDeletion` to share the prompt and honor the journal preference. An unconfirmed batch or a stock-linked
entry always asks for confirmation. `IngestionDeletion.delete(_:returningStock:)` validates the same entry IDs in the
write context and stages remote cleanup with the local deletion. Use the typed `delete(timedNote:)`,
`delete(experience:)`, and `delete(customUnit:)` methods for other entry points.

### Saving ingestions
Use `IngestionSaving.save(_:sendingWebhooksTo:)` for straightforward writes. For a transaction that also updates stock or
routine links, stage everything in the same journal edit context, save with `PersistenceController.saveJournalChanges(in:)`,
and call `IngestionSaving.didSave` after the save. `saveJournalChanges` updates affected experience sort dates first.
Unconfirmed entries stay out of webhooks and leaderboards until confirmed. Save timed notes through
`TimedNoteSaving.save(_:sendingWebhooksTo:)`.

### Adding and editing ingestions
The add (`FinishIngestionScreen`) and edit (`EditIngestionScreen`) forms share `ExperiencePickerRow`, `ConsumerRow`, `LocationButton` and `EstimateFields` (the estimate toggle with ± deviation field). Create experiences with `Experience.create(at:title:in:)` and set locations with `Ingestion.setLocation(_:)`; `ExperienceLocation.make(from:in:)` / `update(from:)` convert anything that is a `LocationValue` (`Location`, `LocationCodable`). Time labels for ingestions, notes and ratings under each `TimeDisplayStyle` come from `EventTimeText`.

PsychonautWiki and custom substances go through the same add screens: `AddIngestionSubstance` names either one, and `ChooseRouteScreenArguments`, `SubstanceAndRoute` (also used to make custom units) and `ChooseOtherRouteScreenArguments` carry it. Open the add ingestion cover with `Navigator.shared.showAddIngestionFullScreenCover(startingAt:)`; the start time reaches `FinishIngestionScreen` as the `addIngestionStartTime` environment value.

### Formulations
A formulation logs several ingestions at once. `FormulationCodable` is its value form for editing (`EditFormulationScreen` only writes on Done), export and import; `apply(to:)` replaces the components, which keep their order in `position` because CloudKit can't sync ordered relationships. Formulations are managed in Settings > Formulations and listed on the New Ingestion screen: `FormulationDoseScreen` picks the amount taken, `ingestionArguments(amount:)` scales every dose (and deviation) by it, and `FinishIngestionScreen(ingestions:dismiss:)` logs them with shared time, experience, consumer, location, note and webhooks (one color per substance; the site picker only when all share a route). Save several ingestions with `IngestionSaving.save(_:[Ingestion], sendingWebhooksTo:)`. Logged ingestions link to their formulation with the amount (`Formulation.ingestionArguments(amount:)` sets both), so the suggestions on New Ingestion and the watch offer the formulation's recent amounts (`FormulationSuggestions`) instead of its substances; deleting a formulation only drops the link. Portable exports link formulations by file-local ID. Older exports link by name when it is unique. `SubstancePickerList` is the substance list shared with the custom unit flow.

### Routines and inventory
`RoutineSchedule` and `RoutineSchedules` share recurrence and reminder logic. Schedule revisions retain earlier dates
and planned amounts. `RoutineQuickLogging` uses the same occurrence ID for Watch and widget actions so retries do not
duplicate entries. Use `Inventory` to stage stock changes in the same transaction as the linked journal entries.
`InventoryLabReportStore` stores local PDF attachments separately from the journal database and backups.

### Stats and Calendar
Use `StatsSelection` and `StatsRecords` for ranges, filters, and chart buckets. `JournalDay` defines the overnight day
boundary shared by Stats and Calendar. Pin a browsed range through `anchored` to preserve the dates. Handle chart navigation
and bar selection separately. A range change clears the bar selection, and a swipe does not select a bar.

### Live activities
Check `LiveActivities.areAvailable` (iOS 16.2+, not on Mac, allowed by the user) rather than repeating the checks. Start or switch the activity with `ActivityManager.shared.show(_:hiddenIngestions:hiddenRatings:)` and end it with `stop()`. Once shown, it follows its experience by itself: changes to the view context or the timeline settings redraw it and deleting the experience ends it, so never push a new state after saving.

### Watch app
The iPhone owns the journal; the watch app (`FreakLogWatch/`) only holds what it was sent. `PhoneWatchSession` (activated at launch, since a watch message launches the app in the background) sends the quick log suggestions built by `WatchQuickLogging.suggestions()` from `getSuggestions` as the application context whenever the view context saves or merges, and logs or undoes the watch's requests with `WatchQuickLogging.log(_:)` / `undo(_:)`, the same way the add ingestion screens do (closest experience, companion color, default webhooks, live activity). The watch sends a request as a message and queues it with `transferUserInfo` when the iPhone isn't reachable; persisted `WatchLogReceipt` records handle duplicate deliveries and Undo arriving before the original log. Formulations are suggested like substances, with ones never logged last; their doses are amounts, and a request logs one ingestion per component, with identifiers derived from the request's (`WatchLogRequest.ingestionIdentifiers`). The message types in `Watch/WatchQuickLog.swift` belong to both targets, as does `Double-asRoundedReadableString.swift`; keep them Foundation-only.

### Assistant
An optional chat (Settings → Integrations → Assistant, off by default) opened from the journal and from each experience, whose menu also has Summarize Session (the chat opens asking `AssistantChat.summaryPrompt`; answers can be added to the experience's notes). Providers are `AssistantProfile`s made from an `AssistantPreset`: the OpenAI Chat Completions, Anthropic Messages and Gemini APIs (`Assistant/Providers/`, one `AssistantChatClient` each, plain `URLSession` with server-sent events) or Apple's on-device model (`OnDeviceModel`, Foundation Models, iOS 26, weak-linked). Journal backups include the provider profiles and active model selection from user defaults. API keys live in this device’s keychain (`AssistantKeychain`). `APIConversation` runs the tool loop for the APIs and only ever appends to its history (a stopped or failed turn is repaired at the end), because providers cache prompts and sign thinking blocks; provider-specific content (Anthropic blocks, Gemini parts) is kept in `AssistantReply.native` and sent back unchanged. Requests go over HTTPS, or HTTP to localhost only (`AssistantHTTP.url`).

The model reaches the journal only through `AssistantToolbox` tools (`AssistantJournalTools`, `AssistantSubstanceTools`): each declares its parameters and progress message, and returns a small JSON object (`JSONValue`) within `Limits` (`.compact` for the on-device model). Experiences are named to the model by references like `e1` that only last for one chat. Tools use the app’s resolvers (`resolvedRoa`, `InteractionChecker`, display names). AnodyneWiki, web search, and Wikipedia follow the current profile, provider, and online lookup settings. `AssistantInstructions` writes the system instructions, including the experience a chat is about. Chats aren't saved and end with their sheet, also when the app locks. The title menu switches models within an API profile while keeping the conversation. Switching profiles starts a new chat.

### Administration site strings
`AdministrationSiteSelection` holds the route-specific site (nostril, vein, muscle, subcutaneous site). `siteString(for:)` converts it into the string stored on `Ingestion.administrationSite` and `init(route:storedSite:)` parses it back. Use `AdministrationSitePicker` for the picker and `AdministrationSiteNameStyle` for display and webhook labels.

### WebhookManager
Use `WebhookManager.shared` for send, edit, and delete operations. `WebhookDataSnapshot` and `WebhookService` build the
message from saved values. Journal transactions stage webhook cleanup with `WebhookManager.stageMessageDeletion` before
deleting entries. `WebhookDeletion` records allow cleanup to retry after the local transaction commits.

### Timeline drawing
The timeline is drawn with SwiftUI Canvas in `Timeline/`. `TimelineModel` is the pure-data input. `getSubstanceIngestionGroups()` (`Timeline/Preparation/SubstanceIngestionGroup.swift`, app only) builds the `SubstanceIngestionGroup` payload with resolved durations and dose weights already filled in, so the timeline and the live activity widget never look up substance data themselves. `ActivityManager` builds the live activity state with `Experience.liveActivityState(...)`.

### Export and import
`JournalFile` is the portable journal format. Settings → Journal Data previews native journal JSON, FreakLog Android,
and PW Journal transfers. Use the named transfer formats for compatibility differences. The codables in
`Settings/Codables/` map records both ways, and journal dates in JSON use whole milliseconds since 1970.
Use the reviewed import payload and one journal transaction for replacement. Separate preset packages live in
`JournalPresetTransfer`.

### Backups
`JournalBackup` is the native full backup. It stores journal records, file-local relationships, journal preferences, and
Assistant model settings. It excludes local operation records, caches, API keys, and inventory report PDFs.
`JournalBackupProtection` handles passphrase-protected files, and the importer also reads earlier unencrypted backups.
GitHub’s original bare format 2 uses the version 12 model and has a compatibility path separate from the later wrapped
format 2. Keep both readable. Dates use `BackupDate` with ISO 8601 and microseconds.

FreakLog 1.6 uses native backup format 6 with `FreakLog Version 17`. When the serialized schema changes, update
the format version and the expected model name as appropriate, add any required upgrade steps, and extend the fixture
tests. Keep existing fixtures intact. Use `JournalBackup.settingKeys` for journal preferences that belong in a backup.

## UserDefaults keys
Keep shared keys on `PersistenceController` and reuse feature-owned keys such as `StatsPreferences` and `JournalDay`. Store enum settings as typed `@AppStorage` values (e.g. `SaveableTimeDisplayStyle`) instead of raw strings. One-off data migrations go in the list in `PersistenceController.runPendingMigrations()`.

## Verification
Use the shared `FreakLogTests` scheme with an installed iPhone simulator from the project. For example:

```sh
xcodebuild -project FreakLog.xcodeproj -scheme FreakLogTests \
  -destination 'platform=iOS Simulator,name=<installed iPhone>' test
```

## Formatting rules
- Use the repository’s `airbnb.swiftformat` configuration when formatting Swift
- 2-space indent
- Max 130 characters per line
- No trailing whitespace
- Imports sorted; `@testable` imports at bottom
- `redundantSelf` removed (no `self.` prefix unless required)
- No block comments (`/* */`) — use line comments
- `guard else` on next line; `else` on same line for `if`

## Known issues / intentional workarounds
- `@preconcurrency import CoreData` and `@preconcurrency import CoreLocation` appear on some files — this suppresses Swift concurrency warnings while full Sendable conformance is pending. Do not remove without fixing the underlying concurrency issues.

## What not to do
- Do not add new global `print()` statements for non-error paths. Errors that reach `catch` blocks may log via `print` but routine flow should not.
- Do not add new `?? ""` unwrapping properties to CoreData helpers unless the empty string case is semantically meaningful. Use the existing `Unwrapped` properties or inline `?? ""`.
- Do not create a new `ChartData`-style struct in entity extensions — use `ExperienceLogic` for shared logic types.
- Do not add a new fetch-request-then-filter pattern for experiences near a time — use `PersistenceController.shared.getExperiences(near:)`.
- Do not read `substance.getDose/getDuration` directly outside previews — use the resolver so custom overrides apply.
