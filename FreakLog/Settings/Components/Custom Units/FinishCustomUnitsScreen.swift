import SwiftUI

struct FinishCustomUnitsScreen: View {
    enum Field: Hashable {
        case name
        case unit
        case unitPlural
        case dose
        case note
    }

    let arguments: SubstanceAndRoute
    let cancel: () -> Void
    private let completion: Completion
    private let draft: CustomUnitCodable?

    private enum Completion {
        case save((CustomUnit) -> Void)
        case draft((CustomUnitCodable) -> Void)
    }

    init(arguments: SubstanceAndRoute, cancel: @escaping () -> Void, onAdded: @escaping (CustomUnit) -> Void) {
        self.init(arguments: arguments, cancel: cancel, name: "", draft: nil, completion: .save(onAdded))
    }

    init(
        arguments: SubstanceAndRoute,
        cancel: @escaping () -> Void,
        name: String = "",
        draft: CustomUnitCodable? = nil,
        onDraft: @escaping (CustomUnitCodable) -> Void
    ) {
        self.init(arguments: arguments, cancel: cancel, name: name, draft: draft, completion: .draft(onDraft))
    }

    private init(
        arguments: SubstanceAndRoute, cancel: @escaping () -> Void,
        name: String, draft: CustomUnitCodable?, completion: Completion
    ) {
        self.arguments = arguments
        self.cancel = cancel
        self.draft = draft
        self.completion = completion
        _name = State(initialValue: draft?.name ?? name)
        _unit = State(initialValue: draft?.unit ?? "")
        _unitPlural = State(initialValue: draft?.unitPlural ?? "")
        _originalUnit = State(initialValue: draft?.originalUnit ?? "")
        _dosePerUnit = State(initialValue: draft?.dose)
        _isEstimate = State(initialValue: draft?.isEstimate ?? false)
        _estimatedDoseStandardDeviation = State(initialValue: draft?.estimatedDoseStandardDeviation)
        _note = State(initialValue: draft?.note ?? "")
    }

    struct Prompt {
        let name: String
        let unit: String
        let unitPlural: String
    }

    var prompt: Prompt {
        switch arguments.substance.name {
        case "Cannabis":
            return Prompt(name: "e.g. Joint weed 20%, Bong weed, Vaporizer weed", unit: "mg", unitPlural: "mg")
        case "Psilocybin mushrooms":
            return Prompt(name: "Mushroom strain", unit: "g", unitPlural: "g")
        case "Alcohol":
            return Prompt(name: "e.g. Beer, Wine, Spirit", unit: "e.g. ml, cup", unitPlural: "e.g. ml, cups")
        case "Caffeine":
            return Prompt(name: "e.g. Coffee, Tea, Energy drink", unit: "e.g. cup, can", unitPlural: "e.g. cups, cans")
        default:
            switch arguments.administrationRoute {
            case .oral:
                return Prompt(name: "e.g. Blue rocket, 85% powder", unit: "e.g. pill, capsule, mg", unitPlural: "e.g. pills, capsules, mg")
            case .smoked:
                return Prompt(name: "e.g. 85% powder", unit: "e.g. mg, hit", unitPlural: "e.g. mg, hits")
            case .insufflated:
                return Prompt(name: "e.g. Nasal solution, Blue dispenser", unit: "e.g. spray, spoon, scoop, line", unitPlural: "e.g. sprays, spoons, scoops, lines")
            case .buccal:
                return Prompt(name: "e.g. Brand name", unit: "e.g. pouch", unitPlural: "e.g. pouches")
            case .transdermal:
                return Prompt(name: "e.g. Brand name", unit: "e.g. patch", unitPlural: "e.g. patches")
            default:
                return Prompt(name: "e.g. 85% powder, Blue rocket", unit: "e.g. pill, spray, spoon", unitPlural: "e.g. pills, sprays, spoons")
            }

        }
    }
    
    var body: some View {
        let substanceName = arguments.substance.name
        Form {
            if substanceName == "Cannabis" && arguments.administrationRoute == .smoked {
                Section {
                    Text("When smoking a joint about 23% of the THC in the bud is inhaled. So if you smoke a joint with 300mg of a bud that has 20% THC then you inhale 300mg * 20/100 * 23/100 = 13.8mg THC.")
                    Text("When smoking with a bong about 40% of the THC in the bud is inhaled. So if you smoke 300mg of a bud that has 20% THC then you inhale 300mg * 20/100 * 40/100 = 24mg THC.")
                    Text("When smoking with a vaporizer about 70% of the THC in the bud is inhaled. So if you smoke 300mg of a bud that has 20% THC then you inhale 300mg * 20/100 * 70/100 = 42mg THC.")
                }
            } else if substanceName == "Psilocybin mushrooms" {
                Section {
                    Text("Dried Psilocybe cubensis contain around 1% of Psilocybin.")
                    Text("Fresh Psilocybe cubensis contain around 0.1% of Psilocybin.")
                    Text("Research the strain of mushroom you have to be able to estimate the amount of Psilocybin it contains.")
                }
            } else if substanceName == "Alcohol" {
                Section {
                    Text("1 ml of Ethanol is 0.8g. So if you are e.g. consuming 200ml of a spirit with 40% of Alcohol you are consuming 200ml * 40/100 * 0.8 = 64g Ethanol.")
                }
            }
            Section {
                LabeledContent {
                    TextField("Name", text: $name, prompt: Text(prompt.name))
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .unit
                        }
                } label: {
                    Text("Name:")
                }
                LabeledContent {
                    TextField("Unit", text: $unit, prompt: Text(prompt.unit))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .unit)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .unitPlural
                        }
                } label: {
                    Text("Unit singular:")
                }
                .onChange(of: unit, perform: { newValue in
                    unitPlural = PluralizableUnit.defaultPlural(of: newValue)
                })
                LabeledContent {
                    TextField("Unit plural", text: $unitPlural, prompt: Text(prompt.unitPlural))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .unitPlural)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .note
                        }
                } label: {
                    Text("Unit plural:")
                }
                TextField("Notes", text: $note, axis: .vertical)
                    .focused($focusedField, equals: .note)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .dose
                    }
            }
            let areUnitsDefined = roaDose?.units != nil
            if arguments.substance.customSubstanceUnits == nil, !areUnitsDefined {
                Section("Original Unit") {
                    UnitsPicker(units: $originalUnit)
                        .padding(.bottom, 10)
                }
            }
            Section("Dose per \(unitOrPlaceholder)") {
                if let roaDose {
                    RoaDoseRow(roaDose: roaDose)
                }
                HStack {
                    TextField(
                        "Dose per \(unitOrPlaceholder)",
                        value: $dosePerUnit,
                        format: .number).keyboardType(.decimalPad)
                        .focused($focusedField, equals: .dose)
                    Spacer()
                    Text(originalUnit)
                }
                EstimateFields(
                    isEstimate: $isEstimate,
                    standardDeviation: $estimatedDoseStandardDeviation,
                    units: originalUnit,
                    mean: dosePerUnit
                )
            }.listRowSeparator(.hidden)
            if let originalUnit = roaDose?.units, !unit.isEmpty {
                Section("Ingestion Preview") {
                    IngestionRowPreview(
                        substanceName: substanceName,
                        administrationRoute: arguments.administrationRoute,
                        isEstimate: isEstimate,
                        unit: unit,
                        unitPlural: unitPlural,
                        dosePerUnit: dosePerUnit,
                        dosePerUnitStandardDeviation: estimatedDoseStandardDeviation,
                        originalUnit: originalUnit,
                        name: name)
                }
                if dosePerUnit != nil {
                    Section("Dose Picker Preview") {
                        VStack(alignment: .leading, spacing: 5) {
                            if !name.isEmpty {
                                Text(name).font(.headline)
                            }
                            CustomUnitDoseRow(
                                customUnit: CustomUnitMinInfo(dosePerUnit: dosePerUnit, unit: unit),
                                roaDose: roaDose)
                        }
                    }
                }
            }
        }
        .navigationTitle(draft == nil ? "Add Custom Unit" : "Edit Custom Unit")
        .onFirstAppear {
            focusedField = .name
            if draft == nil {
                originalUnit = arguments.substance.customSubstanceUnits ?? roaDose?.units ?? "mg"
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .primaryAction) {
                DoneButton(action: onDoneTap)
                    .disabled(trimmed(unit).isEmpty || trimmed(name).isEmpty)
            }
        }
    }

    @State private var name: String
    @State private var unit: String
    @State private var unitPlural: String
    @State private var originalUnit: String
    @State private var dosePerUnit: Double?
    @State private var isEstimate: Bool
    @State private var estimatedDoseStandardDeviation: Double?
    @State private var note: String

    @FocusState private var focusedField: Field?

    private var roaDose: RoaDose? {
        PersistenceController.shared.resolvedDose(for: arguments.substance.name, route: arguments.administrationRoute)
    }

    private var unitOrPlaceholder: String {
        if unit.isEmpty {
            "..."
        } else {
            unit
        }
    }


    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func onDoneTap() {
        let value = CustomUnitCodable(
            id: draft?.id ?? Int32.random(in: Int32.min..<Int32.max),
            substanceName: arguments.substance.name,
            name: trimmed(name),
            creationDate: draft?.creationDate ?? .now,
            administrationRoute: arguments.administrationRoute,
            dose: dosePerUnit,
            estimatedDoseStandardDeviation: estimatedDoseStandardDeviation,
            isEstimate: isEstimate,
            isArchived: false,
            unit: trimmed(unit),
            unitPlural: trimmed(unitPlural),
            originalUnit: originalUnit,
            note: note
        )
        switch completion {
        case .draft(let onDraft):
            onDraft(value)
        case .save(let onAdded):
            let context = PersistenceController.shared.viewContext
            let newCustomUnit = value.insert(into: context)
            try? context.save()
            onAdded(newCustomUnit)
        }
    }
}

// How an ingestion of a few of the new units will read
struct IngestionRowPreview: View {
    let substanceName: String
    let administrationRoute: AdministrationRoute
    let isEstimate: Bool
    let unit: String
    let unitPlural: String
    let dosePerUnit: Double?
    let dosePerUnitStandardDeviation: Double?
    let originalUnit: String
    let name: String

    private let multiplier: Double = 3

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(PersistenceController.shared.displayName(for: substanceName)), \(name)").font(.headline)
            let units = multiplier.with(pluralizableUnit: PluralizableUnit(singular: unit, plural: unitPlural))
            if let dosePerUnit {
                // The number of units is exact, so the deviation scales with it
                let dose = (multiplier * dosePerUnit).doseDescription(
                    units: originalUnit,
                    isEstimate: isEstimate,
                    standardDeviation: dosePerUnitStandardDeviation.map { multiplier * $0 },
                    rounded: true
                )
                Text(units) + Text(" = \(dose) \(administrationRoute.rawValue)").foregroundColor(.secondary)
            } else {
                Text("\(units) \(administrationRoute.rawValue)")
            }
        }
    }
}


#Preview {
    NavigationStack {
        FinishCustomUnitsScreen(
            arguments: SubstanceAndRoute(
                substance: .psychonautWiki(SubstanceRepo.shared.getSubstance(name: "MDMA")!),
                administrationRoute: .oral),
            cancel: {},
            onAdded: { _ in })
    }
}
