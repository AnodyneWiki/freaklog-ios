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
| `FreakLogTests` | Unit tests (decoding, interaction logic, export/import round trip) |
| `FreakLogWatch` | Watch app for quick logging (watchOS 10+), embedded in the main app |

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

CoreData helper extensions live in `CoreDataHelpers/`. Each entity has a corresponding `EntityName-CoreDataHelpers.swift` file with computed properties and convenience methods. `Unwrapped` suffix on a property means it falls back to a safe default instead of returning an optional.

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
`AnodyneClient.shared` (actor) reads the JSON API of the AnodyneWiki instance at `AnodyneSubstance.baseURL` (anodyne.wiki unless changed in Settings > AnodyneWiki; build every AnodyneWiki URL from it): `lookup(_:otherNames:)` for a substance (falls back to the index's titles and abbreviations) and `indexEntries()` for search. Results are cached on disk for a week as `AnodyneSubstance`, which is parsed leniently from the API's varying fields. Only go online when the user asks (tapping load, opening an AnodyneWiki screen) or `AnodyneClient.isAutomaticLoadingEnabled`; otherwise use `cachedLookup(for:)` and `cachedUserNotes(matching:)` (the last saved notes, however old). `AnodyneLoadModel` does this for views. AnodyneWiki's dose tiers are statistics from logged doses; `Dosing.doseValues(for:)` turns them into editor values (common, strong and heavy start at their tier's lower bound, light stays empty). Substance pages are ordered by topic and combine both sources: PsychonautWiki sections take AnodyneWiki additions (`DosesSection(substance:anodyne:)` switches its ranges between both sources, remembered under `doseSourceKey`; `DurationSection(substance:anodyne:)`, `ToxicitySection`, `EffectsSection`, `InteractionsSection`), and `AnodyneTopicSections` holds the AnodyneWiki-only topics shared by the custom and AnodyneWiki-only screens. `userNotes(matching:)` reads the users' notes from all userpages (their `{sev '…'} {xeff '…'}` markup becomes plain text via `anodyneUserMarkupCleaned`). `MoleculeStructureView` draws the structure SVG natively; bump the cache file prefix in `AnodyneClient.lookupFile(for:)` when `AnodyneSubstance` gains fields.

### Substance color
Each substance name maps to a `SubstanceColor` via the `SubstanceCompanion` entity. To look up a color by substance name, call the global `getColor(for: substanceName)`. Returns `SubstanceColor.fallback` (purple) if no companion exists. A `SubstanceColor` is a hex code (`#RRGGBB`), stored as its `rawValue`; `SubstanceColor(rawValue:)` also reads the palette names stored before (iCloud can still bring them from older versions, the one-off `migrateColorsToHex` rewrote local ones). The palette (`SubstanceColor.palette`, `.blue`, `.fireEngineRed`, …) is drawn in light and dark variants, any other code as it is; journal files write palette colors by name (`exportValue`) for the Android app. Use `ColorPickerScreen(selectedColor:usedColors:)` to pick a color (suggested swatches, the system color picker and a hex field, applied right away) and `SubstanceColor.suggested(avoiding:)` for a new substance's or note's default. Suggestions aren't taken from the palette: `distinctColors(from:count:)` generates them, each the candidate farthest in OKLab from the colors in use and the suggestions before it.

### Fetching
All fetch requests are built by the static factories on `PersistenceController` (`ingestionsRequest()`, `experiencesRequest()`, `customRoasRequest(for:)`, …) or its instance getters. Use them in `@FetchRequest(fetchRequest:)` instead of writing predicates inline. `PersistenceController.shared.getExperiences(near: date)` is the single place that knows the time-range predicate for "nearby experiences".

### Dose and duration data
Always look up dose/duration with `PersistenceController.shared.resolvedRoa(for:route:)` (or `resolvedDose`/`resolvedDuration`). It takes the user's `CustomRoa` overrides and custom substance data first, then PsychonautWiki's, then AnodyneWiki's from earlier loads (`AnodyneFallbackStore`, never online; `FreakLog.init` starts `preload()` off the main thread, and a lookup before it finishes loads the cache itself), and is backed by in-memory caches, so it is cheap to call from views. `CustomRoa` rows are keyed by `substanceName` + route; `CustomRoaCodable` is the value form used for editing and export/import. A duration phase with a single value is a fixed time. The editor starts from what the app shows without the user's data (PsychonautWiki's, filled in with AnodyneWiki's) and only creates an override when the values differ from it; an existing override is kept unless it matches the bundled PsychonautWiki data, because the AnodyneWiki part can be deleted with the cache (`CustomRoaCodable.needsSavedRow`). Older partial overrides were completed once by `migrateFillPartialSubstanceOverrides` (`CustomRoaCodable.fillingGaps(from:)`).

### Deleting ingestions
Delete ingestions, timed notes, experiences and custom units through `IngestionDeletion.delete(ingestions:)` / `delete(timedNote:)` / `delete(experience:)` / `delete(customUnit:)`. It deletes locally right away, then removes sent webhook messages and notifies leaderboard servers in the background. For bulk deletes elsewhere, collect `remoteCleanUp(for:timedNotes:)` before deleting and call it afterwards.

### Saving ingestions
Save added and edited ingestions with `IngestionSaving.save(_:sendingWebhooksTo:)`. It saves the view context, sends a new ingestion to the chosen webhook presets or updates the sent messages of an edited one, and syncs leaderboards. An experience's `sortDate` is kept on its first ingestion's time by the view context right before every save, so screens never set it themselves (only `Experience.create` gives the initial one). Timed notes are sent like ingestions: save them with `TimedNoteSaving.save(_:sendingWebhooksTo:)` (new ones are sent, edited ones update their messages); `WebhookPreset.defaultPresetObjectIDs()` is what is sent to when nothing is chosen (every enabled preset, if sending is on).

### Adding and editing ingestions
The add (`FinishIngestionScreen`) and edit (`EditIngestionScreen`) forms share `ExperiencePickerRow`, `ConsumerRow`, `LocationButton` and `EstimateFields` (the estimate toggle with ± deviation field). Create experiences with `Experience.create(at:title:in:)` and set locations with `Ingestion.setLocation(_:)`; `ExperienceLocation.make(from:in:)` / `update(from:)` convert anything that is a `LocationValue` (`Location`, `LocationCodable`). Time labels for ingestions, notes and ratings under each `TimeDisplayStyle` come from `EventTimeText`.

PsychonautWiki and custom substances go through the same add screens: `AddIngestionSubstance` names either one, and `ChooseRouteScreenArguments`, `SubstanceAndRoute` (also used to make custom units) and `ChooseOtherRouteScreenArguments` carry it. Open the add ingestion cover with `Navigator.shared.showAddIngestionFullScreenCover(startingAt:)`; the start time reaches `FinishIngestionScreen` as the `addIngestionStartTime` environment value.

### Formulations
A formulation logs several ingestions at once. `FormulationCodable` is its value form for editing (`EditFormulationScreen` only writes on Done), export and import; `apply(to:)` replaces the components, which keep their order in `position` because CloudKit can't sync ordered relationships. Formulations are managed in Settings > Formulations and listed on the New Ingestion screen: `FormulationDoseScreen` picks the amount taken, `ingestionArguments(amount:)` scales every dose (and deviation) by it, and `FinishIngestionScreen(ingestions:dismiss:)` logs them with shared time, experience, consumer, location, note and webhooks (one color per substance; the site picker only when all share a route). Save several ingestions with `IngestionSaving.save(_:[Ingestion], sendingWebhooksTo:)`. Logged ingestions link to their formulation with the amount (`Formulation.ingestionArguments(amount:)` sets both), so the suggestions on New Ingestion and the watch offer the formulation's recent amounts (`FormulationSuggestions`) instead of its substances; deleting a formulation only drops the link. Exports name the formulation on each ingestion. `SubstancePickerList` is the substance list shared with the custom unit flow.

### Live activities
Check `LiveActivities.areAvailable` (iOS 16.2+, not on Mac, allowed by the user) rather than repeating the checks. Start or switch the activity with `ActivityManager.shared.show(_:hiddenIngestions:hiddenRatings:)` and end it with `stop()`. Once shown, it follows its experience by itself: changes to the view context or the timeline settings redraw it and deleting the experience ends it, so never push a new state after saving.

### Watch app
The iPhone owns the journal; the watch app (`FreakLogWatch/`) only holds what it was sent. `PhoneWatchSession` (activated at launch, since a watch message launches the app in the background) sends the quick log suggestions built by `WatchQuickLogging.suggestions()` from `getSuggestions` as the application context whenever the view context saves or merges, and logs or undoes the watch's requests with `WatchQuickLogging.log(_:)` / `undo(ingestionsWithIdentifiers:)`, the same way the add ingestion screens do (closest experience, companion color, default webhooks, live activity). The watch sends a request as a message and queues it with `transferUserInfo` when the iPhone isn't reachable; requests carry the new ingestion's identifier, so one delivered twice is logged once. Formulations are suggested like substances, with ones never logged last; their doses are amounts, and a request logs one ingestion per component, with identifiers derived from the request's (`WatchLogRequest.ingestionIdentifiers`). The message types in `Watch/WatchQuickLog.swift` belong to both targets, as does `Double-asRoundedReadableString.swift`; keep them Foundation-only.

### Assistant
An optional chat (Settings > Assistant, off by default) opened from the journal and from each experience, whose menu also has Summarize Session (the chat opens asking `AssistantChat.summaryPrompt`; answers can be added to the experience's notes). Providers are `AssistantProfile`s made from an `AssistantPreset`: the OpenAI Chat Completions, Anthropic Messages and Gemini APIs (`Assistant/Providers/`, one `AssistantChatClient` each, plain `URLSession` with server-sent events) or Apple's on-device model (`OnDeviceModel`, Foundation Models, iOS 26, weak-linked). Profiles live in this device's user defaults and API keys in its keychain (`AssistantKeychain`, this device only); neither is in backups. `APIConversation` runs the tool loop for the APIs and only ever appends to its history (a stopped or failed turn is repaired at the end), because providers cache prompts and sign thinking blocks; provider-specific content (Anthropic blocks, Gemini parts) is kept in `AssistantReply.native` and sent back unchanged. Requests go over HTTPS, or HTTP to localhost only (`AssistantHTTP.url`).

The model reaches the journal only through `AssistantToolbox` tools (`AssistantJournalTools`, `AssistantSubstanceTools`): each declares its parameters, transcript label and result summary, and returns a small JSON object (`JSONValue`) within `Limits` (`.compact` for the on-device model). Experiences are named to the model by references like `e1` that only last for one chat. Tools use the app's resolvers (`resolvedRoa`, `InteractionChecker`, display names) like screens do; AnodyneWiki lookups only request titles from its own index, and can be turned off. `AssistantInstructions` writes the system instructions, including the experience a chat is about. Chats aren't saved and end with their sheet, also when the app locks.

### Administration site strings
`AdministrationSiteSelection` holds the route-specific site (nostril, vein, muscle, subcutaneous site). `siteString(for:)` converts it into the string stored on `Ingestion.administrationSite` and `init(route:storedSite:)` parses it back. Use `AdministrationSitePicker` for the picker.

### WebhookManager
All webhook HTTP calls go through `WebhookManager.shared`. It handles send, edit, and delete (for ingestion deletion and preset deletion). Message content is built from the saved ingestion by `WebhookDataSnapshot(ingestion:)` and `WebhookService.content(for:settings:)`, or for a timed note by `content(forNote:settings:)` with its own layout (`webhookNoteTemplateKey`), so send and edit always agree. Deletion helpers (`executeDeletions`, `buildPresetDeletionTargets`) are private; call the public `deleteWebhookMessages(for:)`, `deleteMessage(_:)` or `deletePreset(_:deletingMessages:)`.

### Timeline drawing
The timeline is drawn with SwiftUI Canvas in `Timeline/`. `TimelineModel` is the pure-data input. `getSubstanceIngestionGroups()` (`Timeline/Preparation/SubstanceIngestionGroup.swift`, app only) builds the `SubstanceIngestionGroup` payload with resolved durations and dose weights already filled in, so the timeline and the live activity widget never look up substance data themselves. `ActivityManager` builds the live activity state with `Experience.liveActivityState(...)`.

### Export and import
`JournalFile` is the JSON export the Android app reads (Settings > Export JSON); it leaves out settings, webhooks, sprays and other iOS-only data. Each codable in `Settings/Codables/` maps its entity both ways: `init(_:)` for export and `insert(into:)` for import. `JournalFile.init(experiences:...)` builds an export and `JournalFile.insert(into:)` imports one, linking companions, custom units and experiences. Dates are whole milliseconds since 1970 (the Android format); read and write them with `decodeMillis`/`encodeMillis`. Add a new field to both sides of its codable.

### Backups
`JournalBackup` (Settings > Export Backup) restores everything exactly: versioned, pretty-printed JSON that mirrors every entity and attribute of the data model generically (records of attributes and relationships, which refer to ids only valid within the backup) plus the settings in `JournalBackup.settingKeys`. The import button reads both formats; `JournalBackup.read` returns nil for other files, and a backup is restored in one save, so a broken one leaves the journal as it was. Dates are ISO 8601 with microseconds (`BackupDate`). New journal settings go into `settingKeys`; ones about the device don't.

Newer versions of the app must keep importing older backups. When the data model or the settings written change, bump `JournalBackup.formatVersion` and `dataModelVersion` (`testTheFormatFollowsTheDataModel` fails until then), add a step to `upgrades` if older backups need changing (added attributes, entities and settings need none; removed or renamed ones do, e.g. with `renameAttribute`), and add a backup of the new version as `FreakLogTests/Backup vN.json` with a test that imports it. Never edit an existing fixture.

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
- `swiftlint:disable` blocks in `Settings-ViewModel.swift` (old export conversion in `tryConvertFile`) and a few other files are justified by the genuinely complex/long functions — do not split them artificially just to remove the disable.

## What not to do
- Do not add new global `print()` statements for non-error paths. Errors that reach `catch` blocks may log via `print` but routine flow should not.
- Do not add new `?? ""` unwrapping properties to CoreData helpers unless the empty string case is semantically meaningful. Use the existing `Unwrapped` properties or inline `?? ""`.
- Do not create a new `ChartData`-style struct in entity extensions — use `ExperienceLogic` for shared logic types.
- Do not duplicate the `DeletionTarget` pattern in WebhookManager — use `buildPresetDeletionTargets` / `executeDeletions`.
- Do not add a new fetch-request-then-filter pattern for experiences near a time — use `PersistenceController.shared.getExperiences(near:)`.
- Do not read `substance.getDose/getDuration` directly outside previews — use the resolver so custom overrides apply.
