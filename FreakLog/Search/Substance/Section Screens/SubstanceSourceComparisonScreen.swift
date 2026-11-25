import CoreData
import SwiftUI

struct SubstanceSourceComparisonLink: View {
  let substanceName: String
  var psychonautWiki: Substance?
  let anodyne: AnodyneSubstance?
  let isMissingOnAnodyne: Bool

  var body: some View {
    Section {
      NavigationLink {
        SubstanceSourceComparisonScreen(
          substanceName: substanceName,
          psychonautWiki: psychonautWiki,
          anodyne: anodyne,
          isMissingOnAnodyne: isMissingOnAnodyne
        )
      } label: {
        Label("Compare Sources", systemImage: "list.bullet.rectangle")
      }
    }
  }
}

private struct SubstanceSourceComparisonScreen: View {
  let psychonautWiki: Substance?
  let loadedAnodyne: AnodyneSubstance?
  let loadedInstance: URL
  let isMissingOnAnodyne: Bool

  @AppStorage(PersistenceController.anodyneInstanceURLKey) private var instanceURL = ""
  @FetchRequest private var customRoas: FetchedResults<CustomRoa>
  @State private var selectedRoute: AdministrationRoute?

  init(substanceName: String, psychonautWiki: Substance?, anodyne: AnodyneSubstance?, isMissingOnAnodyne: Bool) {
    self.psychonautWiki = psychonautWiki
    loadedAnodyne = anodyne
    loadedInstance = AnodyneSubstance.baseURL
    self.isMissingOnAnodyne = isMissingOnAnodyne
    _customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substanceName))
  }

  private var isCurrentInstance: Bool {
    (AnodyneSubstance.instanceURL(from: instanceURL) ?? AnodyneSubstance.defaultBaseURL) == loadedInstance
  }

  private var anodyne: AnodyneSubstance? {
    isCurrentInstance ? loadedAnodyne : nil
  }

  private var routes: [AdministrationRoute] {
    let wikiRoutes = (psychonautWiki?.doseInfos.map(\.route) ?? []) + (psychonautWiki?.durationInfos.map(\.route) ?? [])
    let otherRoutes = anodyne.map {
      $0.dosing.compactMap(\.route) + AnodyneFallbackStore.shared.routesWithTimings(for: $0.title)
    } ?? []
    let personalRoutes = customRoas.map(\.administrationRouteUnwrapped)
    let routesWithData = Set(wikiRoutes + otherRoutes + personalRoutes)
    return AdministrationRoute.allCases.filter(routesWithData.contains)
  }

  var body: some View {
    let routes = routes
    List {
      if let route = selectedRoute.flatMap({ routes.contains($0) ? $0 : nil }) ?? routes.first {
        Section {
          if routes.count > 1 {
            Picker("Route", selection: Binding(get: { route }, set: { selectedRoute = $0 })) {
              ForEach(routes) { option in
                Text(option.rawValue.localizedCapitalized).tag(option)
              }
            }
          } else {
            LabeledContent("Route", value: route.rawValue.localizedCapitalized)
          }
        }
        psychonautWikiSection(for: route)
        anodyneSection(for: route)
        personalSection(for: route)
      } else {
        Text("No route-specific information available.").foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Compare Sources")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func psychonautWikiSection(for route: AdministrationRoute) -> some View {
    Section("PsychonautWiki") {
      if let wiki = psychonautWiki {
        doseRows(wiki.getDose(for: route))
        durationRows(wiki.getDuration(for: route))
        Link(destination: wiki.url) {
          Label("Open PsychonautWiki", systemImage: "arrow.up.right.square")
        }
      } else {
        Text("No PsychonautWiki entry is linked.").foregroundStyle(.secondary)
      }
    }
  }

  private func anodyneSection(for route: AdministrationRoute) -> some View {
    Section {
      if let anodyne {
        let doses = anodyne.dosing.filter { $0.route == route }
        if doses.isEmpty {
          Text("No dose data for this route.").foregroundStyle(.secondary)
        }
        ForEach(doses, id: \.self) { dose in
          if doses.count > 1 {
            Text(dose.method).font(.headline)
          }
          anodyneDoseRows(dose)
        }
        let timings = AnodyneFallbackStore.shared
        if timings.routesWithTimings(for: anodyne.title).contains(route) {
          durationRows(timings.duration(for: anodyne.title, route: route))
          Text("Route timings are from user notes.").font(.footnote).foregroundStyle(.secondary)
        } else {
          durationRows(nil)
        }
        if let duration = anodyne.durationOfAction {
          LabeledContent("General Duration", value: duration)
        }
        Link(destination: AnodyneSubstance.pageURL(for: anodyne.title, at: loadedInstance)) {
          Label("Open AnodyneWiki", systemImage: "arrow.up.right.square")
        }
      } else {
        Text(isMissingOnAnodyne && isCurrentInstance
          ? "No matching AnodyneWiki page."
          : "Load AnodyneWiki from the Sources menu to compare its data.")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("AnodyneWiki")
    } footer: {
      if anodyne?.dosing.contains(where: { $0.route == route }) == true {
        Text(AnodyneDosingRow.disclaimer)
      }
    }
  }

  private func personalSection(for route: AdministrationRoute) -> some View {
    Section("Personal Overrides") {
      let overrides = customRoas.filter { $0.administrationRouteUnwrapped == route && !$0.values.isEmpty }
      if overrides.isEmpty {
        Text("No personal overrides for this route.").foregroundStyle(.secondary)
      }
      ForEach(overrides, id: \.objectID) { override in
        let values = override.values
        let dose = override.roaDose
        if dose == nil, CustomRoaField.doseFields.contains(where: { values[$0] != nil }) {
          doseRows(RoaDose(
            units: "",
            lightMin: values.lightDose,
            commonMin: values.commonDose,
            strongMin: values.strongDose,
            heavyMin: values.heavyDose
          ))
        } else {
          doseRows(dose)
        }
        if dose != nil, values.doseUnits?.isEmpty != false {
          Text("Dose unit inherited from the substance.").font(.footnote).foregroundStyle(.secondary)
        }
        durationRows(override.roaDuration)
      }
    }
  }

  @ViewBuilder
  private func doseRows(_ dose: RoaDose?) -> some View {
    if let dose {
      let starts = [("Light", dose.lightMin), ("Common", dose.commonMin), ("Strong", dose.strongMin), ("Heavy", dose.heavyMin)]
      ForEach(starts, id: \.0) { label, start in
        LabeledContent("\(label) Starts At", value: start.map { doseText($0.formatted(), unit: dose.units) } ?? "Unavailable")
      }
    } else {
      Text("No dose data for this route.").foregroundStyle(.secondary)
    }
  }

  private func anodyneDoseRows(_ dose: AnodyneSubstance.Dosing) -> some View {
    let tiers = [
      ("Light", dose.light, "≤"),
      ("Common", dose.common, ""),
      ("Strong", dose.strong, ""),
      ("Heavy", dose.heavy, ""),
      ("Extreme", dose.extreme, "≥"),
    ]
    return ForEach(tiers, id: \.0) { label, tier, bound in
      LabeledContent(label, value: tier.map { tier in
        let value = switch bound {
        case "≤": "≤\(tier.upper.formatted())"
        case "≥": "≥\(tier.lower.formatted())"
        default: tier.lower == tier.upper ? tier.lower.formatted() : "\(tier.lower.formatted())–\(tier.upper.formatted())"
        }
        return doseText(value, unit: tier.unit)
      } ?? "Unavailable")
    }
  }

  @ViewBuilder
  private func durationRows(_ duration: RoaDuration?) -> some View {
    if let duration {
      ForEach(DurationPhase.allCases, id: \.self) { phase in
        LabeledContent(phase.title, value: phase.range(in: duration)?.displayString ?? "Unavailable")
      }
    } else {
      Text("No duration data for this route.").foregroundStyle(.secondary)
    }
  }

  private func doseText(_ value: String, unit: String) -> String {
    unit.isEmpty ? "\(value) (unit unavailable)" : "\(value) \(unit)"
  }
}
