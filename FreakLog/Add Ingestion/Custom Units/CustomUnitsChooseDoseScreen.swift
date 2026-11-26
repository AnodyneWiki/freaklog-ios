import SwiftUI

struct CustomUnitsChooseDoseScreen: View {
    @ObservedObject var customUnit: CustomUnit
    let dismiss: () -> Void
    let navigateToCustomUnitChooseDose: (CustomUnit) -> Void
    let showsProductLink: Bool
    let requiresDose: Bool

    init(
        customUnit: CustomUnit,
        dismiss: @escaping () -> Void,
        navigateToCustomUnitChooseDose: @escaping (CustomUnit) -> Void,
        initialDose: Double? = nil,
        showsProductLink: Bool = true,
        requiresDose: Bool = false
    ) {
        self.customUnit = customUnit
        self.dismiss = dismiss
        self.navigateToCustomUnitChooseDose = navigateToCustomUnitChooseDose
        self.showsProductLink = showsProductLink
        self.requiresDose = requiresDose
        _dose = State(initialValue: initialDose)
    }

    @State private var isAddCustomUnitSheetShown = false

    @State private var dose: Double?
    @State private var isEstimate = false
    @State private var estimatedDoseStandardDeviation: Double?
    @FocusState private var isDoseFieldFocused: Bool
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen = false

    var body: some View {
        Form {
            Section("Pure \(customUnit.administrationRouteUnwrapped.rawValue.capitalized) Dose") {
                VStack(alignment: .leading, spacing: 8) {
                    if let roaDose = customUnit.roaDose {
                        RoaDoseRow(roaDose: roaDose)
                    }
                    CustomUnitCalculationText(
                        customUnit: customUnit,
                        dose: dose,
                        isEstimate: isEstimate,
                        estimatedDoseStandardDeviation: estimatedDoseStandardDeviation)
                    if !(customUnit.substance?.isApproved ?? true) {
                        Text("Info is not approved by the moderators of the data source.")
                    }
                }
            }.listRowSeparator(.hidden)
            Section {
                CustomUnitDosePicker(
                    customUnit: customUnit,
                    dose: $dose,
                    isEstimate: $isEstimate,
                    estimatedDoseStandardDeviation: $estimatedDoseStandardDeviation
                ).focused($isDoseFieldFocused)
            } header: {
                Text(customUnit.nameUnwrapped)
            } footer: {
                if !customUnit.noteUnwrapped.isEmpty {
                    Text(customUnit.noteUnwrapped)
                }
            }
            if isEyeOpen {
                Section {
                    if showsProductLink {
                        NavigationLink {
                            ProductDetailScreen(product: .customUnit(customUnit), allowsLogging: false)
                        } label: {
                            Label("View Product", systemImage: "shippingbox")
                        }
                    }
                    Button("Add new custom unit") {
                        isAddCustomUnitSheetShown = true
                    }
                }
                Section {
                    if let remark = customUnit.substance?.dosageRemark {
                        Text(remark)
                            .foregroundColor(.secondary)
                    }
                    if customUnit.administrationRouteUnwrapped == .smoked || customUnit.administrationRouteUnwrapped == .inhaled {
                        Text(
                            "Depending on your smoking/inhalation method different amounts of substance are lost before entering the body. The dose should reflect the amount of substance that is actually inhaled.")
                    }
                    if customUnit.roaDose?.shouldUseVolumetricDosing ?? false {
                        NavigationLink("Volumetric Dosing Recommended") {
                            VolumetricDosingScreen()
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: FinishIngestionScreenArguments(
                    substanceName: customUnit.substanceNameUnwrapped,
                    administrationRoute: customUnit.administrationRouteUnwrapped,
                    dose: dose,
                    units: customUnit.originalUnitUnwrapped,
                    isEstimate: isEstimate,
                    estimatedDoseStandardDeviation: estimatedDoseStandardDeviation,
                    customUnit: customUnit))
                {
                    NextLabel()
                }
                .disabled(requiresDose && dose.map { $0.isFinite && $0 > 0 } != true)
            }
        }
        .onAppear {
            isDoseFieldFocused = true
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $isAddCustomUnitSheetShown, content: {
                    NavigationStack {
                        FinishCustomUnitsScreen(
                            arguments: customUnitArguments,
                            cancel: {
                                isAddCustomUnitSheetShown = false
                            },
                            onAdded: { customUnit in
                                isAddCustomUnitSheetShown = false
                                navigateToCustomUnitChooseDose(customUnit)
                            })
                    }
                })
        .navigationBarTitle("\(customUnit.substanceDisplayName) Dose")
    }

    // A new unit made from here is for the same substance and route
    var customUnitArguments: SubstanceAndRoute {
        SubstanceAndRoute(
            substance: AddIngestionSubstance(storedName: customUnit.substanceNameUnwrapped, units: customUnit.originalUnitUnwrapped),
            administrationRoute: customUnit.administrationRouteUnwrapped
        )
    }
}

#Preview {
    NavigationStack {
        CustomUnitsChooseDoseScreen(customUnit: CustomUnit.previewSample, dismiss: { }, navigateToCustomUnitChooseDose: {_ in })
    }
}
