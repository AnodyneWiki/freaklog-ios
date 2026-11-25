# FreakLog

FreakLog is a fully open source continuation fork of the now closed-source and in-app-purchase-ridden PW Journal app.

Features:
- Easy offline access to key harm reduction information (dosage, tolerance, duration, interactions)
- Ingestion journal with effect timelines, ratings, timed notes and a calendar
- Live Activity with the timeline of the current experience
- Tolerance and usage stats
- Custom substances, custom units and your own dose and duration data for any substance and route
- Optional [AnodyneWiki](https://anodyne.wiki) integration: logged dose tiers, user notes, timings, legal status, reagent tests, molecular structures and experience reports, combined with the PsychonautWiki data on each substance page
- Webhooks (e.g. Discord) and leaderboards
- iCloud sync, and export and import of your journal

**Triple tap on the closed eye in settings to see all PW substances.** (necessary to get past App Store review)

We strongly recommend using [TripSit](https://tripsit.me/) instead of PW to look up info on substances.

<p>
<img src="README Assets/presentation.png" width="100%">
</p>

## Installation and Building

The project should be opened with Xcode 15 or newer; the app runs on iOS 16.2 and newer.
Dependencies are managed with [Swift Package Manager](https://swift.org/package-manager), no further setup is needed.
