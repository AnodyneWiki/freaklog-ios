import SwiftUI
import CoreData

struct DoseEntryView: View {
    let substance: SubstanceLite
    let route: AdministrationRoute
    @Binding var path: NavigationPath
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    @State private var dose: Double = 0
    @State private var unit: String = ""
    @State private var time: Date = Date()
    @State private var isEstimate = false
    @State private var isSaving = false
    @State private var showSavedConfirmation = false

    private var roaDose: RoaDose? {
        substance.fullSubstance?.getDose(for: route)
    }

    var defaultUnits: String {
        roaDose?.units ?? unit.ifEmpty("mg")
    }

    var suggestedDoses: [Double] {
        guard let dose = roaDose else { return [] }
        return [dose.lightMin, dose.commonMin, dose.strongMin, dose.heavyMin]
            .compactMap { $0 }
            .uniqued()
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Circle().fill(substance.color.swiftUIColor).frame(width: 12, height: 12)
                    Text(substance.name).font(.headline)
                    Spacer()
                    Text(route.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Dose") {
                Stepper(value: $dose, in: 0...100000, step: stepValue) {
                    HStack {
                        Text("\(dose.formatted())")
                        Text(defaultUnits).foregroundStyle(.secondary)
                    }
                }
                if !suggestedDoses.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(suggestedDoses, id: \.self) { sd in
                                Button("\(sd.formatted())") { dose = sd }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                Toggle("Estimate", isOn: $isEstimate)
            }

            Section("Time") {
                DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute])
                Button("Now") { time = Date() }
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text("Save Ingestion").bold() }
                        Spacer()
                    }
                }
                .disabled(dose <= 0 || isSaving)
            }
        }
        .navigationTitle("Dose")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Saved", isPresented: $showSavedConfirmation) {
            Button("OK") {
                path = NavigationPath()
            }
        }
    }

    private var stepValue: Double {
        if defaultUnits.lowercased().contains("g") && !defaultUnits.lowercased().contains("mg") { return 0.1 }
        if dose < 1 { return 0.1 }
        if dose < 10 { return 0.5 }
        if dose < 100 { return 1 }
        return 10
    }

    private func save() {
        isSaving = true
        let context = moc

        // Find or create active experience: bucket by 12h window of last ingestion.
        let request: NSFetchRequest<Experience> = Experience.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        request.fetchLimit = 1

        let experience: Experience
        if let recent = try? context.fetch(request).first,
           let firstIngestionTime = recent.ingestionsSorted.first?.timeUnwrapped,
           time.timeIntervalSince(firstIngestionTime) < 60 * 60 * 12 {
            experience = recent
        } else {
            experience = Experience(context: context)
            experience.creationDate = Date()
            experience.sortDate = time
            experience.title = nil
            experience.text = ""
        }

        let ingestion = Ingestion(context: context)
        ingestion.identifier = UUID()
        ingestion.time = time
        ingestion.creationDate = Date()
        ingestion.dose = dose
        ingestion.units = defaultUnits
        ingestion.isEstimate = isEstimate
        ingestion.administrationRoute = route.rawValue
        ingestion.substanceName = substance.name
        ingestion.color = substance.color.rawValue
        ingestion.experience = experience

        do {
            try context.save()
            playHapticFeedback()
            showSavedConfirmation = true
        } catch {
            print("Watch save failed: \(error)")
        }
        isSaving = false
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
