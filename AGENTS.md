# FreakLog iOS

FreakLog is an iOS substance-use journal built with SwiftUI, CoreData, and optional CloudKit sync.

## Build and verify

Open `FreakLog.xcodeproj` in Xcode and resolve its Swift Package Manager dependencies. Use the shared
`FreakLogTests` scheme for the iPhone simulator and the `FreakLogWatch` scheme for Watch changes.

```sh
xcodebuild -project FreakLog.xcodeproj -scheme FreakLogTests -showdestinations
xcodebuild -project FreakLog.xcodeproj -scheme FreakLogTests \
  -destination 'platform=iOS Simulator,id=<simulator UUID>' CODE_SIGNING_ALLOWED=NO test
```

Register new app, widget, and test files in the appropriate Xcode target. The Watch source directory is
synchronized by Xcode. Keep local signing settings and unrelated project-file reordering out of commits.
For interface changes, check the normal entry point in the simulator and use a representative journal.

## Releases

Whenever you bump the app’s `MARKETING_VERSION`, create a signed, annotated Git tag named `vX.Y.Z`
on the version bump commit. Use `FreakLog X.Y.Z` as the tag message. Release history is maintained in
`WhatsNewScreen` in `FreakLog/Settings/SettingsScreen.swift`.

## Where to work

| Area | Paths |
|---|---|
| App lifecycle and navigation | `FreakLog/FreakLog.swift`, `AppDelegate.swift`, and `Main/Navigation/` |
| Journal persistence and shared operations | `FreakLog/Persistence.swift`, `Main.xcdatamodeld/`, and `CoreDataHelpers/` |
| Journal, search, and entry forms | `FreakLog/Journal/`, `Search/`, and `Add Ingestion/` |
| Stats and experience timelines | `FreakLog/Stats/`, `Timeline/`, and journal components |
| Product, stock, and schedule tools | `FreakLog/Inventory/` and `Routines/` |
| Settings and file formats | `FreakLog/Settings/`, `Settings/Codables/`, and `Settings/Backup/` |
| Integrations | `FreakLog/Assistant/`, `Webhooks/`, `Leaderboard/`, and `Watch/` |
| Extensions and tests | `FreakLogWatch/`, `TimelineWidget/`, and `FreakLogTests/` |

## Journal writes

- Use `GlobalNavigationDestination` and the existing `Navigator` destinations for shared navigation.
- Reuse `PersistenceController` fetches and `getExperiences(near:)` for nearby experiences.
  Put shared experience calculations in `ExperienceLogic`.
- Use `IngestionSaving.save(_:sendingWebhooksTo:)` for ordinary writes. For writes involving stock or routine
  links, stage everything in one journal edit context, save through
  `PersistenceController.saveJournalChanges(in:)`, then call `IngestionSaving.didSave`. The save updates
  experience sort dates. Save timed notes through `TimedNoteSaving`.
- Unconfirmed entries stay outside publication and confirmed totals. Use the existing confirmation logic for
  their stock, routine, and batch links.
- Use `IngestionDeletion.Request` and the shared confirmation UI for ingestion deletes. The request validates
  the same entry IDs at write time. Unconfirmed batches and stock-linked entries always require confirmation.
  Use the typed deletion APIs for notes, experiences, and custom units. Remote cleanup is staged before saving.

## Names, sources, and units

- Use stored substance names as record and lookup keys. Use `PersistenceController.displayName(for:)` for
  presentation. Read categories and route overrides through the persistence resolvers.
- Use `Ingestion.isMine` and `Ingestion.storedConsumerName(_:)` for participant ownership.
  Use `AdministrationSiteSelection` to store sites and `AdministrationSiteNameStyle` to render them.
- Read dose, duration, and timing through `resolvedRoa(for:route:)` and the existing timeline helpers.
  These incorporate personal overrides and previously downloaded AnodyneWiki data.
- Keep AnodyneWiki requests and caches scoped to their instance through `AnodyneClient` and its request context.
  Browse filters use the downloaded index. Reuse `AnodyneLoadModel` for on-demand and opted-in loading.
- Use `SubstanceColor` for old palette values and exact colors. Portable journal data preserves exact values
  in `colorHex` with a legacy palette-compatible `color` alongside it.
- Use `FormulationCodable` to edit and transfer formulations and `ingestionArguments(amount:)` to scale components.
  Portable files link formulations by file-local ID. Older files can fall back to a unique name.

## Stats, routines, and inventory

- Use `StatsSelection` and `StatsRecords` for date ranges, filters, and buckets. Stats and Calendar share
  `JournalDay`. Anchor a browsed range when pinning it. Range changes clear chart bar selection.
- Use `RoutineSchedule` and `RoutineSchedules` for recurrence, reminder previews, and occurrence identity.
  Schedule revisions retain previous dates and planned amounts. `RoutineQuickLogging` shares occurrence
  IDs between Watch and widget actions so retries cannot log the same occurrence twice.
- Stage stock changes through `Inventory` in the same transaction as linked entries. Inventory lab PDFs are
  local attachments in `InventoryLabReportStore`, outside the journal database and backups.
- Keep Watch payloads in `Watch/WatchQuickLog.swift` Foundation-only. `WatchLogReceipt` protects against
  duplicate delivery and Undo arriving ahead of a log.
- Use `LiveActivities.areAvailable` and the existing `ActivityManager` entry points. An active timeline
  follows its saved experience. Widget and Watch data use prepared inputs from the phone.

## Transfers and backups

- Keep `JournalFile` and its named Android and PW Journal transfers separate from `JournalBackup`.
  Portable journal JSON uses milliseconds since 1970. Review the decoded payload before replacing data
  in one transaction. Saved-product presets use `JournalPresetTransfer`.
- Native backups store journal data, preferences, and Assistant model settings. Local operation records,
  caches, API keys, and inventory PDFs stay out of backups. Use `JournalBackupProtection` for passphrases.
- Preserve support for GitHub’s original bare format 2 with model version 12 and the later wrapped format 2.
  The source of truth for the current format is `JournalBackup.formatVersion` and `dataModelVersion`.
  For schema changes, update the format and model as appropriate, extend the upgrade and fixture tests,
  and keep existing fixtures intact.
- Add backup-eligible journal preferences to `JournalBackup.settingKeys`. Shared preference keys live on
  `PersistenceController`. Reuse feature-owned keys such as `StatsPreferences` and `JournalDay`.

## Integrations and style

- Route webhook writes through `WebhookManager` and `WebhookService`. Stage cleanup through
  `WebhookManager.stageMessageDeletion` so `WebhookDeletion` can retry independently of the local write.
- Use `AssistantToolbox` and its existing journal filters for model access. Provider profiles and online lookup
  preferences control which tools are available. API keys live in `AssistantKeychain`, and chats are ephemeral.
- Match the surrounding Swift. For formatting, use `airbnb.swiftformat`. Keep `@testable` imports last and
  preserve the existing concurrency workarounds until their underlying types are corrected.
