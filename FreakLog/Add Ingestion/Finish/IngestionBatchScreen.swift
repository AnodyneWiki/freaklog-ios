import CoreData
import SwiftUI

struct StagedIngestion: Identifiable {
    let id = UUID()
    let arguments: [FinishIngestionScreenArguments]
    var time: Date
    var endTime: Date?
    var note: String
    let consumer: String
    let location: Location?
    let sites: AdministrationSiteSelection
    let colors: [String: SubstanceColor]
    let isUnconfirmed: Bool
    var stockContainerID: NSManagedObjectID?
    let webhookPresetIDs: [NSManagedObjectID]

    var timeRange: ClosedRange<Date> { time...max(time, endTime ?? time) }

    var title: String {
        if let formulation = arguments.first?.formulation { return formulation.nameUnwrapped }
        if let unit = arguments.first?.customUnit { return unit.nameUnwrapped }
        return arguments.map { PersistenceController.shared.displayName(for: $0.substanceName) }
            .uniqued().formatted(.list(type: .and))
    }

    var amount: String? {
        guard let first = arguments.first else { return nil }
        if let count = first.formulationAmount {
            return count.doseDescription(units: "servings", isEstimate: false, standardDeviation: nil)
        }
        if arguments.count == 1 { return first.reviewAmount }
        return nil
    }

    struct Saved {
        fileprivate let context: NSManagedObjectContext
        let experience: Experience
        let ingestions: [Ingestion]
        let webhookPresetsByIngestion: [NSManagedObjectID: [NSManagedObjectID]]

        @MainActor
        func notifyIntegrations() {
            IngestionSaving.didSave(
                ingestions, newIngestions: ingestions, webhookPresetsByIngestion: webhookPresetsByIngestion
            )
        }
    }

    @MainActor
    static func persist(
        _ drafts: [Self], to destination: Experience?, title: String,
        routineSlot: RoutineOccurrenceSlot? = nil, persistence: PersistenceController = .shared
    ) throws -> Saved {
        guard let earliestTime = drafts.map(\.time).min(), drafts.allSatisfy({ !$0.arguments.isEmpty }) else {
            throw SaveError.empty
        }
        let context = try persistence.journalEditContext()
        return try PersistenceController.withJournalStoreWrite {
            let experience = try destination.map { try PersistenceController.journalObject($0, in: context) }
                ?? Experience.create(at: earliestTime, title: title, in: context)
            let occurrence: RoutineOccurrence?
            if let routineSlot {
                guard let pending = try RoutineSchedules.stageLog(for: routineSlot, in: context) else {
                    throw RoutineSchedules.StorageError.alreadyLogged
                }
                occurrence = pending
            } else {
                occurrence = nil
            }

            var companions = try Dictionary(
                context.fetch(PersistenceController.substanceCompanionsRequest()).map { ($0.substanceNameUnwrapped, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var loggedEntries: [(Ingestion, [NSManagedObjectID])] = []
            for draft in drafts {
                let entries = try draft.stage(in: context, for: experience, occurrence: occurrence, companions: &companions)
                loggedEntries += entries.map { ($0, draft.webhookPresetIDs) }
            }
            let ingestions = loggedEntries.map(\.0)
            try PersistenceController.saveJournalChanges(in: context)
            return Saved(
                context: context, experience: experience, ingestions: ingestions,
                webhookPresetsByIngestion: Dictionary(uniqueKeysWithValues: loggedEntries.map { ($0.objectID, $1) })
            )
        }
    }

    @MainActor
    private func stage(
        in context: NSManagedObjectContext, for experience: Experience, occurrence: RoutineOccurrence?,
        companions: inout [String: SubstanceCompanion]
    ) throws -> [Ingestion] {
        let confirmationBatchID = isUnconfirmed && arguments.count > 1 ? UUID() : nil
        let entries = try arguments.map { argument in
            let name = argument.substanceName
            let color = colors[name] ?? .fallback
            let companion = companions[name] ?? SubstanceCompanion(context: context)
            companion.substanceName = name
            companion.colorAsText = color.rawValue
            companions[name] = companion

            let ingestion = Ingestion(context: context)
            ingestion.identifier = UUID()
            ingestion.time = time
            ingestion.endTime = endTime
            ingestion.creationDate = .now
            ingestion.customUnit = try argument.customUnit.map { try PersistenceController.journalObject($0, in: context) }
            ingestion.formulation = try argument.formulation.map { try PersistenceController.journalObject($0, in: context) }
            ingestion.formulationAmount = argument.formulationAmount ?? 0
            ingestion.isHiddenInTimeline = argument.isHiddenInTimeline
            ingestion.dose = argument.dose ?? 0
            ingestion.units = argument.units
            ingestion.isEstimate = argument.isEstimate
            ingestion.estimatedDoseStandardDeviation = argument.estimatedDoseStandardDeviation ?? 0
            ingestion.note = note
            ingestion.administrationRoute = argument.administrationRoute.rawValue
            ingestion.substanceName = name
            ingestion.color = color.rawValue
            ingestion.consumerName = Ingestion.storedConsumerName(consumer)
            let site = sites.siteString(for: argument.administrationRoute)
            ingestion.administrationSite = site.isEmpty ? nil : site
            ingestion.experience = experience
            ingestion.setLocation(location)
            ingestion.substanceCompanion = companion
            ingestion.isUnconfirmed = isUnconfirmed
            ingestion.confirmationBatchID = confirmationBatchID
            ingestion.routineOccurrence = occurrence
            return ingestion
        }
        if !isUnconfirmed, let stockContainerID {
            guard let use = Inventory.Use(arguments) else { throw InventoryError.sourceChanged }
            try use.stage(using: stockContainerID, for: entries, at: .now, in: context)
            context.processPendingChanges()
        }
        return entries
    }

    private enum SaveError: LocalizedError {
        case empty

        var errorDescription: String? {
            String(localized: "Add an ingestion before saving the batch.")
        }
    }
}

struct IngestionBatchScreen: View {
    @Binding var drafts: [StagedIngestion]
    let onSaved: () -> Void

    @EnvironmentObject private var toastViewModel: ToastViewModel
    @Environment(\.managedObjectContext) private var context
    @State private var selectedExperience: Experience?
    @State private var wantsNewExperience = true
    @State private var experiences: [Experience] = []
    @State private var title = ""
    @State private var saveError: String?
    @State private var isSaving = false

    @FetchRequest(fetchRequest: PersistenceController.enabledWebhookPresetsRequest())
    private var enabledWebhookPresets: FetchedResults<WebhookPreset>

    var body: some View {
        Form {
            Section("Entries") {
                if drafts.isEmpty {
                    Text("No entries yet").foregroundStyle(.secondary)
                }
                ForEach($drafts) { $draft in
                    NavigationLink {
                        StagedIngestionEditor(draft: $draft)
                    } label: {
                        entryRow(draft)
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0); saveError = nil }
            }
            if !drafts.isEmpty {
                experienceSection
            }
            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.circle")
                } footer: {
                    Text("Your drafts are still here. Review the entries and try again.")
                }
            }
        }
        .navigationTitle("Review Batch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(drafts.allSatisfy(\.isUnconfirmed) ? "Save Batch" : "Log Batch", action: save)
                    .font(.headline)
                    .disabled(drafts.isEmpty || isSaving)
            }
        }
        .task(id: drafts.map(\.timeRange)) {
            let nearby = Set(drafts.flatMap { PersistenceController.shared.getExperiences(near: $0.timeRange) })
            experiences = nearby.sorted()
            if let selectedExperience, !nearby.contains(selectedExperience) {
                experiences.insert(selectedExperience, at: 0)
            }
        }
    }

    private var experienceSection: some View {
        Section {
            if experiences.isEmpty {
                LabeledContent("Add To", value: "New Experience")
            } else {
                ExperiencePickerRow(
                    selectedExperience: $selectedExperience, wantsToForceNewExperience: $wantsNewExperience,
                    experiences: experiences
                )
            }
            if selectedExperience == nil {
                TextField("Title (Optional)", text: $title)
                    .textInputAutocapitalization(.sentences)
            }
        } header: {
            Text("Experience")
        } footer: {
            Text("All entries go into this experience at their own recorded times.")
        }
    }

    private func entryRow(_ draft: StagedIngestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.title).font(.headline)
            if let amount = draft.amount { Text(amount) }
            if let end = draft.endTime, draft.time < end {
                Text((draft.time..<end).formatted(.interval.month(.abbreviated).day().hour().minute()))
                    .foregroundStyle(.secondary)
            } else {
                Text(draft.time, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            if draft.isUnconfirmed {
                Text("Unconfirmed").font(.subheadline).foregroundStyle(.secondary)
            } else {
                if let id = draft.stockContainerID {
                    let container = try? context.existingObject(with: id) as? StockContainer
                    let name = container?.displayName ?? String(localized: "Unavailable Container")
                    Label(name, systemImage: "shippingbox").font(.subheadline).foregroundStyle(.secondary)
                }
                let names = enabledWebhookPresets.filter { draft.webhookPresetIDs.contains($0.objectID) }.map(\.displayName)
                if !names.isEmpty {
                    Label(names.formatted(.list(type: .and)), systemImage: "arrow.up.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        do {
            let saved = try StagedIngestion.persist(drafts, to: selectedExperience, title: title)
            saved.notifyIntegrations()
            toastViewModel.showSuccessToast(message: String(localized: "Batch Saved"))
            onSaved()
        } catch {
            isSaving = false
            saveError = (error as? LocalizedError)?.errorDescription ?? String(localized: "The batch couldn’t be saved.")
        }
    }
}

private struct StagedIngestionEditor: View {
    @Binding var draft: StagedIngestion
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TimePickerOption
    @State private var time: Date
    @State private var endTime: Date
    @State private var note: String
    @State private var stockContainerID: NSManagedObjectID?

    init(draft: Binding<StagedIngestion>) {
        _draft = draft
        let entry = draft.wrappedValue
        _mode = State(initialValue: entry.endTime == nil ? .pointInTime : .timeRange)
        _time = State(initialValue: entry.time)
        _endTime = State(initialValue: entry.endTime ?? entry.time.addingTimeInterval(30 * 60))
        _note = State(initialValue: entry.note)
        _stockContainerID = State(initialValue: entry.stockContainerID)
    }

    var body: some View {
        Form {
            Section("When") {
                TimePointOrRangePicker(
                    selectedTimePickerOption: $mode, selectedTime: $time, selectedEndTime: $endTime,
                    showsPresets: true
                )
            }
            Section("Details") {
                TextField("Note", text: $note, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
            }
            if !draft.isUnconfirmed, let use = Inventory.Use(draft.arguments) {
                InventorySourcePicker(use: use, selection: $stockContainerID)
            }
        }
        .navigationTitle(draft.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    draft.time = time
                    draft.endTime = mode == .timeRange ? endTime : nil
                    draft.note = note
                    draft.stockContainerID = stockContainerID
                    dismiss()
                }
                .font(.headline)
            }
        }
    }
}
