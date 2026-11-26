import SwiftUI

struct SprayCalculatorScreen: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        Form {
            spraysSection
            inputsSection
            resultSection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Spray Calculator")
        .toolbar {
            if !viewModel.sprayModels.isEmpty {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .sheet(isPresented: $viewModel.isShowingAddSpray) {
            AddSprayScreen()
        }
        .alert("Spray Calculator", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var spraysSection: some View {
        Section("Spray") {
            ForEach(viewModel.sprayModels) { model in
                Button {
                    viewModel.select(model)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.name).foregroundStyle(.primary)
                            if model.isValid {
                                Text("\(model.contentInMl.asRoundedReadableString) mL · \(model.numSprays.asRoundedReadableString) sprays")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Invalid volume or spray count")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if viewModel.selectedSpray?.id == model.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .disabled(!model.isValid)
                .accessibilityAddTraits(viewModel.selectedSpray?.id == model.id ? .isSelected : [])
            }
            .onDelete(perform: viewModel.deleteSprays)

            Button {
                viewModel.isShowingAddSpray = true
            } label: {
                Label("Add Spray", systemImage: "plus")
            }
        }
    }

    private var inputsSection: some View {
        Section {
            Picker("Calculate", selection: Binding(
                get: { viewModel.calculation },
                set: viewModel.selectCalculation
            )) {
                Text("Solute Weight").tag(SprayCalculation.soluteWeight)
                Text("Liquid Volume").tag(SprayCalculation.liquidVolume)
            }

            Picker("Weight Unit", selection: $viewModel.units) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }

            quantityInput("Weight per Spray", placeholder: "Weight", unit: viewModel.units.rawValue,
                          text: $viewModel.weightPerSprayText)

            if viewModel.calculation == .soluteWeight {
                quantityInput("Liquid Volume", placeholder: "Volume", unit: "mL", text: $viewModel.knownQuantityText)
            } else {
                quantityInput("Solute Weight", placeholder: "Weight", unit: viewModel.units.rawValue,
                              text: $viewModel.knownQuantityText)
            }
            quantityInput("Purity (Optional)", placeholder: "Purity", unit: "%", text: $viewModel.purityInPercentText)
        } header: {
            Text("Inputs")
        } footer: {
            if !viewModel.purityInPercentText.isEmpty, viewModel.purity == nil {
                Text("Enter a purity greater than 0% and no greater than 100%.")
            }
            if (!viewModel.weightPerSprayText.isEmpty && viewModel.weightPerSpray == nil)
                || (!viewModel.knownQuantityText.isEmpty && viewModel.knownQuantity == nil) {
                Text("Enter amounts greater than zero.")
            }
        }
    }

    private var resultSection: some View {
        Section("Result") {
            if let result = viewModel.result {
                if viewModel.calculation == .soluteWeight {
                    resultRow("Solute Weight", value: result, unit: viewModel.units.rawValue)
                } else {
                    resultRow("Liquid Volume", value: result, unit: "mL")
                }
                if let adjusted = viewModel.adjustedWeight {
                    resultRow("Weight Adjusted for Purity", value: adjusted, unit: viewModel.units.rawValue)
                }
            } else if viewModel.selectedSpray == nil {
                Text("Choose a calibrated spray to calculate a result.")
                    .foregroundStyle(.secondary)
            } else if viewModel.knownQuantity != nil, viewModel.weightPerSpray != nil {
                Text("These amounts are outside the calculator’s supported range.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter the weight per spray and the known amount.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quantityInput(
        _ label: LocalizedStringKey, placeholder: LocalizedStringKey, unit: String, text: Binding<String>
    ) -> some View {
        LabeledContent {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(label))
            Text(unit).foregroundStyle(.secondary)
        } label: {
            Text(label)
        }
    }

    private func resultRow(_ label: LocalizedStringKey, value: Double, unit: String) -> some View {
        LabeledContent {
            Text("\(value.asRoundedReadableString) \(unit)").monospacedDigit()
        } label: {
            Text(label)
        }
    }
}

#Preview {
    NavigationStack {
        SprayCalculatorScreen()
    }
}
