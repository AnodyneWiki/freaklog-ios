import SwiftUI

struct ChooseDoseScreen: View {
  init(arguments: SubstanceAndRoute, dismiss: @escaping () -> Void, navigateToCustomUnitChooseDose: @escaping (CustomUnit) -> Void) {
    self.init(
      substanceName: arguments.substance.name,
      substance: arguments.substance,
      administrationRoute: arguments.administrationRoute,
      dismiss: dismiss,
      navigateToCustomUnitChooseDose: navigateToCustomUnitChooseDose)
  }

  init(
    arguments: CustomChooseDoseScreenArguments,
    dismiss: @escaping () -> Void,
    navigateToCustomUnitChooseDose: @escaping (CustomUnit) -> Void
  ) {
    let description = PersistenceController.shared.getCustomSubstance(name: arguments.substanceName)?.explanationUnwrapped
    self.init(
      substanceName: arguments.substanceName,
      substance: nil,
      customSubstanceDescription: description?.isEmpty == false ? description : nil,
      defaultUnits: arguments.units,
      administrationRoute: arguments.administrationRoute,
      dismiss: dismiss,
      navigateToCustomUnitChooseDose: navigateToCustomUnitChooseDose)
  }

  init(
    substanceName: String,
    substance: Substance?,
    customSubstanceDescription: String? = nil,
    defaultUnits: String = UnitPickerOptions.mg.rawValue,
    administrationRoute: AdministrationRoute,
    dismiss: @escaping () -> Void,
    navigateToCustomUnitChooseDose: @escaping (CustomUnit) -> Void
  ) {
    self.substanceName = substanceName
    self.substance = substance
    self.customSubstanceDescription = customSubstanceDescription
    self.defaultUnits = defaultUnits
    self.administrationRoute = administrationRoute
    self.dismiss = dismiss
    self.navigateToCustomUnitChooseDose = navigateToCustomUnitChooseDose
    let roaDose = PersistenceController.shared.resolvedDose(for: substanceName, route: administrationRoute)
    self.roaDose = roaDose
    _selectedUnits = State(initialValue: roaDose?.units ?? defaultUnits)
    customUnits = FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest(for: substanceName))
  }

  static let doseDisclaimer =
    "Dosage information is gathered from users and various resources. It is not a recommendation and should be verified with other sources for accuracy. Always start with lower doses due to differences between individual body weight, tolerance, metabolism, and personal sensitivity."

  let substanceName: String
  let substance: Substance?
  let customSubstanceDescription: String?
  let defaultUnits: String
  let administrationRoute: AdministrationRoute
  let dismiss: () -> Void
  let navigateToCustomUnitChooseDose: (CustomUnit) -> Void
  private let roaDose: RoaDose?
  @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
  @State private var selectedPureDose: Double?
  @State private var selectedDoseDeviation: Double?
  @State private var selectedUnits: String
  @State private var isEstimate = false

  var body: some View {
    screen.toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .primaryAction) {
        NavigationLink(value: FinishIngestionScreenArguments(
          substanceName: substanceName,
          administrationRoute: administrationRoute,
          dose: selectedPureDose,
          units: selectedUnits,
          isEstimate: isEstimate,
          estimatedDoseStandardDeviation: selectedDoseDeviation))
        {
          NextLabel()
        }
      }
    }
  }

  private var customUnits: FetchRequest<CustomUnit>

  @FocusState private var isDoseFieldFocused: Bool
  @State private var isAddCustomUnitSheetShown: Bool = false

  @State private var isDosageRemarkExpanded = false

  private var doseSection: some View {
    Section {
      VStack(alignment: .leading) {
        if let substance, !substance.isApproved {
          Text("Info is not approved by the moderators of the data source.")
        }
        let remark = substance?.dosageRemark ?? customSubstanceDescription
        if let remark {
          HStack {
            Text(remark).lineLimit(isDosageRemarkExpanded ? nil : 2)
            if !isDosageRemarkExpanded {
              Image(systemName: "chevron.down")
            }
          }
          .onTapGesture {
            withAnimation {
              isDosageRemarkExpanded.toggle()
            }
          }
        }
        if let roaDose {
          RoaDoseRow(roaDose: roaDose)
        }
        DosePicker(
          roaDose: roaDose,
          doseMaybe: $selectedPureDose,
          selectedUnits: $selectedUnits)
          .focused($isDoseFieldFocused)
          .onFirstAppear {
            isDoseFieldFocused = true
          }
        EstimateFields(
          isEstimate: $isEstimate,
          standardDeviation: $selectedDoseDeviation,
          units: selectedUnits.isEmpty ? roaDose?.units ?? defaultUnits : selectedUnits,
          mean: selectedPureDose
        )
      }
    } header: {
      Text("Pure \(administrationRoute.rawValue.capitalized) Dose")
    } footer: {
      if
        let units = roaDose?.units,
        let clarification = DosesSection.getUnitClarification(for: units)
      {
        Text(clarification)
      }
    }
    .listRowSeparator(.hidden)
  }

  var customUnitPrompt: String {
    if substanceName == "Cannabis" && administrationRoute == .smoked {
      "Prefer to log weight of bud, hash or log another unit related to joint, vaporizer or bong?"
    } else if substanceName == "Psilocybin mushrooms" {
      "Prefer to log weight of mushrooms instead of mg Psilocybin?"
    } else if substanceName == "Alcohol" {
      "Prefer to log number of drinks, beer or wine instead of g of Ethanol?"
    } else if substanceName == "Caffeine" {
      "Prefer to log coffee, tea or energy drink instead of mg Caffeine?"
    } else {
      "Prefer to use a different unit such as \(sampleUnitText)?"
    }
  }

  var sampleUnitText: String {
    switch administrationRoute {
    case .oral:
      "pills, capsules or raw powder weight"
    case .smoked:
      "hits"
    case .insufflated:
      "sprays, spoons, scoops, lines or raw powder weight"
    case .buccal:
      "pouches"
    case .transdermal:
      "patches"
    default:
      "pills, sprays, spoons or powder weight"
    }
  }

  private var customUnitArguments: CustomUnitArguments {
    if let substance {
      .substance(substance: substance, administrationRoute: administrationRoute)
    } else {
      .customSubstance(
        customSubstanceName: substanceName,
        administrationRoute: administrationRoute,
        customSubstanceUnit: defaultUnits)
    }
  }

  private var filteredCustomUnits: [CustomUnit] {
    customUnits.wrappedValue.filter { $0.administrationRouteUnwrapped == administrationRoute }
  }

  private var screen: some View {
    Form {
      doseSection
      if isEyeOpen {
        Section {
          Text(customUnitPrompt)
          Button("Add a custom unit") {
            isAddCustomUnitSheetShown.toggle()
          }
          ForEach(filteredCustomUnits) { customUnit in
            NavigationLink(value: customUnit) {
              Text("Log \(customUnit.pluralizableUnit.plural) (\(customUnit.nameUnwrapped))")
            }
          }
        }
        if substanceName == "Nicotine" {
          Section("Nicotine Content vs Dose") {
            Text(
              "The nicotine inhaled by the average smoker per cigarette is indicated on the package. The nicotine content of the cigarette itself is much higher as on average only about 10% of the cigarette's nicotine is inhaled.\nMore nicotine is inhaled when taking larger and more frequent puffs or by blocking the cigarette filter ventilation holes.\nNicotine yields from electronic cigarettes are also highly correlated with the device type and brand, liquid nicotine concentration, and PG/VG ratio, and to a lower significance with electrical power. Nicotine yields from 15 puffs may vary 50-fold.")
          }
        }
        if administrationRoute == .smoked, substance?.categories.contains("opioid") == true {
          ChasingTheDragonSection()
        }
        let isSmokedRoute = administrationRoute == .smoked || administrationRoute == .inhaled
        let shouldUseVolumetricDosing = roaDose?.shouldUseVolumetricDosing ?? false
        if isSmokedRoute || shouldUseVolumetricDosing {
          Section("Info") {
            if isSmokedRoute {
              Text(
                "Depending on your smoking/inhalation method different amounts of substance are lost before entering the body. The dosage should reflect the amount of substance that is actually inhaled.")
            }
            if shouldUseVolumetricDosing {
              NavigationLink("Volumetric Dosing Recommended") {
                VolumetricDosingScreen()
              }
            }
          }
        }
        Section("Disclaimer") {
          Text(Self.doseDisclaimer)
        }
      }
    }
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
    .scrollDismissesKeyboard(.interactively)
    .navigationBarTitle("\(substanceName) Dose")
  }
}

#Preview {
  NavigationStack {
    ChooseDoseScreen(
      substanceName: "Amphetamine",
      substance: SubstanceRepo.shared.getSubstance(name: "Amphetamine")!,
      administrationRoute: .oral,
      dismiss: {},
      navigateToCustomUnitChooseDose: { _ in })
  }
}
