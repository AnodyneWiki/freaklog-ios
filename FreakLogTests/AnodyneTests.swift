@testable import FreakLog
import XCTest

// Parses trimmed copies of real AnodyneWiki API responses
final class AnodyneTests: XCTestCase {
    private func fixture(_ key: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Anodyne", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(json[key] as? [String: Any])
    }

    func testReadsDoseTiersPerRoute() throws {
        let mdma = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("mdma")))
        XCTAssertEqual(mdma.title, "3,4-Methylenedioxymethamphetamine")
        XCTAssertEqual(mdma.commonName, "MDMA")
        let oral = try XCTUnwrap(mdma.dosing.first { $0.route == .oral })
        XCTAssertEqual(oral.light?.upper, 74.6)
        XCTAssertEqual(oral.common?.lower, 74.6)
        XCTAssertEqual(oral.common?.upper, 100)
        XCTAssertEqual(oral.extreme?.lower, 200)
        XCTAssertEqual(oral.unit, "mg")
        XCTAssertEqual(oral.totalEntries, 61)
        XCTAssertEqual(mdma.dosing.first { $0.method == "Intrarectal" }?.route, .rectal)
        XCTAssertEqual(mdma.durationOfAction, "3 – 6 hours")
        XCTAssertFalse(mdma.erowidReports.isEmpty)
        XCTAssertEqual(mdma.redditReports.count, 2)
        XCTAssertFalse(mdma.reagents.isEmpty)
    }

    func testDoseValuesStartAtEachTier() throws {
        let mdma = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("mdma")))
        let values = try XCTUnwrap(mdma.dosing.first { $0.route == .oral }).doseValues(for: .oral)
        XCTAssertNil(values.lightDose)
        XCTAssertEqual(values.commonDose, 74.6)
        XCTAssertEqual(values.strongDose, 100)
        XCTAssertEqual(values.heavyDose, 120)
        XCTAssertEqual(values.doseUnits, "mg")
        // Shown in PsychonautWiki's form, without a threshold
        let roaDose = try XCTUnwrap(mdma.dosing.first { $0.route == .oral }?.roaDose)
        XCTAssertNil(roaDose.lightMin)
        XCTAssertEqual(roaDose.commonMin, 74.6)
        XCTAssertEqual(roaDose.strongMin, 100)
        XCTAssertEqual(roaDose.heavyMin, 120)
        XCTAssertEqual(roaDose.units, "mg")
    }

    func testCleansHtmlAndReadsVaryingFields() throws {
        let amphetamine = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("amphetamine")))
        XCTAssertEqual(amphetamine.classes, ["Stimulant"])
        XCTAssertEqual(amphetamine.abbreviations, ["Speed"])
        XCTAssertEqual(
            amphetamine.durationOfAction,
            "Immediate release dosing: 3 – 6 hours Extended release dosing: 8 – 12 hours"
        )
        XCTAssertTrue(amphetamine.effectGroups.contains { $0.name == "Physical Effects" && $0.effects.contains("Stimulation") })
    }

    func testRemovesWikiMarkup() throws {
        let json: [String: Any] = [
            "Title": "Methylhexanamine",
            "Aliases": ["1,3-DMAA", "Benzeneethanamine, 4-fluoro-2,5-dimethoxy-"],
            "Scheduling": [
                [
                    "gov": "United States",
                    "schedule": "Unapproved drug; use is unlawful.{-{Efn|The N.D.A was withdrawn in 1983.|group=note}-} substance",
                ],
                ["gov": "US", "schedule": "List of Schedule II controlled substances (U.S.)|Schedule II substance"],
            ],
        ]
        let substance = try XCTUnwrap(AnodyneSubstance(apiJSON: json))
        XCTAssertEqual(substance.scheduling.map(\.schedule), ["Unapproved drug; use is unlawful.", "Schedule II substance"])
        XCTAssertEqual(substance.aliases, ["1,3-DMAA"])
    }

    func testReadsUserNotes() throws {
        let notes = AnodyneUserNote.notes(fromUserJSON: try fixture("userNinerik"))
        XCTAssertEqual(notes.map(\.substanceName), ["Caffeine", "Amphetamine"])
        let caffeine = try XCTUnwrap(notes.first)
        XCTAssertEqual(caffeine.user, "ninerik")
        XCTAssertEqual(caffeine.routes.first?.name, "Oral")
        XCTAssertEqual(caffeine.routes.first?.dosage, "35–680 mg")
        XCTAssertEqual(caffeine.routesSummary, "Oral 35–680 mg")
        XCTAssertEqual(caffeine.effects.first, "light stimulation")
        XCTAssertTrue(caffeine.effects.contains("increased heart rate"))
        XCTAssertTrue(caffeine.effects.contains("addiction (since the start of 2026)"))
        XCTAssertTrue(caffeine.indications.contains("headache from Caffeine withdrawals"))
        XCTAssertEqual(caffeine.notes, ["Awful awful awful stimulant"])
        XCTAssertEqual(caffeine.userPageURL.absoluteString, "https://anodyne.wiki/user/ninerik")

        let mdma = try XCTUnwrap(AnodyneUserNote.notes(fromUserJSON: try fixture("userEmily")).first)
        XCTAssertEqual(mdma.routesSummary, "Oral 40–91 mg, Insufflated 22 mg")
        XCTAssertTrue(mdma.hasDetails)
    }

    func testRendersUserMarkup() {
        XCTAssertEqual("{sev 'strong'} {xeff 'appetite suppression'}".anodyneUserMarkupCleaned, "strong appetite suppression")
        XCTAssertEqual("{sub '2C-B'} and {class 'stimulant' 'stimulants'}".anodyneUserMarkupCleaned, "2C-B and stimulants")
        XCTAssertEqual("{p}Hello{Ep}{p}*there*{gt}{lt}{Ep}".anodyneUserMarkupCleaned, "Hello there><")
    }

    @MainActor
    func testReadsStructureAndFormula() throws {
        let substance = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("methylhexanamine")))
        XCTAssertEqual(substance.formula, "C₇H₁₇N")
        XCTAssertEqual(substance.molarMass, "115.22 g/mol")
        let drawing = try XCTUnwrap(MoleculeDrawing.parse(try XCTUnwrap(substance.structureSVG)))
        XCTAssertEqual(drawing.viewBox, CGRect(x: 0, y: 0, width: 76.411, height: 26.88))
        // Bonds in the text color, the nitrogen label in its element color; the white background is left out
        XCTAssertTrue(drawing.shapes.contains { $0.stroke == .foreground })
        XCTAssertTrue(drawing.shapes.contains { $0.fill == .rgb(48.0 / 255, 80.0 / 255, 248.0 / 255) })
        XCTAssertFalse(drawing.shapes.contains { $0.path.boundingRect.width > 70 && $0.stroke == nil })
    }

    // Progesterone's structure is base64 encoded and draws its bonds as <line> elements
    @MainActor
    func testReadsBase64StructuresWithLines() throws {
        let substance = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("progesterone")))
        let drawing = try XCTUnwrap(MoleculeDrawing.parse(try XCTUnwrap(substance.structureSVG)))
        XCTAssertEqual(drawing.viewBox, CGRect(x: 0, y: 0, width: 125.909, height: 74.123))
        // 42 bond lines, 9 wedge and label paths; the white background rectangle is left out
        XCTAssertEqual(drawing.shapes.count, 51)
        XCTAssertTrue(drawing.shapes.contains { $0.stroke == .rgb(1, 13.0 / 255, 13.0 / 255) })
    }

    func testParsesRunTogetherPathNumbers() throws {
        let path = try XCTUnwrap(SVGPath.parse("m1.106 10.672.005 15.248M14.305 3.052l13.198-7.62h2v-1z"))
        let bounds = path.boundingRect
        XCTAssertEqual(bounds.minX, 1.106, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 25.92, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 29.503, accuracy: 0.001)
    }

    func testReadsTimings() {
        XCTAssertEqual(AnodyneTiming.range(in: "3 – 6 hours"), DurationRange(min: 3, max: 6, units: .hours))
        XCTAssertEqual(
            AnodyneTiming.range(in: "Immediate release dosing: 3 – 6 hours Extended release dosing: 8 – 12 hours"),
            DurationRange(min: 3, max: 6, units: .hours)
        )
        XCTAssertEqual(AnodyneTiming.range(in: "~ 7-8 h"), DurationRange(min: 7, max: 8, units: .hours))
        XCTAssertEqual(AnodyneTiming.range(in: "~2.5hours"), DurationRange(min: 2.5, max: 2.5, units: .hours))
        XCTAssertEqual(AnodyneTiming.range(in: "10-15 seconds"), DurationRange(min: 10, max: 15, units: .seconds))
        XCTAssertEqual(AnodyneTiming.range(in: "~20min"), DurationRange(min: 20, max: 20, units: .minutes))
        XCTAssertNil(AnodyneTiming.range(in: "varies"))
    }

    func testCombinesUsersTimingsPerRoute() throws {
        let routes = [
            AnodyneUserNote.Route(name: "Oral", dosage: nil, onset: "20 min", comeup: "1.5-2 h", duration: "~ 7-8 h"),
            AnodyneUserNote.Route(name: "Oral", dosage: nil, onset: "30 minutes", comeup: "~1.5 hours", duration: "~7 hours"),
        ]
        let duration = try XCTUnwrap(AnodyneTiming.combinedDuration(routes))
        XCTAssertEqual(duration.onset, DurationRange(min: 20, max: 30, units: .minutes))
        XCTAssertEqual(duration.comeup, DurationRange(min: 90, max: 120, units: .minutes))
        XCTAssertEqual(duration.total, DurationRange(min: 7, max: 8, units: .hours))
        XCTAssertNil(duration.peak)
    }

    func testFallbackStoreFindsSubstancesByTheirAppName() throws {
        let instance = AnodyneSubstance.defaultBaseURL
        let store = AnodyneFallbackStore(cacheRoot: temporaryCacheRoot(), configuredInstance: { instance })
        let mdma = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("mdma")))
        store.record(mdma, lookedUpAs: "MDMA", from: instance)
        // The duration of action applies to every route
        XCTAssertEqual(store.duration(for: "MDMA", route: .insufflated)?.total, DurationRange(min: 3, max: 6, units: .hours))
        store.record(AnodyneUserNote.notes(fromUserJSON: try fixture("userEmily")), from: instance)
        XCTAssertNotNil(store.duration(for: "mdma", route: .oral))
        XCTAssertNil(store.duration(for: "LSD", route: .oral))
        // Doses come from the dose tiers per route
        XCTAssertEqual(store.dose(for: "MDMA", route: .oral)?.commonMin, 74.6)
        XCTAssertNil(store.dose(for: "MDMA", route: .intravenous))
        XCTAssertEqual(store.routesWithData(for: "MDMA"), [.oral, .insufflated, .rectal])
    }

    func testFallbackStoreMergesTimingsNotedUnderAnyAlias() throws {
        let instance = AnodyneSubstance.defaultBaseURL
        let store = AnodyneFallbackStore(cacheRoot: temporaryCacheRoot(), configuredInstance: { instance })
        let mdma = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("mdma")))
        XCTAssertEqual(mdma.title, "3,4-Methylenedioxymethamphetamine")
        // One user names it by its abbreviation, the other by its title; recorded before the substance is known
        store.record([
            AnodyneUserNote(
                user: "A",
                substanceName: "MDMA",
                routes: [AnodyneUserNote.Route(name: "Oral", dosage: nil, onset: "20 min", comeup: nil, duration: nil)]
            ),
            AnodyneUserNote(
                user: "B",
                substanceName: mdma.title,
                routes: [AnodyneUserNote.Route(name: "Oral", dosage: nil, onset: "40 min", comeup: nil, duration: nil)]
            ),
        ], from: instance)
        store.record(mdma, lookedUpAs: "MDMA", from: instance)
        XCTAssertEqual(store.duration(for: "MDMA", route: .oral)?.onset, DurationRange(min: 20, max: 40, units: .minutes))
        XCTAssertEqual(store.duration(for: mdma.title, route: .oral)?.onset, DurationRange(min: 20, max: 40, units: .minutes))
        XCTAssertEqual(store.routesWithTimings(for: "MDMA"), [.oral])
    }

    func testFailedUserNotesRefreshPreservesCachedNotesAndTimings() async throws {
        let instance = AnodyneSubstance.defaultBaseURL
        let root = temporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = AnodyneCacheFiles(root: root, instance: instance)
        let previous = AnodyneUserNote(
            user: "A",
            substanceName: "Example",
            routes: [.init(name: "Oral", dosage: nil, onset: "20 min", comeup: nil, duration: nil)]
        )
        let notes = try JSONSerialization.jsonObject(with: JSONEncoder().encode([previous]))
        let cached = try JSONSerialization.data(withJSONObject: ["date": 0, "notes": notes])
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try cached.write(to: files.userNotes)

        let fallback = AnodyneFallbackStore(cacheRoot: root, configuredInstance: { instance })
        let onset = DurationRange(min: 20, max: 20, units: .minutes)
        XCTAssertEqual(fallback.duration(for: "Example", route: .oral)?.onset, onset)

        let malformedIndex = AnodyneClient(cacheRoot: root, configuredInstance: { instance }, fallbackStore: fallback) { request in
            let url = try XCTUnwrap(request.url)
            let data = Data("{}".utf8)
            return (data, URLResponse(url: url, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: nil))
        }
        do {
            _ = try await malformedIndex.userNotes(matching: ["Example"])
            XCTFail("A response with no entries field must fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotParseResponse)
        }
        let savedNotes = await malformedIndex.cachedUserNotes(matching: ["Example"])
        XCTAssertEqual(savedNotes, [previous])
        XCTAssertEqual(try Data(contentsOf: files.userNotes), cached)
        XCTAssertEqual(fallback.duration(for: "Example", route: .oral)?.onset, onset)

        let malformedPage = AnodyneClient(cacheRoot: root, configuredInstance: { instance }, fallbackStore: fallback) { request in
            let url = try XCTUnwrap(request.url)
            let body = url.path.hasSuffix("/api/index/user")
                ? #"{"Entries":[{"Title":"A"}]}"#
                : #"{"Title":"A","TriedSubstances":{}}"#
            let data = Data(body.utf8)
            return (data, URLResponse(url: url, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: nil))
        }
        let refreshed = try await malformedPage.userNotes(matching: ["Example"])
        XCTAssertEqual(refreshed, [previous])
        XCTAssertEqual(try Data(contentsOf: files.userNotes), cached)
        XCTAssertEqual(fallback.duration(for: "Example", route: .oral)?.onset, onset)
    }

    func testInFlightLookupIsDiscardedEvenAfterSwitchingBack() async throws {
        let first = try XCTUnwrap(URL(string: "https://wiki.example.org/first"))
        let second = try XCTUnwrap(URL(string: "https://wiki.example.org/second"))
        let settings = InstanceSettings(first)
        let root = temporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fallback = AnodyneFallbackStore(cacheRoot: root, configuredInstance: { settings.url })
        let payload = try JSONSerialization.data(withJSONObject: fixture("mdma"))
        let server = PausedResponse(payload: payload)
        let client = AnodyneClient(cacheRoot: root, configuredInstance: { settings.url }, fallbackStore: fallback) { request in
            let url = try XCTUnwrap(request.url)
            return (await server.load(url), URLResponse(url: url, mimeType: "application/json", expectedContentLength: payload.count, textEncodingName: nil))
        }

        let pending = Task { try await client.lookup("MDMA") }
        let requestedURL = await server.firstRequest()
        XCTAssertEqual(requestedURL.absoluteString, first.absoluteString + "/api/substance/MDMA")
        await client.applyInstanceChange { settings.url = second }
        await client.applyInstanceChange { settings.url = first }
        await server.release()

        do {
            _ = try await pending.value
            XCTFail("A response from before the instance switch must be discarded")
        } catch is CancellationError {
        }
        let cached = await client.cachedLookup(for: "MDMA")
        XCTAssertNil(cached)
        XCTAssertNil(fallback.dose(for: "MDMA", route: .oral))
        XCTAssertFalse(FileManager.default.fileExists(atPath: AnodyneCacheFiles(root: root, instance: first).directory.path))
    }

    @MainActor
    func testBackupInstanceSwitchRefreshesDiskAndOfflineData() async throws {
        let first = try XCTUnwrap(URL(string: "https://wiki.example.org/first"))
        let second = try XCTUnwrap(URL(string: "https://wiki.example.org/second"))
        let settings = InstanceSettings(first)
        let root = temporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fallback = AnodyneFallbackStore(cacheRoot: root, configuredInstance: { settings.url })
        let payload = try JSONSerialization.data(withJSONObject: fixture("mdma"))
        let client = AnodyneClient(cacheRoot: root, configuredInstance: { settings.url }, fallbackStore: fallback) { request in
            let url = try XCTUnwrap(request.url)
            return (payload, URLResponse(url: url, mimeType: "application/json", expectedContentLength: payload.count, textEncodingName: nil))
        }

        let original = try await client.lookup("MDMA")
        XCTAssertNotNil(fallback.dose(for: "MDMA", route: .oral))
        let originalFiles = AnodyneCacheFiles(root: root, instance: first)
        let newFiles = AnodyneCacheFiles(root: root, instance: second)
        XCTAssertNotEqual(originalFiles.directory, newFiles.directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFiles.lookupFile(for: "mdma").path))

        let persistence = PersistenceController(inMemory: true)
        var backup = try JournalBackup(context: persistence.viewContext, defaults: settings.defaults, appVersion: "test")
        backup.settings[PersistenceController.anodyneInstanceURLKey] = .string(second.absoluteString)
        let restored = backup
        await client.applyInstanceChange { restored.restoreSettings(to: settings.defaults) }

        XCTAssertEqual(settings.url, second)
        let cached = await client.cachedLookup(for: "MDMA")
        XCTAssertNil(cached)
        XCTAssertNil(fallback.dose(for: "MDMA", route: .oral))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFiles.directory.path))

        let fresh = try await client.lookup("MDMA")
        XCTAssertEqual(fresh, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFiles.lookupFile(for: "mdma").path))
        let reloaded = AnodyneFallbackStore(cacheRoot: root, configuredInstance: { settings.url })
        XCTAssertNotNil(reloaded.dose(for: "MDMA", route: .oral))
    }

    private func temporaryCacheRoot() -> URL {
        URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private final class InstanceSettings: @unchecked Sendable {
        private let suite = "AnodyneTests.\(UUID())"
        let defaults: UserDefaults

        init(_ url: URL) {
            defaults = UserDefaults(suiteName: suite)!
            self.url = url
        }

        deinit { defaults.removePersistentDomain(forName: suite) }

        var url: URL {
            get {
                defaults.string(forKey: PersistenceController.anodyneInstanceURLKey)
                    .flatMap(AnodyneSubstance.instanceURL(from:)) ?? AnodyneSubstance.defaultBaseURL
            }
            set { defaults.set(newValue.absoluteString, forKey: PersistenceController.anodyneInstanceURLKey) }
        }
    }

    private actor PausedResponse {
        let payload: Data
        private var requestedURL: URL?
        private var requestWaiter: CheckedContinuation<URL, Never>?
        private var responseWaiter: CheckedContinuation<Data, Never>?

        init(payload: Data) { self.payload = payload }

        func load(_ url: URL) async -> Data {
            requestedURL = url
            requestWaiter?.resume(returning: url)
            requestWaiter = nil
            return await withCheckedContinuation { responseWaiter = $0 }
        }

        func firstRequest() async -> URL {
            if let requestedURL { return requestedURL }
            return await withCheckedContinuation { requestWaiter = $0 }
        }

        func release() {
            responseWaiter?.resume(returning: payload)
            responseWaiter = nil
        }
    }

    func testReadsInstanceAddresses() {
        XCTAssertEqual(AnodyneSubstance.instanceURL(from: "wiki.example.org")?.absoluteString, "https://wiki.example.org")
        XCTAssertEqual(
            AnodyneSubstance.instanceURL(from: " http://192.168.1.5:8080/ ")?.absoluteString,
            "http://192.168.1.5:8080"
        )
        XCTAssertEqual(AnodyneSubstance.instanceURL(from: "https://anodyne.wiki"), AnodyneSubstance.defaultBaseURL)
        XCTAssertNil(AnodyneSubstance.instanceURL(from: "ftp://wiki.example.org"))
        XCTAssertNil(AnodyneSubstance.instanceURL(from: "not a url"))
        XCTAssertNil(AnodyneSubstance.instanceURL(from: ""))
    }

    func testUnknownSubstanceIsNotFound() throws {
        XCTAssertNil(AnodyneSubstance(apiJSON: try fixture("notFound")))
    }

    func testIndexEntries() throws {
        let entries = (try fixture("index")["Entries"] as? [[String: Any]] ?? []).compactMap(AnodyneIndexEntry.init(apiJSON:))
        // Oxytocin is marked NoBuild and has no page
        XCTAssertEqual(entries.map(\.title).sorted(), ["3,4-Methylenedioxymethamphetamine", "Amphetamine", "Ketamine"])
        let ketamine = try XCTUnwrap(entries.first { $0.title == "Ketamine" })
        XCTAssertTrue(ketamine.matches("k"))
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.title == "Amphetamine" }).matches("speed"))
    }

    func testMapsAdministrationMethods() {
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Insufflated"), .insufflated)
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Sublingual"), .sublingual)
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Intravenous"), .intravenous)
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Vaporized"), .inhaled)
        XCTAssertNil(AnodyneSubstance.route(forMethod: "Ocular"))
    }
}
