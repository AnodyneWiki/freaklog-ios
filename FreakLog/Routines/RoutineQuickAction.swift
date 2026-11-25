import CryptoKit
import Foundation

struct RoutineOccurrenceSlot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let scheduleID: UUID
    let scheduledAt: Date

    var isManual: Bool { id.hasPrefix("\(scheduleID.uuidString).manual.") }

    var timeID: UUID? {
        let parts = id.split(separator: ".")
        guard parts.count == 3, !isManual else { return nil }
        return UUID(uuidString: String(parts[2]))
    }

    // The same occurrence has the same receipt on the widget, on Watch and after a retry.
    var receiptID: UUID {
        let hash = SHA256.hash(data: Data("FreakLog:RoutineTaken:\(id)".utf8))
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct RoutineQuickAction: Codable, Equatable, Sendable {
    let slot: RoutineOccurrenceSlot
    let revision: Data
}

struct RoutineTakenRequest: Codable, Equatable, Sendable, Identifiable {
    let action: RoutineQuickAction
    let recordedAt: Date

    var id: UUID { action.slot.receiptID }
}

struct RoutineQuickSnapshot: Codable, Equatable, Sendable {
    struct Preview: Codable, Equatable, Sendable {
        let scheduledAt: Date
        let dayStart: Date
        let dayEnd: Date
        var action: RoutineQuickAction?
    }

    let previews: [Preview]
    let phoneLocked: Bool
    static let empty = Self(previews: [], phoneLocked: false)

    func next(at date: Date) -> Preview? {
        previews.first { date < $0.dayEnd }
    }

    #if os(iOS)
    private static var file: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RoutineAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("NextRoutine.json")
    }

    static func read() -> Self {
        guard let file, let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return snapshot
    }

    #if !WIDGET_EXTENSION
    func write() throws -> Bool {
        guard let file = Self.file else { return false }
        try JSONEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtection])
        return true
    }
    #endif
    #endif
}

#if os(iOS)
import AppIntents

@available(iOS 17.0, *)
struct MarkRoutineTakenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Routine Taken"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isDiscoverable = false

    @Parameter(title: "Routine")
    var data: String

    init() {}

    init(action: RoutineQuickAction) {
        data = (try? JSONEncoder().encode(action))?.base64EncodedString() ?? ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        // WidgetKit runs this intent in the app where the journal lives.
        try requireJournal()
        #else
        guard let payload = Data(base64Encoded: data),
              let action = try? JSONDecoder().decode(RoutineQuickAction.self, from: payload) else {
            throw MarkRoutineTakenError.openJournal
        }
        try RoutineQuickLogging.markTaken(RoutineTakenRequest(action: action, recordedAt: .now))
        #endif
        return .result()
    }

    #if WIDGET_EXTENSION
    private func requireJournal() throws { throw MarkRoutineTakenError.openJournal }
    #endif
}

enum MarkRoutineTakenError: LocalizedError {
    case openJournal
    case routineChanged

    var errorDescription: String? {
        switch self {
        case .openJournal: String(localized: "Open FreakLog on your iPhone to log this routine.")
        case .routineChanged: String(localized: "This routine changed. Review it on your iPhone.")
        }
    }
}
#endif
