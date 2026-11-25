import AlertToast
import SwiftUI
import AppIntents

struct ChooseSubstanceScreen: View {
    private let usesShortcutPrefill: Bool
    @StateObject private var viewModel = ViewModel()
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var locationManager: LocationManager

    init(usesShortcutPrefill: Bool = true) {
        self.usesShortcutPrefill = usesShortcutPrefill
    }

    var body: some View {
        let prefill = usesShortcutPrefill ? Navigator.shared.ingestionPrefill : nil
        let matchedSubstance = prefill?.matchSubstance(in: viewModel.customSubstanceModels, isEyeOpen: viewModel.isEyeOpen)
        ChooseSubstanceContent(
            searchText: $viewModel.searchText,
            isShowingOpenEyeToast: $viewModel.isShowingOpenEyeToast,
            isEyeOpen: viewModel.isEyeOpen,
            filteredSuggestions: viewModel.filteredSuggestions,
            filteredSubstances: viewModel.filteredSubstances,
            filteredCustomUnits: viewModel.filteredCustomUnits,
            filteredFormulations: viewModel.filteredFormulations,
            filteredCustomSubstances: viewModel.filteredCustomSubstances,
            allowsPackageScan: usesShortcutPrefill && prefill == nil,
            prefill: prefill,
            matchedSubstance: matchedSubstance,
            dismiss: { dismiss() }).task {
                locationManager.maybeRequestLocation() // because we might need current location on finish screen
            }
            .environment(\.ingestionPrefillNote, prefill?.note)
    }
}

struct ChooseSubstanceContent: View {
    @Binding var searchText: String
    @Binding var isShowingOpenEyeToast: Bool
    let isEyeOpen: Bool
    let filteredSuggestions: [any SuggestionProtocol]
    let filteredSubstances: [Substance]
    let filteredCustomUnits: [CustomUnit]
    let filteredFormulations: [Formulation]
    let filteredCustomSubstances: [CustomSubstanceModel]
    let allowsPackageScan: Bool
    var prefill: IngestionPrefill? = nil
    var matchedSubstance: AddIngestionSubstance? = nil
    let dismiss: () -> Void

    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            screen.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: FinishIngestionScreenArguments.self) { arguments in
                FinishIngestionScreen(arguments: arguments, dismiss: dismiss)
            }
            .navigationDestination(for: Formulation.self) { formulation in
                FormulationDoseScreen(formulation: formulation, dismiss: dismiss)
            }
            .navigationDestination(for: JournalPresetProduct.self) { product in
                switch product {
                case .customUnit(let unit):
                    FinishIngestionScreen(
                        arguments: FinishIngestionScreenArguments(
                            substanceName: unit.substanceNameUnwrapped,
                            administrationRoute: unit.administrationRouteUnwrapped,
                            dose: nil,
                            units: unit.originalUnitUnwrapped,
                            isEstimate: false,
                            estimatedDoseStandardDeviation: nil,
                            customUnit: unit
                        ),
                        dismiss: dismiss
                    )
                    .environment(\.requiresIngestionAmount, true)
                case .formulation(let formulation):
                    FormulationDoseScreen(
                        formulation: formulation, dismiss: dismiss, initialAmount: nil
                    )
                }
            }
            .navigationDestination(for: FinishFormulationArguments.self) { arguments in
                FinishIngestionScreen(ingestions: arguments.ingestions, dismiss: dismiss)
            }
            .navigationDestination(for: AddIngestionDestination.self) { destination in
                switch destination {
                case .interactions(let substance):
                    AcknowledgeInteractionsView(substance: substance, dismiss: dismiss)
                case .saferUse(let substance):
                    AcknowledgeSaferUseScreen(substance: substance, dismiss: dismiss)
                case .saferRoutes:
                    SaferRoutesScreen()
                }
            }
            .navigationDestination(for: ChooseRouteScreenArguments.self, destination: { arguments in
                ChooseRouteScreen(
                    substance: arguments.substance,
                    shortcutRoute: prefill.flatMap { request in
                        request.applies(to: arguments.substance, matchedSubstance: matchedSubstance)
                            ? request.administrationRoute
                            : nil
                    },
                    dismiss: dismiss
                )
            })
            .navigationDestination(for: ChooseOtherRouteScreenArguments.self, destination: { arguments in
                ChooseOtherRouteScreen(arguments: arguments, dismiss: dismiss)
            })
            .navigationDestination(for: SubstanceAndRoute.self) { arguments in
                ChooseDoseScreen(
                    arguments: arguments,
                    dismiss: dismiss,
                    navigateToCustomUnitChooseDose: { customUnit in
                        navPath.append(customUnit)
                    },
                    shortcut: prefill?.doseEditor(for: arguments, matchedSubstance: matchedSubstance)
                )
            }
            .navigationDestination(for: CustomUnit.self) { customUnit in
                CustomUnitsChooseDoseScreen(
                    customUnit: customUnit,
                    dismiss: dismiss,
                    navigateToCustomUnitChooseDose: { navPath.append($0) },
                    initialDose: prefill?.dose(for: customUnit, matchedSubstance: matchedSubstance)
                )
            }
        }
        .onFirstAppear {
            if let matchedSubstance {
                openPrefilledSubstance(matchedSubstance)
            }
        }
        .toast(isPresenting: $isShowingOpenEyeToast, duration: 1) {
            AlertToast(
                displayMode: .alert,
                type: .image("Eye Open", .red))
        }
    }

    @State private var isShowingAddCustomSheet = false
    @AppStorage(PersistenceController.isAddIngestionSiriTipVisibleKey) private var isSiriTipVisible = false

    private func openPrefilledSubstance(_ substance: AddIngestionSubstance) {
        if !isEyeOpen {
            navPath.append(SubstanceAndRoute(substance: substance, administrationRoute: .oral))
        } else if let reference = substance.psychonautWikiSubstance {
            navPath.append(reference.saferUse.isEmpty
                ? AddIngestionDestination.interactions(substance: reference)
                : AddIngestionDestination.saferUse(substance: reference))
        } else {
            navPath.append(ChooseRouteScreenArguments(substance: substance))
        }
    }

    private var screen: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                SiriTipView(intent: AddIngestionIntent(), isVisible: $isSiriTipVisible).padding(.horizontal)
                if allowsPackageScan {
                    VStack(alignment: .leading, spacing: 8) {
                        PackageLabelDraftButton(logProduct: { navPath.append($0) })
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                if prefill?.hasSubstance == true && matchedSubstance == nil {
                    Label(
                        "Choose a substance. The shortcut’s name didn’t match one available entry.",
                        systemImage: "info.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                }
                ForEach(filteredSuggestions, id: \.id) { suggestion in
                    if let pureSubstanceSuggestions = suggestion as? PureSubstanceSuggestions {
                        PureSubstanceSuggestionView(pureSubstanceSuggestions: pureSubstanceSuggestions, isEyeOpen: isEyeOpen)
                    } else if let customUnitSuggestions = suggestion as? CustomUnitSuggestions {
                        CustomUnitSuggestionView(customUnitSuggestions: customUnitSuggestions, isEyeOpen: isEyeOpen)
                    } else if let customSubstanceSuggestions = suggestion as? CustomSubstanceSuggestions {
                        CustomSubstanceSuggestionView(customSubstanceSuggestions: customSubstanceSuggestions, isEyeOpen: isEyeOpen)
                    } else if let formulationSuggestions = suggestion as? FormulationSuggestions {
                        FormulationSuggestionView(formulationSuggestions: formulationSuggestions)
                    }
                }
                ForEach(filteredFormulations) { formulation in
                    FormulationBox(formulation: formulation)
                }
                ForEach(filteredCustomUnits) { customUnit in
                    CustomUnitBox(customUnit: customUnit)
                }
                ForEach(filteredCustomSubstances) { custom in
                    CustomSubstanceBox(
                        customSubstanceModel: custom,
                        isEyeOpen: isEyeOpen)
                }
                ForEach(filteredSubstances) { substance in
                    SubstanceBox(
                        substance: substance,
                        dismiss: dismiss,
                        isEyeOpen: isEyeOpen)
                }
                Button {
                    isShowingAddCustomSheet.toggle()
                } label: {
                    Label("New Custom Substance", systemImage: "plus.circle.fill").labelStyle(.titleAndIcon).font(.headline)
                }.padding(.horizontal)
                    .sheet(isPresented: $isShowingAddCustomSheet) {
                        AddCustomSubstanceView(searchText: searchText) { chooseRouteScreenArguments in
                            navPath.append(chooseRouteScreenArguments)
                        }
                    }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .disableAutocorrection(true)
        .navigationBarTitle("New Ingestion")
    }
}

struct IngestionPrefill {
    let substance: String?
    let route: String?
    let amount: Double?
    let unit: String?
    let time: Date?
    let note: String?

    var hasSubstance: Bool { Self.key(substance) != nil }

    var administrationRoute: AdministrationRoute? {
        Self.key(route).flatMap(AdministrationRoute.init(rawValue:))
    }

    func applies(to substance: AddIngestionSubstance, matchedSubstance: AddIngestionSubstance?) -> Bool {
        !hasSubstance || substance == matchedSubstance
    }

    private var validAmount: Double? {
        guard let amount, amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    func matchSubstance(in customSubstances: [CustomSubstanceModel], isEyeOpen: Bool) -> AddIngestionSubstance? {
        guard let name = Self.key(substance) else { return nil }
        let references = SubstanceRepo.shared.substances
        let canonicalMatches = references.filter { Self.key($0.name) == name }.map(AddIngestionSubstance.psychonautWiki)
            + customSubstances.filter { Self.key($0.name) == name }.map(\.addIngestionSubstance)
        let matches = canonicalMatches.isEmpty
            ? references.filter { reference in
                reference.commonNames.contains { Self.key($0) == name } || Self.key(reference.displayName) == name
            }.map(AddIngestionSubstance.psychonautWiki)
            : canonicalMatches
        guard matches.count == 1, let match = matches.first else { return nil }
        if let reference = match.psychonautWikiSubstance, !isEyeOpen, !namesOfLegalSubstances.contains(reference.name) {
            return nil
        }
        return match
    }

    func doseEditor(for arguments: SubstanceAndRoute, matchedSubstance: AddIngestionSubstance?) -> ShortcutDosePrefill {
        guard applies(to: arguments.substance, matchedSubstance: matchedSubstance) else {
            return ShortcutDosePrefill(message: amount == nil && unit == nil ? nil : "Choose the amount and unit for this substance.")
        }
        if Self.key(route) != nil, administrationRoute != arguments.administrationRoute {
            return ShortcutDosePrefill(message: "The shortcut’s route doesn’t match. Check the selected route and enter its amount and unit.")
        }
        guard let unitKey = Self.key(unit) else {
            return ShortcutDosePrefill(message: amount == nil ? nil : "Choose a unit before entering the shortcut’s amount.")
        }
        let knownUnits = Self.standardUnit(unitKey)
            ?? arguments.substance.customSubstanceUnits.flatMap { Self.key($0) == unitKey ? $0 : nil }
            ?? PersistenceController.shared.resolvedDose(for: arguments.substance.name, route: arguments.administrationRoute)
                .flatMap { Self.key($0.units) == unitKey ? $0.units : nil }
        if let knownUnits {
            return ShortcutDosePrefill(
                amount: validAmount,
                units: knownUnits,
                message: amount != nil && validAmount == nil ? "Enter a valid amount." : nil
            )
        }
        let customUnits = PersistenceController.shared.getActiveCustomUnits().filter {
            $0.substanceNameUnwrapped == arguments.substance.name
                && $0.administrationRoute == arguments.administrationRoute.rawValue
                && Self.matches($0, unitKey: unitKey)
        }
        if customUnits.count == 1, let customUnit = customUnits.first {
            return ShortcutDosePrefill(customUnit: customUnit)
        }
        return ShortcutDosePrefill(message: "Choose a unit. The shortcut’s unit didn’t match one available unit for this route.")
    }

    func dose(for customUnit: CustomUnit, matchedSubstance: AddIngestionSubstance?) -> Double? {
        let substance = AddIngestionSubstance(
            storedName: customUnit.substanceNameUnwrapped,
            units: customUnit.originalUnitUnwrapped
        )
        guard !hasSubstance || matchedSubstance?.name == substance.name,
              let route = AdministrationRoute(rawValue: customUnit.administrationRoute ?? ""),
              let match = doseEditor(
                for: SubstanceAndRoute(substance: matchedSubstance ?? substance, administrationRoute: route),
                matchedSubstance: matchedSubstance
              ).customUnit, match.objectID == customUnit.objectID
        else { return nil }
        return validAmount
    }

    private static func matches(_ customUnit: CustomUnit, unitKey: String) -> Bool {
        [customUnit.nameUnwrapped, customUnit.pluralizableUnit.singular, customUnit.pluralizableUnit.plural]
            .contains { key($0) == unitKey }
    }

    private static func standardUnit(_ key: String) -> String? {
        switch key {
        case "g": UnitPickerOptions.g.rawValue
        case "mg": UnitPickerOptions.mg.rawValue
        case "µg", "μg", "ug", "mcg": UnitPickerOptions.µg.rawValue
        case "ml": UnitPickerOptions.mL.rawValue
        default: nil
        }
    }

    private static func key(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value.lowercased()
    }
}

struct ShortcutDosePrefill {
    var amount: Double?
    var units: String?
    var customUnit: CustomUnit?
    var message: String?
}
