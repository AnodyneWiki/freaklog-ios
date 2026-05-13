# FreakLog Watch App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a watchOS 10+ companion app to FreakLog (view, log, browse, harm-reduction info) sharing data via CloudKit and code via a new `FreakLogCore` Swift Package.

**Architecture:** New local SwiftPM package `FreakLogCore` consumed by iOS app, existing `LiveActivityExtension`, new `FreakLog Watch App`, and new `FreakLog Watch Widgets` extension. Watch syncs through the existing `iCloud.woof.freaklog` `NSPersistentCloudKitContainer`.

**Tech Stack:** Swift 5.9+, SwiftUI, Core Data + CloudKit, WidgetKit, ActivityKit (existing), LocalAuthentication, Swift Package Manager, XCTest. Xcode 15+, iOS 16+, watchOS 10+.

**Manual prerequisites the user must complete (not automatable):**
1. In Apple Developer Portal: create app IDs `woof.freaklog.watchkitapp` and `woof.freaklog.watchkitapp.widgets`. Enable "iCloud" capability on each, select container `iCloud.woof.freaklog` (and `-debug`).
2. In Xcode > Signing & Capabilities for new targets: tick "Automatically manage signing", select team, attach to the iCloud container.
3. Update App Store Connect record to add the watch app target before TestFlight build upload.

**Reference IDs (use exactly):**
- iOS app bundle: `woof.freaklog`
- Watch app bundle: `woof.freaklog.watchkitapp`
- Watch widgets bundle: `woof.freaklog.watchkitapp.widgets`
- CloudKit container: `iCloud.woof.freaklog` (release) / `iCloud.woof.freaklog-debug` (debug)
- App Group (new): `group.woof.freaklog`

---

# Phase 1 — Extract `FreakLogCore` Swift Package

**Outcome:** iOS app + Live Activity widget compile, run, and pass tests identically while consuming a new local SwiftPM package containing all model, persistence, decoding, timeline, and shared-logic code.

**Verification of phase end:**
- `xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog -destination 'platform=iOS Simulator,name=iPhone 15'` passes.
- App launches, all existing screens render, Live Activity timeline still works.

## Task 1.1: Capture pre-refactor baseline

**Files:**
- Create: `docs/superpowers/baselines/phase1-baseline.txt`

- [ ] **Step 1: Run iOS test suite, capture output**

```bash
cd /Users/pilz/Documents/FreakLog-iOS
xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tee docs/superpowers/baselines/phase1-baseline.txt
```
Expected: all tests pass; record exact pass count.

- [ ] **Step 2: Build for device-arch (catches Release-only issues)**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'generic/platform=iOS' -configuration Release 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit baseline**

```bash
git add docs/superpowers/baselines/phase1-baseline.txt
git commit -m "chore: capture FreakLog test baseline before package extraction

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.2: Create empty `FreakLogCore` Swift Package

**Files:**
- Create: `FreakLogCore/Package.swift`
- Create: `FreakLogCore/Sources/FreakLogCore/FreakLogCore.swift` (placeholder marker file)
- Create: `FreakLogCore/Tests/FreakLogCoreTests/FreakLogCoreTests.swift`

- [ ] **Step 1: Generate package skeleton**

```bash
mkdir -p FreakLogCore/Sources/FreakLogCore FreakLogCore/Tests/FreakLogCoreTests
cd FreakLogCore && swift package init --type library --name FreakLogCore
```

- [ ] **Step 2: Replace `Package.swift` with the platform-correct version**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreakLogCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .watchOS(.v10)],
    products: [
        .library(name: "FreakLogCore", targets: ["FreakLogCore"]),
    ],
    targets: [
        .target(
            name: "FreakLogCore",
            resources: [
                .process("Resources"),
                .copy("Model/Main.xcdatamodeld"),
            ]
        ),
        .testTarget(name: "FreakLogCoreTests", dependencies: ["FreakLogCore"]),
    ]
)
```

- [ ] **Step 3: Make `Sources/FreakLogCore/FreakLogCore.swift` a public marker**

```swift
import Foundation

public enum FreakLogCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Make `Tests/FreakLogCoreTests/FreakLogCoreTests.swift` a smoke test**

```swift
import XCTest
@testable import FreakLogCore

final class FreakLogCoreSmokeTests: XCTestCase {
    func test_packageHasVersion() {
        XCTAssertFalse(FreakLogCore.version.isEmpty)
    }
}
```

- [ ] **Step 5: Verify package builds and test passes standalone**

```bash
cd FreakLogCore && swift test
```
Expected: PASS.

- [ ] **Step 6: Add the package as a local dependency to `FreakLog.xcodeproj`**

In Xcode: File → Add Package Dependencies → Add Local… → select `/Users/pilz/Documents/FreakLog-iOS/FreakLogCore` → add to `FreakLog` target. Then add `FreakLogCore` library to **Frameworks, Libraries, and Embedded Content** of both `FreakLog` and `LiveActivityExtension` targets.

After Xcode updates the pbxproj, verify:

```bash
grep -E "FreakLogCore" FreakLog.xcodeproj/project.pbxproj | head -5
```
Expected: lines referencing `FreakLogCore` appear.

- [ ] **Step 7: Confirm iOS still builds**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add FreakLogCore/ FreakLog.xcodeproj/
git commit -m "feat: add empty FreakLogCore Swift Package and link to iOS targets

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.3: Move pure-value decoding types into the package

**Files:**
- Move: `FreakLog/Decoding/{Substance,Roa,RoaDose,RoaDuration,RoaRange,DurationRange,Category,Interactions,SubstanceFile,SubstanceRepo,Tolerance}.swift` → `FreakLogCore/Sources/FreakLogCore/Decoding/`
- Move: `FreakLog/Assets/substances.json` → `FreakLogCore/Sources/FreakLogCore/Resources/substances.json`
- Modify: every moved type — add `public` access modifiers to types/inits/properties used outside the package
- Modify: `FreakLog` target Xcode group references — drop the moved files

- [ ] **Step 1: Write a failing test in the package that requires `SubstanceRepo` to load from package bundle**

```swift
// FreakLogCore/Tests/FreakLogCoreTests/SubstanceRepoTests.swift
import XCTest
@testable import FreakLogCore

final class SubstanceRepoTests: XCTestCase {
    func test_loadsKnownSubstance() {
        let mdma = SubstanceRepo.shared.getSubstance(name: "MDMA")
        XCTAssertNotNil(mdma)
        XCTAssertEqual(mdma?.name, "MDMA")
    }
}
```

- [ ] **Step 2: Run test, confirm failure**

```bash
cd FreakLogCore && swift test --filter SubstanceRepoTests
```
Expected: FAIL — `SubstanceRepo` undefined.

- [ ] **Step 3: Move files via git mv (preserves history) and update bundle reference**

```bash
cd /Users/pilz/Documents/FreakLog-iOS
mkdir -p FreakLogCore/Sources/FreakLogCore/Decoding FreakLogCore/Sources/FreakLogCore/Resources
git mv FreakLog/Decoding/{Substance,Roa,RoaDose,RoaDuration,RoaRange,DurationRange,Category,Interactions,SubstanceFile,SubstanceRepo,Tolerance}.swift FreakLogCore/Sources/FreakLogCore/Decoding/
git mv FreakLog/Assets/substances.json FreakLogCore/Sources/FreakLogCore/Resources/substances.json
```

- [ ] **Step 4: In `SubstanceRepo.swift`, swap `Bundle.main` for `Bundle.module`**

```swift
// before:
guard let url = Bundle.main.url(forResource: "substances", withExtension: "json") else { ... }
// after:
guard let url = Bundle.module.url(forResource: "substances", withExtension: "json") else {
    fatalError("substances.json missing from FreakLogCore resources")
}
```

- [ ] **Step 5: Add `public` to every external-facing API in moved files**

Use this checklist (apply to each file): `public struct Substance`, `public init(...)`, all stored properties used by app code → `public let`/`var`. Same for `Roa`, `RoaDose`, `RoaDuration`, `RoaRange`, `DurationRange`, `Category`, `Interactions`, `Tolerance`, `SubstanceRepo` (`public static let shared`, `public func getSubstance`, `public func getSubstances`).

- [ ] **Step 6: Re-run package tests**

```bash
cd FreakLogCore && swift test
```
Expected: PASS.

- [ ] **Step 7: Add `import FreakLogCore` everywhere the iOS app referenced these types**

```bash
cd /Users/pilz/Documents/FreakLog-iOS
grep -rl "SubstanceRepo\|: Substance\b\|Roa\b" FreakLog/ TimelineWidget/ \
  --include='*.swift' | while read f; do
    grep -q '^import FreakLogCore' "$f" || \
      sed -i '' '1a\
import FreakLogCore
' "$f"
  done
```

- [ ] **Step 8: Build iOS app, fix remaining access-control errors**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:" | head -20
```
Expected on first pass: zero errors. If errors: each one names a missing `public` — add it, rebuild.

- [ ] **Step 9: Run iOS test suite**

```bash
xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```
Expected: same pass count as baseline.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: move Decoding types and substances.json into FreakLogCore

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.4: Move shared logic & helpers (`SubstanceColor`, `InteractionChecker`, `ToleranceChartCalculator`, helper extensions)

**Files:**
- Move: `FreakLog/CoreDataHelpers/SubstanceColor.swift` → `FreakLogCore/Sources/FreakLogCore/Logic/SubstanceColor.swift`
- Identify and move: `InteractionChecker`, `ToleranceChartCalculator` (find via `grep -r "class InteractionChecker"` and `grep -r "class ToleranceChartCalculator"`)
- Move: pure-Swift extensions referenced by Core (e.g., `Date+Helpers.swift` if it exists) → `FreakLogCore/Sources/FreakLogCore/Helpers/`
- Move: `FreakLog/Constants.swift` items that are domain-shared → `FreakLogCore/Sources/FreakLogCore/Helpers/SharedConstants.swift`; iOS-only constants (URL schemes, FAB position) stay in app
- Move: `FreakLog/Global Functions.swift` — split: domain functions to package, UIApplication/UIKit functions stay in app

- [ ] **Step 1: Write tests for moved logic**

```swift
// FreakLogCore/Tests/FreakLogCoreTests/InteractionCheckerTests.swift
import XCTest
@testable import FreakLogCore

final class InteractionCheckerTests: XCTestCase {
    func test_dangerousInteractionDetected() {
        let result = InteractionChecker.getInteractionBetween(aName: "MDMA", bName: "MAOI")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.interactionType, .dangerous)
    }

    func test_unrelatedSubstancesReturnNil() {
        let result = InteractionChecker.getInteractionBetween(aName: "Caffeine", bName: "Vitamin C")
        XCTAssertNil(result)
    }
}
```

```swift
// FreakLogCore/Tests/FreakLogCoreTests/SubstanceColorTests.swift
import XCTest
@testable import FreakLogCore

final class SubstanceColorTests: XCTestCase {
    func test_swiftUIColorIsStable() {
        XCTAssertNotEqual(SubstanceColor.red.swiftUIColor.description, "")
    }
}
```

- [ ] **Step 2: Run tests, confirm failures**

```bash
cd FreakLogCore && swift test --filter InteractionCheckerTests
```

- [ ] **Step 3: Move files via git mv, public-ify**

```bash
git mv FreakLog/CoreDataHelpers/SubstanceColor.swift FreakLogCore/Sources/FreakLogCore/Logic/
# locate and move the others:
for f in $(grep -lE "class (InteractionChecker|ToleranceChartCalculator)" FreakLog -r --include='*.swift'); do
  git mv "$f" "FreakLogCore/Sources/FreakLogCore/Logic/$(basename "$f")"
done
```

Add `public` to types and key methods.

- [ ] **Step 4: Add `import FreakLogCore` where needed in app/widget files; fix build errors iteratively**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:" | head -20
```

- [ ] **Step 5: Package tests + iOS tests pass**

```bash
cd FreakLogCore && swift test
cd .. && xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move shared logic (SubstanceColor, InteractionChecker, ToleranceChartCalculator) into FreakLogCore

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.5: Move Core Data model + persistence into the package

**Files:**
- Move: `FreakLog/Main.xcdatamodeld` → `FreakLogCore/Sources/FreakLogCore/Model/Main.xcdatamodeld` (bundle resource)
- Move: `FreakLog/CoreDataHelpers/{CustomSubstance,CustomUnit,Experience,ExperienceLocation,Ingestion,ShulginRating,Spray,SubstanceCompanion,TimedNote,WebhookMessage,WebhookPreset}-CoreDataHelpers.swift` → `FreakLogCore/Sources/FreakLogCore/Model/`
- Move: `FreakLog/CoreDataHelpers/ExperienceLogic.swift` → `FreakLogCore/Sources/FreakLogCore/Logic/`
- Move: `FreakLog/Persistence.swift` → `FreakLogCore/Sources/FreakLogCore/Persistence/PersistenceController.swift`
- Refactor `PersistenceController.init` to accept config struct so iOS, watch, and widgets can pass different options:

```swift
public struct PersistenceConfig {
    public var inMemory: Bool = false
    public var cloudKitEnabled: Bool = false
    public var readOnly: Bool = false
    public var debugContainer: Bool = false  // determines which CloudKit container ID
    public init() {}
}
```

- [ ] **Step 1: Write failing test for in-memory persistence + CRUD**

```swift
// FreakLogCore/Tests/FreakLogCoreTests/PersistenceCRUDTests.swift
import XCTest
import CoreData
@testable import FreakLogCore

final class PersistenceCRUDTests: XCTestCase {
    func test_canCreateAndFetchExperience() throws {
        var cfg = PersistenceConfig(); cfg.inMemory = true
        let p = PersistenceController(config: cfg)
        p.loadPersistentStoresSync()
        let ctx = p.viewContext
        let exp = Experience(context: ctx)
        exp.creationDate = Date()
        exp.title = "Test"
        try ctx.save()

        let fetched = try ctx.fetch(Experience.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Test")
    }
}
```

- [ ] **Step 2: Run, confirm fail**

```bash
cd FreakLogCore && swift test --filter PersistenceCRUDTests
```

- [ ] **Step 3: Move files**

```bash
cd /Users/pilz/Documents/FreakLog-iOS
mkdir -p FreakLogCore/Sources/FreakLogCore/Model FreakLogCore/Sources/FreakLogCore/Persistence
git mv FreakLog/Main.xcdatamodeld FreakLogCore/Sources/FreakLogCore/Model/Main.xcdatamodeld
git mv FreakLog/CoreDataHelpers/*-CoreDataHelpers.swift FreakLogCore/Sources/FreakLogCore/Model/
git mv FreakLog/CoreDataHelpers/ExperienceLogic.swift FreakLogCore/Sources/FreakLogCore/Logic/
git mv FreakLog/Persistence.swift FreakLogCore/Sources/FreakLogCore/Persistence/PersistenceController.swift
```

- [ ] **Step 4: Refactor `PersistenceController` to use `PersistenceConfig` and `Bundle.module` for the model**

Key edits inside `PersistenceController.swift`:
```swift
public final class PersistenceController {
    public static let shared = PersistenceController(config: defaultProductionConfig())

    private static func defaultProductionConfig() -> PersistenceConfig {
        var cfg = PersistenceConfig()
        cfg.cloudKitEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        #if DEBUG
        cfg.debugContainer = true
        #endif
        return cfg
    }

    public let container: NSPersistentCloudKitContainer

    public init(config: PersistenceConfig) {
        guard let modelURL = Bundle.module.url(forResource: "Main", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Main Core Data model missing from FreakLogCore resources")
        }
        container = NSPersistentCloudKitContainer(name: "Main", managedObjectModel: model)
        // ...rest of existing logic, parameterised by `config` instead of inline #if APP_WIDGET / inMemory
    }

    public func loadPersistentStoresSync() {
        // synchronous variant for tests
    }

    public func loadData(_ app: Any?) { /* iOS-specific stays in app via callback */ }
}
```

Also add `public` to every method, property, and `static let` key currently consumed by app code.

- [ ] **Step 5: Add `public` to every NSManagedObject helper extension property used outside package**

Quick rule: every `var foo:` or `func foo` in a `*-CoreDataHelpers.swift` extension that is referenced outside the package needs `public`.

- [ ] **Step 6: Update iOS app to use new init signature**

In `FreakLog/AppDelegate.swift` (or wherever `PersistenceController.shared.loadData` is called) — no change if `.shared` still does the right thing.

In `FreakLog/Persistence.swift` callsites that referenced removed `#if APP_WIDGET`: ensure `LiveActivityExtension` instead constructs its own `PersistenceController(config:)` with `readOnly = true`.

- [ ] **Step 7: Build & test iOS**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:" | head -20
xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```
Expected: build clean, tests match baseline.

- [ ] **Step 8: Verify CloudKit schema is unchanged (defensive smoke test)**

```bash
# Manually launch the app in simulator under iCloud-enabled debug account once, observe logs:
xcrun simctl launch booted woof.freaklog
# Confirm no "model migration" logs and existing data still visible.
```

- [ ] **Step 9: Run package tests**

```bash
cd FreakLogCore && swift test
```

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: move Core Data model and PersistenceController into FreakLogCore

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.6: Move Timeline rendering (`TimelineModel`, drawables, `EffectTimeline`) into the package

**Files:**
- Move: `FreakLog/Timeline/{TimelineModel,AxisDrawable,GroupDrawable,RatingDrawable,TimeRangeDrawable,TimedNoteDrawable,WeightedLine,IngestionRange,EverythingForOneRating,EverythingForOneTimedNote}.swift` → `FreakLogCore/Sources/FreakLogCore/Timeline/`
- Move: `FreakLog/Timeline/EffectTimeline.swift` → `FreakLogCore/Sources/FreakLogCore/Timeline/EffectTimeline.swift`
- Move: `FreakLog/Timeline/Preparation/*` and `FreakLog/Timeline/Drawables/*` → `FreakLogCore/Sources/FreakLogCore/Timeline/`
- Audit `EffectTimeline.swift` for iOS-only APIs (`UIBezierPath`, `UIColor`, hover gestures); replace with cross-platform equivalents (`Path`, `Color`) or wrap with `#if os(iOS)`

- [ ] **Step 1: Write failing tests for `TimelineModel` initialisation**

```swift
// FreakLogCore/Tests/FreakLogCoreTests/TimelineModelTests.swift
import XCTest
@testable import FreakLogCore

final class TimelineModelTests: XCTestCase {
    func test_emptyInputProducesNonDrawableModel() {
        let m = TimelineModel(
            substanceGroups: [],
            everythingForEachRating: [],
            everythingForEachTimedNote: [],
            areRedosesDrawnIndividually: false,
            areSubstanceHeightsIndependent: false
        )
        XCTAssertFalse(m.isWorthDrawing)
    }
}
```

- [ ] **Step 2: Confirm fail**

- [ ] **Step 3: Move files**

```bash
mkdir -p FreakLogCore/Sources/FreakLogCore/Timeline
git mv FreakLog/Timeline/*.swift FreakLogCore/Sources/FreakLogCore/Timeline/
git mv FreakLog/Timeline/Preparation/*.swift FreakLogCore/Sources/FreakLogCore/Timeline/
git mv FreakLog/Timeline/Drawables/*.swift FreakLogCore/Sources/FreakLogCore/Timeline/
rmdir FreakLog/Timeline/Preparation FreakLog/Timeline/Drawables FreakLog/Timeline 2>/dev/null
```

- [ ] **Step 4: Audit `EffectTimeline.swift` for iOS-only APIs**

```bash
grep -nE "UIKit|UIColor|UIBezierPath|UIScreen|onHover|hoverEffect" FreakLogCore/Sources/FreakLogCore/Timeline/EffectTimeline.swift
```

For each hit, either substitute (`Color`, `Path`) or guard with `#if os(iOS)` and provide a watchOS branch using SwiftUI primitives.

- [ ] **Step 5: Public-ify timeline types**

`public struct TimelineModel`, `public struct *Drawable`, `public struct EverythingForOneRating`, `public struct EverythingForOneTimedNote`, `public struct EffectTimeline: View` and its `public init`.

- [ ] **Step 6: Build for iOS + tests**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:" | head -20
xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

- [ ] **Step 7: Verify package builds for both platforms**

```bash
cd FreakLogCore && swift build
xcodebuild -scheme FreakLogCore -destination 'generic/platform=watchOS' build
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: move TimelineModel and EffectTimeline into FreakLogCore (cross-platform)

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.7: Refactor `LiveActivityExtension` to consume the package

**Files:**
- Modify: `TimelineWidget/TimelineWidgetAttributes.swift`
- Modify: `TimelineWidget/TimelineWidgetLiveActivity.swift`
- Modify: `TimelineWidget/TimelineWidgetBundle.swift`

- [ ] **Step 1: Add `import FreakLogCore` at top of every TimelineWidget file**

- [ ] **Step 2: Remove file-membership references in pbxproj for files now living in the package** — Xcode UI: select each previously-added shared file in TimelineWidget target, untick "Target Membership" for `LiveActivityExtension` (the package import replaces them).

- [ ] **Step 3: Build the widget extension**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' -target LiveActivityExtension 2>&1 | grep -E "error:" | head -10
```

- [ ] **Step 4: Manual smoke test** — run app, start an experience, confirm Live Activity appears with correct timeline rendering.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: LiveActivityExtension consumes FreakLogCore

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 1.8: Phase 1 sign-off

- [ ] **Step 1: Full test pass + baseline diff**

```bash
xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tee docs/superpowers/baselines/phase1-after.txt | tail -10
diff docs/superpowers/baselines/phase1-baseline.txt docs/superpowers/baselines/phase1-after.txt | grep -E "^[<>].*Test (Suite|Case)" | head -20
```
Expected: no missing tests, no new failures.

- [ ] **Step 2: Tag phase end**

```bash
git tag phase-1-complete
git commit --allow-empty -m "chore: Phase 1 complete — FreakLogCore extraction done

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

# Phase 2 — Watch App v1: Read-only + Complications/Smart Stack

**Outcome:** A watchOS 10+ app named `FreakLog Watch App` that displays the active experience with timeline, lets the user browse past experiences and view detail, and exposes 4 complication families plus a Smart Stack widget. No write operations yet.

**Verification:** Watch app launches in simulator, syncs with iPhone via CloudKit, complications appear in the watch face gallery, Smart Stack widget shows in the Smart Stack preview.

## Task 2.1: Add the `FreakLog Watch App` target

**Files:**
- Create via Xcode: target `FreakLog Watch App`, bundle ID `woof.freaklog.watchkitapp`, watchOS 10.0
- Create: `FreakLog Watch App/FreakLogWatchApp.swift`
- Create: `FreakLog Watch App/Info.plist`
- Create: `FreakLog Watch App/FreakLog Watch App.entitlements` (matches iOS iCloud + App Group entitlements)
- Modify: `FreakLog.xcodeproj/project.pbxproj` (Xcode handles)

- [ ] **Step 1: Add the watch app target via Xcode UI**

Xcode: File → New → Target → watchOS → App → name `FreakLog Watch App`, bundle ID `woof.freaklog.watchkitapp`, language Swift, interface SwiftUI, embed in `FreakLog`. Confirm minimum deployment is watchOS 10.0.

- [ ] **Step 2: Link `FreakLogCore` to the new target**

Xcode: select `FreakLog Watch App` target → General → Frameworks, Libraries, and Embedded Content → `+` → add `FreakLogCore`.

- [ ] **Step 3: Add iCloud + App Group entitlements**

`FreakLog Watch App/FreakLog Watch App.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.woof.freaklog</string>
        <string>iCloud.woof.freaklog-debug</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array><string>CloudKit</string></array>
    <key>com.apple.security.application-groups</key>
    <array><string>group.woof.freaklog</string></array>
</dict></plist>
```

Same App Group must be added to the iOS app entitlements (modify `FreakLog/FreakLog.entitlements`).

- [ ] **Step 4: Replace generated `FreakLogWatchApp.swift` body**

```swift
import SwiftUI
import FreakLogCore

@main
struct FreakLogWatchApp: App {
    @StateObject private var auth = WatchAuthenticator()
    @Environment(\.scenePhase) private var phase

    init() {
        var cfg = PersistenceConfig()
        cfg.cloudKitEnabled = true
        #if DEBUG
        cfg.debugContainer = true
        #endif
        PersistenceController.bootShared(config: cfg)
    }

    var body: some Scene {
        WindowGroup {
            WatchAuthGate(auth: auth) {
                RootTabView()
                    .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
            }
        }
        .onChange(of: phase) { _, new in auth.scenePhaseChanged(new) }
    }
}
```

(Add `bootShared` helper to `PersistenceController` to allow re-init on first launch.)

- [ ] **Step 5: Build the watch target**

```bash
xcodebuild build -project FreakLog.xcodeproj -scheme "FreakLog Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED with placeholder views.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add FreakLog Watch App target with FreakLogCore wired up

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Task 2.2: `WatchAuthenticator` (passcode + wrist gate)

**Files:**
- Create: `FreakLog Watch App/Root/WatchAuthenticator.swift`
- Create: `FreakLog Watch App/Root/WatchAuthGate.swift`
- Test: `FreakLog Watch AppTests/WatchAuthenticatorTests.swift`

- [ ] **Step 1: Create the watch test target**

Xcode: File → New → Target → watchOS → Unit Testing Bundle → name `FreakLog Watch AppTests`. Link to `FreakLog Watch App`.

- [ ] **Step 2: Failing test**

```swift
import XCTest
@testable import FreakLog_Watch_App

final class WatchAuthenticatorTests: XCTestCase {
    func test_initiallyLockedWhenRequired() {
        let a = WatchAuthenticator(isRequired: true)
        XCTAssertEqual(a.state, .locked)
    }
    func test_initiallyUnlockedWhenNotRequired() {
        let a = WatchAuthenticator(isRequired: false)
        XCTAssertEqual(a.state, .unlocked)
    }
}
```

- [ ] **Step 3: Implement `WatchAuthenticator`**

```swift
import SwiftUI
import LocalAuthentication

@MainActor
public final class WatchAuthenticator: ObservableObject {
    public enum State { case locked, unlocking, unlocked }
    @Published public private(set) var state: State

    private let isRequired: Bool

    public init(isRequired: Bool = UserDefaults.standard.bool(forKey: "isWatchAuthRequired")) {
        self.isRequired = isRequired
        self.state = isRequired ? .locked : .unlocked
    }

    public func unlock() async {
        guard state == .locked else { return }
        state = .unlocking
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            state = .unlocked
            return
        }
        do {
            try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock FreakLog")
            state = .unlocked
        } catch {
            state = .locked
        }
    }

    public func scenePhaseChanged(_ new: ScenePhase) {
        if new == .background, isRequired { state = .locked }
    }
}
```

- [ ] **Step 4: `WatchAuthGate.swift` wraps content with lock screen**

```swift
import SwiftUI

struct WatchAuthGate<Content: View>: View {
    @ObservedObject var auth: WatchAuthenticator
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch auth.state {
        case .unlocked: content()
        case .locked, .unlocking:
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.title2)
                Button("Unlock") { Task { await auth.unlock() } }
            }
            .task { await auth.unlock() }
        }
    }
}
```

- [ ] **Step 5: Tests pass + commit**

```bash
xcodebuild test -project FreakLog.xcodeproj -scheme "FreakLog Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'
git add -A && git commit -m "feat(watch): add WatchAuthenticator with biometric unlock"
```

## Task 2.3: `RootTabView` + 4-tab shell

**Files:**
- Create: `FreakLog Watch App/Root/RootTabView.swift`
- Placeholder: `FreakLog Watch App/Active/ActiveExperienceView.swift`
- Placeholder: `FreakLog Watch App/Journal/JournalListView.swift`
- Placeholder: `FreakLog Watch App/Substances/SubstanceListView.swift`
- Placeholder: `FreakLog Watch App/Settings/WatchSettingsView.swift`

- [ ] **Step 1: Implement `RootTabView`**

```swift
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ActiveExperienceView()
                .tabItem { Label("Active", systemImage: "waveform.path.ecg") }
            JournalListView()
                .tabItem { Label("Journal", systemImage: "book.closed") }
            SubstanceListView()
                .tabItem { Label("Subs", systemImage: "pills") }
            WatchSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tabViewStyle(.verticalPage)  // watchOS 10 paged style
    }
}
```

- [ ] **Step 2: Stub each placeholder with `Text("…")`**

- [ ] **Step 3: Build and run on watch sim, confirm tabs swipeable**

- [ ] **Step 4: Commit**

## Task 2.4: `ActiveExperienceView` + ViewModel (read-only timeline)

**Files:**
- Create: `FreakLog Watch App/Active/ActiveExperienceViewModel.swift`
- Create: `FreakLog Watch App/Active/ActiveExperienceView.swift`
- Create: `FreakLog Watch App/Active/EmptyActiveView.swift`
- Test: `FreakLog Watch AppTests/ActiveExperienceViewModelTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
import CoreData
@testable import FreakLog_Watch_App
import FreakLogCore

final class ActiveExperienceViewModelTests: XCTestCase {
    var ctx: NSManagedObjectContext!

    override func setUp() {
        var cfg = PersistenceConfig(); cfg.inMemory = true
        let p = PersistenceController(config: cfg)
        p.loadPersistentStoresSync()
        ctx = p.viewContext
    }

    func test_noExperiences_yieldsNilActive() {
        let vm = ActiveExperienceViewModel(context: ctx)
        XCTAssertNil(vm.activeExperience)
    }

    func test_recentExperience_isActive() throws {
        let exp = Experience(context: ctx)
        exp.creationDate = Date()
        exp.sortDate = Date()
        let ing = Ingestion(context: ctx)
        ing.time = Date().addingTimeInterval(-3600)
        ing.experience = exp
        ing.substanceName = "MDMA"
        try ctx.save()

        let vm = ActiveExperienceViewModel(context: ctx)
        vm.refresh()
        XCTAssertEqual(vm.activeExperience?.objectID, exp.objectID)
    }
}
```

- [ ] **Step 2: Implement ViewModel**

```swift
import Foundation
import CoreData
import Combine
import FreakLogCore

@MainActor
final class ActiveExperienceViewModel: ObservableObject {
    @Published private(set) var activeExperience: Experience?
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(context: NSManagedObjectContext) {
        self.context = context
        refresh()
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)
            .merge(with: NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        let req = Experience.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        let recent = (try? context.fetch(req)) ?? []
        activeExperience = recent.first { $0.isCurrent }
    }
}
```

- [ ] **Step 3: Implement `ActiveExperienceView`**

```swift
import SwiftUI
import FreakLogCore

struct ActiveExperienceView: View {
    @Environment(\.managedObjectContext) private var ctx
    @StateObject private var vm: ActiveExperienceViewModel

    init() {
        _vm = StateObject(wrappedValue: ActiveExperienceViewModel(
            context: PersistenceController.shared.viewContext))
    }

    var body: some View {
        NavigationStack {
            if let exp = vm.activeExperience {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exp.titleUnwrapped).font(.headline)
                        if let start = exp.ingestionsSorted.first?.time {
                            Text(start, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        EffectTimeline(
                            timelineModel: exp.getMyTimeLineModel(
                                hiddenIngestions: [], hiddenRatings: [],
                                areRedosesDrawnIndividually: false,
                                areSubstanceHeightsIndependent: false),
                            height: 100,
                            timeDisplayStyle: .regular,
                            isShowingCurrentTime: true,
                            spaceToLabels: 4
                        )
                        ForEach(exp.ingestionsSorted, id: \.objectID) { ing in
                            IngestionRow(ingestion: ing)
                        }
                    }.padding(.horizontal, 6)
                }
                .navigationTitle("Active")
            } else {
                EmptyActiveView()
            }
        }
    }
}

struct IngestionRow: View {
    let ingestion: Ingestion
    var body: some View {
        HStack {
            Circle().fill(ingestion.substanceColor.swiftUIColor).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(ingestion.substanceNameUnwrapped).font(.caption)
                if let dose = ingestion.doseUnwrapped {
                    Text("\(dose, specifier: "%.1f") \(ingestion.units ?? "")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 4: `EmptyActiveView`**

```swift
import SwiftUI
struct EmptyActiveView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz").font(.title2)
            Text("No active experience").font(.caption)
            Text("Open FreakLog on iPhone to start one.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding()
    }
}
```

- [ ] **Step 5: Tests pass; manual smoke test on sim with seeded data**

- [ ] **Step 6: Commit**

## Task 2.5: `JournalListView` + paginated experience list

**Files:**
- Create: `FreakLog Watch App/Journal/JournalListView.swift`
- Test: `FreakLog Watch AppTests/JournalListViewModelTests.swift`

- [ ] **Step 1: Failing test for paginated viewmodel**

```swift
final class JournalListViewModelTests: XCTestCase {
    func test_pageSize30() throws {
        let ctx = makeInMemoryContext()
        for i in 0..<45 {
            let e = Experience(context: ctx); e.creationDate = Date().addingTimeInterval(-Double(i)*1000); e.sortDate = e.creationDate
        }
        try ctx.save()
        let vm = JournalListViewModel(context: ctx, pageSize: 30)
        vm.loadFirstPage()
        XCTAssertEqual(vm.items.count, 30)
        vm.loadMore()
        XCTAssertEqual(vm.items.count, 45)
    }
}
```

- [ ] **Step 2: Implement viewmodel + view**

(Standard NSFetchRequest with `fetchLimit` + `fetchOffset`, append-on-scroll using `.onAppear` of last visible row.)

- [ ] **Step 3: Tests + manual smoke + commit**

## Task 2.6: `ExperienceDetailView` + `IngestionDetailView`

**Files:**
- Create: `FreakLog Watch App/Journal/ExperienceDetailView.swift`
- Create: `FreakLog Watch App/Journal/IngestionDetailView.swift`

- [ ] **Step 1: Tests** — minimal: `init` smoke tests confirming view bodies render without crashing in `XCTHostApplicationLaunchPolicy`

- [ ] **Step 2: Implement** — show timeline, ingestion list (tappable → IngestionDetail), text notes, ratings (read-only)

- [ ] **Step 3: Manual smoke test + commit**

## Task 2.7: `WatchSettingsView` (read-only sync status, biometric toggle)

**Files:**
- Create: `FreakLog Watch App/Settings/WatchSettingsView.swift`

- [ ] **Step 1: Implement** — sections: iCloud (status from `PersistenceController`), Security (toggle for `isWatchAuthRequired` UserDefault), Display (time-display style picker mirroring iOS)

- [ ] **Step 2: Manual smoke test + commit**

## Task 2.8: Watch widget extension target

**Files:**
- Create via Xcode: target `FreakLog Watch Widgets` (watchOS Widget Extension), bundle `woof.freaklog.watchkitapp.widgets`
- Create: `FreakLog Watch Widgets/FreakLogWatchWidgetsBundle.swift`
- Create: `FreakLog Watch Widgets/Provider/ActiveExperienceProvider.swift`
- Create: `FreakLog Watch Widgets/ActiveExperienceWidget.swift`
- Create: `FreakLog Watch Widgets/Complications/PhaseComplication.swift`
- Create: `FreakLog Watch Widgets/Complications/MiniTimelineComplication.swift`

- [ ] **Step 1: Add Widget Extension target via Xcode UI** — choose "Live Activity" template? **No** — choose plain Widget. Embed in `FreakLog Watch App`.

- [ ] **Step 2: Add same iCloud/App Group entitlements** as the watch app (read-only Core Data store)

- [ ] **Step 3: Link `FreakLogCore`**

- [ ] **Step 4: Implement `ActiveExperienceProvider`** with timeline entries every 5 minutes for the next 12 hours, generated from current active experience snapshot. Use `PersistenceController(config: …readOnly=true…)`.

```swift
import WidgetKit
import FreakLogCore

struct ActiveExperienceProvider: TimelineProvider {
    typealias Entry = ActiveExperienceEntry

    func placeholder(in: Context) -> ActiveExperienceEntry { .placeholder }
    func getSnapshot(in: Context, completion: @escaping (Entry) -> Void) {
        completion(currentEntry() ?? .placeholder)
    }
    func getTimeline(in: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let entries: [Entry] = stride(from: 0, to: 12*60*60, by: 5*60).compactMap { offset in
            currentEntry(at: now.addingTimeInterval(TimeInterval(offset)))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60*60))))
    }

    private func currentEntry(at date: Date = .now) -> ActiveExperienceEntry? {
        guard let exp = PersistenceController.shared.getLatestActiveExperience() else { return nil }
        return ActiveExperienceEntry(date: date, experienceSnapshot: .init(from: exp))
    }
}

struct ActiveExperienceEntry: TimelineEntry {
    let date: Date
    let experienceSnapshot: ExperienceSnapshot
    static let placeholder = ActiveExperienceEntry(date: .now, experienceSnapshot: .placeholder)
}
```

(`ExperienceSnapshot` = a `Sendable` struct of just timeline-render inputs, so widget process doesn't access main-actor Core Data on render.)

- [ ] **Step 5: `ActiveExperienceWidget`** (Smart Stack rectangular + Lock Screen)

```swift
struct ActiveExperienceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ActiveExperience", provider: ActiveExperienceProvider()) { entry in
            ActiveExperienceWidgetView(entry: entry)
        }
        .configurationDisplayName("Active Experience")
        .description("Shows your current FreakLog timeline.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct ActiveExperienceWidgetView: View {
    let entry: ActiveExperienceEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .accessoryRectangular: MiniTimelineView(snapshot: entry.experienceSnapshot)
        case .accessoryCircular:    PhaseRing(snapshot: entry.experienceSnapshot)
        case .accessoryCorner:      PhaseCorner(snapshot: entry.experienceSnapshot)
        case .accessoryInline:      Text(entry.experienceSnapshot.inlineSummary)
        default:                    Text(entry.experienceSnapshot.inlineSummary)
        }
    }
}
```

- [ ] **Step 6: `PhaseComplication` and `MiniTimelineComplication`** as separate `Widget` types with single `supportedFamilies` each (allows distinct entries in the watch face gallery).

- [ ] **Step 7: Bundle**

```swift
@main
struct FreakLogWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ActiveExperienceWidget()
        PhaseComplication()
        MiniTimelineComplication()
    }
}
```

- [ ] **Step 8: Build, install on sim, add complication to watch face manually, verify it renders**

- [ ] **Step 9: Trigger refresh from app on every save**

In `WatchSettingsView` and after Phase 3 mutations: call `WidgetCenter.shared.reloadAllTimelines()`.

- [ ] **Step 10: Commit + tag phase 2**

```bash
git tag phase-2-complete
```

---

# Phase 3 — Watch v2: Write Operations

**Outcome:** Users can add ingestions, redose, log timed notes, and start new experiences from the watch. Changes sync back to iPhone via CloudKit.

## Task 3.1: Substance picker (recent + search)

**Files:**
- Create: `FreakLog Watch App/AddIngestion/SubstancePickerView.swift`
- Create: `FreakLog Watch App/AddIngestion/SubstancePickerViewModel.swift`
- Test: `FreakLog Watch AppTests/SubstancePickerViewModelTests.swift`

- [ ] **Step 1: Failing tests** — `recentSubstances` returns most-frequent last-30-day substances; `search("md")` returns MDMA before Methylone alphabetically; empty query returns recent.

- [ ] **Step 2: Implement viewmodel querying Core Data + `SubstanceRepo`**

- [ ] **Step 3: Implement `SubstancePickerView`** — sectioned `List` (Recent / All / Custom), search field via `.searchable`

- [ ] **Step 4: Tests + manual + commit**

## Task 3.2: Route picker

**Files:**
- Create: `FreakLog Watch App/AddIngestion/RoutePickerView.swift`

- [ ] **Step 1: Failing test** — picker shows only RoAs available for the chosen `Substance` with valid `RoaDuration`

- [ ] **Step 2: Implement** — `List` of `AdministrationRoute` cases filtered against `substance.roas`

- [ ] **Step 3: Tests + commit**

## Task 3.3: Dose dial with digital crown

**Files:**
- Create: `FreakLog Watch App/AddIngestion/DoseDialView.swift`
- Create: `FreakLog Watch App/AddIngestion/DoseDialViewModel.swift`
- Test: `FreakLog Watch AppTests/DoseDialViewModelTests.swift`

- [ ] **Step 1: Failing tests** — dial increment for MDMA-oral defaults to 5 mg between common-low (75) and strong-high (240); estimate toggle adds ±SD field

- [ ] **Step 2: Implement** — `Stepper` is too coarse on watch; use `digitalCrownRotation($amount, from: lowerBound, through: upperBound, by: step, sensitivity: .high, isContinuous: false)`

- [ ] **Step 3: Visual: vertical bar with common/light/strong markers from `RoaDose`**

- [ ] **Step 4: Tests + commit**

## Task 3.4: Time picker

**Files:**
- Create: `FreakLog Watch App/AddIngestion/TimePickerView.swift`

- [ ] **Step 1: Implement** — two presets (Now, 15 min ago, 30 min ago, 1 h ago) + a fallback `DatePicker`

- [ ] **Step 2: Tests for default = "Now" + commit**

## Task 3.5: `AddIngestionFlow` ties it together

**Files:**
- Create: `FreakLog Watch App/AddIngestion/AddIngestionFlow.swift`
- Create: `FreakLog Watch App/AddIngestion/AddIngestionState.swift` (the @Observable state passed between steps)
- Test: `FreakLog Watch AppTests/AddIngestionFlowTests.swift`

- [ ] **Step 1: Failing test** — completing all 4 steps creates an `Ingestion` with the right values; if no recent active experience, also creates a new `Experience`

- [ ] **Step 2: Implement** — `NavigationStack` with `path: [AddIngestionStep]`; final step calls `ExperienceLogic.createIngestion(...)` from FreakLogCore

- [ ] **Step 3: After save, `WidgetCenter.shared.reloadAllTimelines()` and pop to root**

- [ ] **Step 4: Manual smoke: add ingestion on watch sim, observe iPhone receiving it via CloudKit**

- [ ] **Step 5: Commit**

## Task 3.6: `RedoseSheet` from `ActiveExperienceView`

**Files:**
- Create: `FreakLog Watch App/AddIngestion/RedoseSheet.swift`
- Modify: `FreakLog Watch App/Active/ActiveExperienceView.swift` — add "+" toolbar button per substance row

- [ ] **Step 1: Test** — tapping redose pre-fills substance + route from previous ingestion of that substance

- [ ] **Step 2: Implement single-screen sheet (substance/route fixed, dose dial + time)**

- [ ] **Step 3: Commit**

## Task 3.7: `AddTimedNoteView`

**Files:**
- Create: `FreakLog Watch App/TimedNote/AddTimedNoteView.swift`

- [ ] **Step 1: Test** — saving creates `TimedNote` with `isPartOfTimeline = true` by default

- [ ] **Step 2: Implement** — text field (dictation), color picker, time picker, save

- [ ] **Step 3: Commit + tag phase 3**

```bash
git tag phase-3-complete
```

---

# Phase 4 — Watch v3: Safer-Use Browser, Custom Units, Polish

**Outcome:** Substance info accessible offline on watch (dosage, duration, tolerance, interactions); custom units displayed correctly in dose dial; settings refined.

## Task 4.1: `SubstanceListView` + categorisation

**Files:**
- Create: `FreakLog Watch App/Substances/SubstanceListView.swift`

- [ ] **Step 1: Test** — alphabetical, grouped by `Category`

- [ ] **Step 2: Implement using `SubstanceRepo.shared.getAllSubstances()`** — gated by eye-open flag (UserDefault from iOS)

- [ ] **Step 3: Commit**

## Task 4.2: `SubstanceInfoView` (dosage + duration + tolerance)

**Files:**
- Create: `FreakLog Watch App/Substances/SubstanceInfoView.swift`
- Create: `FreakLog Watch App/Substances/RoaInfoSection.swift`

- [ ] **Step 1: Test** — for a substance with no Roa, view shows "No data"

- [ ] **Step 2: Implement** — sections per RoA: dose ranges (`light/common/strong/heavy`), duration (onset/come-up/peak/offset/total)

- [ ] **Step 3: Commit**

## Task 4.3: `InteractionsView`

**Files:**
- Create: `FreakLog Watch App/Substances/InteractionsView.swift`

- [ ] **Step 1: Test** — color-codes by `InteractionType.dangerCount`

- [ ] **Step 2: Implement using `InteractionChecker`**

- [ ] **Step 3: Commit**

## Task 4.4: Custom-unit support in `DoseDialView`

**Files:**
- Modify: `FreakLog Watch App/AddIngestion/DoseDialView.swift`
- Modify: `FreakLog Watch App/AddIngestion/DoseDialViewModel.swift`

- [ ] **Step 1: Test** — selecting a `CustomUnit` (e.g. "0.5 mg per drop") shows `n drops` on dial, computes `pureSubstanceDose` correctly

- [ ] **Step 2: Implement** — read `CustomUnit` entities for the chosen substance; if any, prepend "Use custom unit" section; pass through to `Ingestion.customUnitDose` on save

- [ ] **Step 3: Commit**

## Task 4.5: Polish pass

- [ ] **Step 1: Haptics** — add `WKInterfaceDevice.current().play(.success)` after saves
- [ ] **Step 2: Crown haptic feedback on dose dial** (`digitalCrownAccessory(.visibility(.visible))`)
- [ ] **Step 3: VoiceOver labels** on all icons and dial controls (`.accessibilityLabel`, `.accessibilityValue`)
- [ ] **Step 4: Localization sweep** — all visible strings via `NSLocalizedString`/`LocalizedStringKey`, copied into `Localizable.strings` in the watch app bundle
- [ ] **Step 5: Performance** — verify Smart Stack widget doesn't hit Core Data on every entry render (snapshots are precomputed in provider)

- [ ] **Step 6: Commit + tag phase 4**

```bash
git tag phase-4-complete
```

## Task 4.6: Final verification & docs

- [ ] **Step 1: Full multi-target test pass**

```bash
xcodebuild test -project FreakLog.xcodeproj -scheme FreakLog -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -3
xcodebuild test -project FreakLog.xcodeproj -scheme "FreakLog Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' 2>&1 | tail -3
cd FreakLogCore && swift test 2>&1 | tail -3
```

- [ ] **Step 2: Update `README.md`** — add "Watch app" section under Features

- [ ] **Step 3: Final commit + tag**

```bash
git tag watch-app-v1.0
git commit --allow-empty -m "chore: FreakLog Watch App v1.0 complete

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Self-Review Notes

**Spec coverage:** Phases 1–4 cover all four scope items confirmed in brainstorm (read, log, browse, harm-reduction info). Complications and Smart Stack widget covered in 2.8. CloudKit sync covered structurally in 1.5 + 2.1 entitlements. Authentication covered in 2.2.

**Placeholder check:** Each task lists exact file paths, exact build/test commands, and code blocks for non-trivial logic. Where steps say "implement" without expanding into 5-line slices (e.g. Phase 4 polish), the file is small and well-bounded; an executing engineer reads the surrounding code to fill it in.

**Type consistency:** `PersistenceController(config: PersistenceConfig)`, `getLatestActiveExperience()`, `Experience.isCurrent`, `ExperienceLogic.createIngestion` — referenced consistently across phases. `ExperienceSnapshot` is introduced in Task 2.8 and referenced only there.

**Known manual gates (require human/Xcode UI):** target creation (1.2-step-6, 2.1, 2.8), signing/cap setup, Apple Dev portal CloudKit container provisioning. Documented at top.
