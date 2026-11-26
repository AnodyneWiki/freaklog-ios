import CoreData
import SwiftUI

struct MoveIngestionsScreen: View {
    @ObservedObject var source: Experience
    var onMove: (IngestionMove.Receipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<NSManagedObjectID>()
    @State private var destination: Experience?
    @State private var makesNewExperience = false
    @State private var title = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                let ingestions = source.ingestionsSorted
                Section {
                    ForEach(ingestions) { ingestion in
                        ingestionRow(ingestion)
                    }
                    if ingestions.isEmpty {
                        Text("No ingestions to move").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ingestions")
                } footer: {
                    if ingestions.contains(where: { $0.isUnconfirmed && $0.confirmationBatchID != nil }) {
                        Text("Unconfirmed batches move together.")
                    }
                }

                Section {
                    NavigationLink {
                        MoveExperiencePicker(source: source) { experience in
                            destination = experience
                            makesNewExperience = experience == nil
                        }
                    } label: {
                        LabeledContent("Move To", value: destinationName)
                    }
                    if makesNewExperience {
                        TextField("Title (Optional)", text: $title)
                            .textInputAutocapitalization(.sentences)
                    }
                } footer: {
                    Text("Notes, ratings, and the original experience stay in place. Ingestions keep their times, stock, and routine links.")
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                    }
                }
            }
            .navigationTitle("Move Ingestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move", action: move)
                        .disabled(selection.isEmpty || (!makesNewExperience && destination == nil))
                }
            }
        }
    }

    private var destinationName: String {
        if makesNewExperience { return String(localized: "New Experience") }
        return destination?.titleUnwrapped ?? String(localized: "Choose Experience")
    }

    private func ingestionRow(_ ingestion: Ingestion) -> some View {
        let isSelected = selection.contains(ingestion.objectID)
        return Button {
            let batch = Set(ingestion.pendingConfirmationEntries.map(\.objectID))
            let ids = batch.isEmpty ? [ingestion.objectID] : batch
            if isSelected {
                selection.subtract(ids)
            } else {
                selection.formUnion(ids)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingestion.substanceDisplayName)
                        .foregroundStyle(.primary)
                    HStack {
                        if let time = ingestion.time {
                            Text(time, format: .dateTime.month(.abbreviated).day().hour().minute())
                        }
                        if let dose = ingestion.doseUnwrapped {
                            Text("\(dose.formatted()) \(ingestion.unitsUnwrapped)")
                        }
                        if !ingestion.isMine {
                            Text(ingestion.consumerNameUnwrapped)
                        }
                        if ingestion.isUnconfirmed {
                            Text("Unconfirmed")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            } icon: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move() {
        guard let target: IngestionMove.Destination = makesNewExperience
            ? .new(title: title) : destination.map({ .existing($0.objectID) }) else { return }
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let (receipt, moved) = try IngestionMove.move(selection, from: source.objectID, to: target, in: context)
            IngestionSaving.didSave(moved, newIngestions: [])
            onMove(receipt)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MoveExperiencePicker: View {
    var didSelect: (Experience?) -> Void

    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var experiences: FetchedResults<Experience>
    @State private var search = ""

    init(source: Experience, didSelect: @escaping (Experience?) -> Void) {
        self.didSelect = didSelect
        let request = PersistenceController.experiencesRequest()
        request.predicate = NSPredicate(format: "SELF != %@", source)
        request.fetchBatchSize = 30
        _experiences = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        List {
            Section {
                Button {
                    didSelect(nil)
                    dismiss()
                } label: {
                    Label("New Experience", systemImage: "plus")
                }
            }
            Section("Existing Experiences") {
                let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                ForEach(experiences.filter { query.isEmpty || $0.titleUnwrapped.localizedStandardContains(query) }) { experience in
                    Button {
                        didSelect(experience)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(experience.titleUnwrapped).foregroundStyle(.primary)
                            if let date = experience.sortDate {
                                Text(date, style: .date).foregroundStyle(.secondary).font(.subheadline)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Move To")
        .searchable(text: $search, prompt: "Find an experience")
    }
}

@MainActor
enum IngestionMove {
    enum Destination {
        case existing(NSManagedObjectID)
        case new(title: String)
    }

    struct Receipt {
        fileprivate let sourceID: NSManagedObjectID
        fileprivate let destinationID: NSManagedObjectID
        fileprivate let ingestionIDs: Set<NSManagedObjectID>
        fileprivate let destinationWasEmpty: Bool
        fileprivate let originalDestinationSortDate: Date?
        fileprivate let newDestinationTitle: String?
    }

    enum MoveError: LocalizedError {
        case entriesChanged, incompleteBatch, destinationChanged

        var errorDescription: String? {
            switch self {
            case .entriesChanged:
                String(localized: "Some selected ingestions changed. Review the selection and try again.")
            case .incompleteBatch:
                String(localized: "Select every ingestion in an unconfirmed batch to move it.")
            case .destinationChanged:
                String(localized: "The destination experience is no longer available.")
            }
        }
    }

    static func move(
        _ selection: Set<NSManagedObjectID>, from sourceID: NSManagedObjectID,
        to target: Destination, in context: NSManagedObjectContext
    ) throws -> (Receipt, [Ingestion]) {
        try PersistenceController.withJournalStoreWrite {
            let ingestions = try entries(selection, inExperience: sourceID, context: context)
            let destination: Experience
            let wasCreated: Bool
            switch target {
            case .existing(let destinationID):
                guard destinationID != sourceID,
                      let existing = try? context.existingObject(with: destinationID) as? Experience,
                      !existing.isDeleted else { throw MoveError.destinationChanged }
                destination = existing
                wasCreated = false
            case .new(let title):
                let time = ingestions.compactMap(\.time).min() ?? .now
                destination = Experience.create(at: time, title: title, in: context)
                wasCreated = true
            }
            let destinationWasEmpty = destination.ingestionsSorted.isEmpty
            let originalDestinationSortDate = destination.sortDate
            for ingestion in ingestions {
                ingestion.experience = destination
            }
            try PersistenceController.saveJournalChanges(in: context)
            let receipt = Receipt(
                sourceID: sourceID, destinationID: destination.objectID, ingestionIDs: selection,
                destinationWasEmpty: destinationWasEmpty,
                originalDestinationSortDate: originalDestinationSortDate,
                newDestinationTitle: wasCreated ? destination.title : nil
            )
            return (receipt, ingestions)
        }
    }

    static func undo(_ receipt: Receipt, in context: NSManagedObjectContext) throws -> [Ingestion] {
        try PersistenceController.withJournalStoreWrite {
            let ingestions = try entries(receipt.ingestionIDs, inExperience: receipt.destinationID, context: context)
            guard let source = try? context.existingObject(with: receipt.sourceID) as? Experience,
                  !source.isDeleted, let destination = ingestions.first?.experience else { throw MoveError.destinationChanged }
            let movedSortDate = destination.sortDate
            for ingestion in ingestions {
                ingestion.experience = source
            }
            if destination.ingestionsSorted.isEmpty {
                if let originalTitle = receipt.newDestinationTitle, destination.title == originalTitle,
                   destination.textUnwrapped.isEmpty, destination.legacyLocation == nil, !destination.isFavorite,
                   destination.ratingsUnwrapped.isEmpty, destination.timedNotesSorted.isEmpty {
                    context.delete(destination)
                } else if receipt.destinationWasEmpty, movedSortDate == ingestions.compactMap(\.time).min() {
                    destination.sortDate = receipt.originalDestinationSortDate
                }
            }
            try PersistenceController.saveJournalChanges(in: context)
            return ingestions
        }
    }

    private static func entries(
        _ ids: Set<NSManagedObjectID>, inExperience experienceID: NSManagedObjectID, context: NSManagedObjectContext
    ) throws -> [Ingestion] {
        guard !ids.isEmpty else { throw MoveError.entriesChanged }
        let ingestions = try ids.map { id in
            guard let ingestion = try? context.existingObject(with: id) as? Ingestion,
                  !ingestion.isDeleted, ingestion.experience?.objectID == experienceID else {
                throw MoveError.entriesChanged
            }
            return ingestion
        }
        let batches = Set(ingestions.filter(\.isUnconfirmed).compactMap(\.confirmationBatchID))
        if !batches.isEmpty, let experience = ingestions.first?.experience {
            let containsPartialBatch = experience.ingestionsSorted.contains {
                guard $0.isUnconfirmed, let batch = $0.confirmationBatchID, batches.contains(batch) else { return false }
                return !ids.contains($0.objectID)
            }
            if containsPartialBatch {
                throw MoveError.incompleteBatch
            }
        }
        return ingestions
    }
}
