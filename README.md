# FreakLog

FreakLog is an open-source iOS journal for tracking substance use and a fork of [PsyLog](https://codeberg.org/PsyLog/PsyLog-iOS).

**Public TestFlight beta coming soon™.**

The journal includes offline harm reduction reference data, experience timelines, ratings, timed notes, calendar views, Live Activities, tolerance estimates, and custom substances and units.

## Highlights

- **Journal and logging.** Review and correct entries, log a batch with individual timestamps, or open a draft by scanning a paired package. Move entries between experiences with Undo.
- **Search and Stats.** Search entries and substances together. Browse date ranges, compare recorded amounts, and open the entries behind a chart. Save commonly used filters.
- **Experience timelines.** Inspect entries and notes on one time axis. Optionally display heart-rate measurements from Apple Health.
- **Products and inventory.** Build formulations from saved products and custom units. Track stock by container, preview stock transfers, and keep local lab report PDFs with a container.
- **Routines and Apple Watch.** See what’s due, schedule reminders, and log from iPhone or Apple Watch. The Home Screen widget can mark eligible occurrences as taken on iOS 17 or later.
- **Backups and transfers.** Review a file before replacing your journal. Protect FreakLog backups with a passphrase, verify them before restoring, and preview transfers for FreakLog Android and PW Journal. Assistant API keys and inventory PDFs stay on the device.
- **Reports.** Review and share a selected part of your journal, an editable experience report, or a clinician summary.
- **Substance reference.** Compare route information from PsychonautWiki and [AnodyneWiki](https://anodyne.wiki), and keep personal overrides for doses and timings.
- **Assistant.** Ask about your journal or summarize an experience. Use Apple Intelligence on supported devices running iOS 26 or configure a model provider. Optional online lookups provide context within the conversation.
- **Sync and sharing.** Sync through iCloud, send selected updates to Discord-compatible webhooks, or opt in to sharing entries with selected leaderboard servers.

**Triple-tap the closed eye in Settings to show all PsychonautWiki substances.**

For substance information, we recommend [AnodyneWiki](https://anodyne.wiki), with [TripSit](https://tripsit.me/) as a secondary reference.

<p>
<img src="README Assets/presentation.png" width="100%">
</p>

## Installation and Building

Open `FreakLog.xcodeproj` in Xcode. The iPhone app requires iOS 16 or later. Its widget extension requires iOS 16.2 or later, and the Watch app requires watchOS 10 or later. Dependencies are resolved by Swift Package Manager.
