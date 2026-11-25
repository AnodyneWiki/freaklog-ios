# FreakLog

FreakLog is an open-source iOS journal for tracking substance use and a fork of [PsyLog](https://codeberg.org/PsyLog/PsyLog-iOS).

**Public TestFlight beta coming soon™.**

## Journal and logging

- Log an ingestion now or backdate it, review it before saving, or save a batch with a different time for each entry. Keep an entry unconfirmed for later review. Add timed notes, mood and energy, ratings, and locations. Choose whether to confirm single-entry deletion.
- Browse entries and experiences in Journal, filter to favorites, or open a day in Calendar. Search the journal and substance library together. Set an overnight day boundary shared by Calendar and Stats.
- Compare participants on one experience timeline, inspect estimated phases, and optionally overlay heart rate from Apple Health. Add private reminders and move selected entries between experiences with Undo.
- Prefill ingestion drafts from Shortcuts, scan previously paired packages from Add Ingestion, and log recent substances or formulations from Apple Watch. The Watch queues entries while the iPhone is unreachable.

## Stats and substance reference

- Choose a date range and filter by substance, route, person, or tag. Drag a chart to preview adjacent dates, use the arrows for small or large jumps, and tap a bar to see its entries.
- Compare amount trends by substance and unit, review a substance’s history, pin filtered views, and track personal goals.
- Browse offline PsychonautWiki reference data or connect to an AnodyneWiki instance. Filter the AnodyneWiki catalog by class and compare sources by route. See timings, interactions, reagent references, molecular structures, and experience reports. [AnodyneWiki](https://anodyne.wiki)
- Organize substances with personal tags and colors, override reference values by route, and review duplicate custom names. Choose simple or medical administration-site names. Save custom units and formulations, including nested blends.

## Routines and inventory

- See what’s overdue, due today, or coming up. Schedule daily, weekday, interval, monthly, or as-needed routines. Preview upcoming times, set per-time amounts, and log, skip, or snooze scheduled entries.
- Open your journal from widgets and mark an eligible routine as taken from the Home Screen or Apple Watch.
- Track stock by container, draw from stock when logging, and preview transfers between containers. Scan package labels, remember German PZNs, and look up German medication names offline.
- Attach a lab report PDF to a container and open it during ingestion review. PDFs stay on the device. Find Inventory, Routines, Safer Use, and the Spray Calculator in Tools.

## Reports, transfers, and privacy

- Preview and edit an experience report before sharing it as Markdown or an image. Review a selected journal export or generate a self-reported clinician summary as a PDF.
- Preview imports and exports, including supported FreakLog Android and PW Journal transfers. Share saved products, substance definitions, and other presets separately. Export from Shortcuts.
- Use optional iCloud sync or passphrase-protected FreakLog backups. Verify a backup, keep local recovery copies, or set up rotating encrypted backups. Native backups can include journal settings and Assistant model profiles. Assistant API keys stay in the device Keychain.
- Ask the optional Assistant about your journal or summarize an experience. Use Apple Intelligence on supported devices or connect your own OpenAI-compatible, Anthropic, or Gemini provider. Optional online lookups include web search and Wikipedia.
- Choose which compatible webhooks receive updates or opt in to a leaderboard server. Use journal locking, discreet widgets, and alternate app icons to customize how the app appears.

Open **Settings → What’s New** for version-by-version highlights.

**Triple-tap the closed eye in Settings to show all PsychonautWiki substances.**

For substance information, we recommend [AnodyneWiki](https://anodyne.wiki), with [TripSit](https://tripsit.me/) as a secondary reference.

<p>
<img src="README Assets/presentation.png" width="100%">
</p>

## Installation and building

Open `FreakLog.xcodeproj` in Xcode. The iPhone app targets iOS 16 or later, the widget extension targets iOS 16.2 or later, and the Watch app targets watchOS 10 or later. Xcode resolves dependencies with Swift Package Manager. For simulator tests and contributor guidance, see [AGENTS.md](AGENTS.md).
