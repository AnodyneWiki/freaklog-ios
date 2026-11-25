# FreakLog

FreakLog is an open-source iOS journal for tracking substance use and a fork of [PsyLog](https://codeberg.org/PsyLog/PsyLog-iOS).

**Public TestFlight beta coming soon™.**

The journal includes offline harm reduction reference data, experience timelines, ratings, timed notes, calendar views, Live Activities, tolerance estimates, and custom substances and units.

## Highlights

- **Assistant.** Ask about your journal or summarize an experience and save the summary to your notes. Use Apple Intelligence on supported devices running iOS 26 or connect your own OpenAI-compatible, Anthropic, or Gemini provider. Optional web access includes dedicated Wikipedia lookups and general web search via Exa.
- **Apple Watch quick logging.** Log recent substances and formulations, adjust the amount with the Digital Crown, and undo an entry. The watch queues entries while the iPhone is unreachable.
- **Formulations.** Save mixtures as presets and scale every ingredient from a single amount when you log them.
- **All Ingestions.** Browse individual entries and timed notes alongside a timeline with a configurable time range. Switch between ingestions and experiences, or filter either view to favorite experiences. Record an administration site and location per entry, and see ingestion counts over time in Statistics.
- **Substance customization.** Rename substances, set categories, override dose and duration data by route, and choose colors with suggested swatches, the system color picker, or hex codes.
- **AnodyneWiki integration.** Look up substances on an instance of your choice and see logged dose tiers, timings, notes, legal status, reagent tests, molecular structures, and experience reports alongside PsychonautWiki data. [AnodyneWiki](https://anodyne.wiki)
- **iCloud sync and backups.** Sync your journal with iCloud or export a backup of your journal, substance customizations, app settings, and assistant model profiles. Assistant API keys stay in the device Keychain.
- **Webhooks and leaderboards.** Send ingestion and timed-note updates to multiple Discord-compatible webhooks, or opt in to sharing ingestions with leaderboard servers you select.

**Triple-tap the closed eye in Settings to show all PsychonautWiki substances.**

For substance information, we recommend [AnodyneWiki](https://anodyne.wiki), with [TripSit](https://tripsit.me/) as a secondary reference.

<p>
<img src="README Assets/presentation.png" width="100%">
</p>

## Installation and Building

Open `FreakLog.xcodeproj` in Xcode. The app targets iOS 16.2 and watchOS 10 or later. Dependencies are resolved by Swift Package Manager.
