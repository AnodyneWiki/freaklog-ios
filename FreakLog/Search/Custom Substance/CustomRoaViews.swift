import SwiftUI

// Every route, each linking to the editor for its custom dose & duration data.
struct CustomRoaRouteList: View {
  let substanceName: String
  var customSubstance: CustomSubstance?

  @FetchRequest private var customRoas: FetchedResults<CustomRoa>

  init(substanceName: String, customSubstance: CustomSubstance? = nil) {
    self.substanceName = substanceName
    self.customSubstance = customSubstance
    _customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substanceName))
  }

  private var routesWithPsychonautWikiData: Set<AdministrationRoute> {
    guard customSubstance == nil, let substance = SubstanceRepo.shared.getSubstance(name: substanceName) else { return [] }
    return Set(substance.administrationRoutesUnwrapped)
  }

  var body: some View {
    let routesWithPsychonautWikiData = routesWithPsychonautWikiData
    let anodyneRoutes = Set(AnodyneFallbackStore.shared.routesWithData(for: substanceName))
    ForEach(AdministrationRoute.allCases) { route in
      NavigationLink(destination: EditCustomRoaView(substanceName: substanceName, route: route, customSubstance: customSubstance)) {
        HStack {
          Text(route.rawValue.localizedCapitalized)
          Spacer()
          if customRoas.contains(where: { $0.administrationRouteUnwrapped == route && $0.hasData }) {
            Text("Custom")
              .foregroundColor(.accentColor)
          } else if routesWithPsychonautWikiData.contains(route) {
            Text("PsychonautWiki")
              .foregroundStyle(.secondary)
          } else if anodyneRoutes.contains(route) {
            Text("AnodyneWiki")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

// Dose and duration rows plus a single-ingestion timeline starting at a chosen time.
struct RoaPreview: View {
  let substanceName: String
  let route: AdministrationRoute
  let roaDose: RoaDose?
  let roaDuration: RoaDuration?

  @State private var selectedTime = Date()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let roaDose {
        RoaDoseRow(roaDose: roaDose)
      }
      if let roaDuration {
        OneRoaDurationRow(duration: roaDuration, color: route.color)
        let model = timelineModel(roaDuration: roaDuration)
        if model.isWorthDrawing {
          Divider()
          HStack {
            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
              .labelsHidden()
            Spacer()
            Button("Now") { selectedTime = .now }
              .buttonStyle(.bordered)
              .controlSize(.small)
          }
          EffectTimeline(timelineModel: model, timeDisplayStyle: .relativeToNow)
        }
      }
    }
  }

  private func timelineModel(roaDuration: RoaDuration) -> TimelineModel {
    TimelineModel(
      substanceGroups: [SubstanceIngestionGroup(
        substanceName: substanceName,
        color: route.color,
        routeMinInfos: [RouteMinInfo(
          route: route,
          ingestions: [IngestionMinInfo(dose: nil, time: selectedTime, endTime: nil, onsetDelayInHours: 0)],
          roaDuration: roaDuration
        )]
      )],
      everythingForEachRating: [],
      everythingForEachTimedNote: [],
      areRedosesDrawnIndividually: true,
      areSubstanceHeightsIndependent: false
    )
  }
}
