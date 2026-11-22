import SwiftUI

struct DurationSection: View {

    let substance: Substance
    // AnodyneWiki's duration of action and half-life, shown below the routes
    let anodyne: AnodyneSubstance?

    @FetchRequest private var customRoas: FetchedResults<CustomRoa>

    init(substance: Substance, anodyne: AnodyneSubstance? = nil) {
        self.substance = substance
        self.anodyne = anodyne
        _customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substance.name))
    }

    // PW routes first, then routes that only have custom data or AnodyneWiki timings, each with custom data
    // taking priority and AnodyneWiki's timings filling in where neither has any.
    private var durationInfos: [DurationInfo] {
        let pwRoutes = substance.roas.map(\.name)
        let customRoutes = customRoas.map(\.administrationRouteUnwrapped).filter { !pwRoutes.contains($0) }
        let anodyneRoutes = AnodyneTimingStore.shared.routesWithTimings(for: substance.name)
        return (pwRoutes + customRoutes + anodyneRoutes).uniqued().compactMap { route in
            PersistenceController.shared.resolvedDuration(for: substance.name, route: route).map {
                DurationInfo(route: route, roaDuration: $0)
            }
        }
    }

    @State private var selectedTime = Date()
    @State private var timelineModel: TimelineModel?
    @State private var hiddenRoutes: [AdministrationRoute] = []

    var body: some View {
        Group {
            if let timelineModel { // have the if let here instead of in the section because the height of the item in the section is fixed when its first rendered
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            DatePicker(
                                "Start Time",
                                selection: $selectedTime,
                                displayedComponents: [.hourAndMinute]
                            )
                            Button("Now") {
                                selectedTime = .now
                            }
                            .buttonStyle(.bordered)
                        }
                        EffectTimeline(
                            timelineModel: timelineModel,
                            timeDisplayStyle: .relativeToNow
                        )
                        Text(TimelineDisclaimers.heavyDose).font(.footnote)
                    }
                    listItems
                } header: {
                    HStack {
                        Text("Duration")
                        Spacer()
                        NavigationLink(value: GlobalNavigationDestination.timelineInfo) {
                            Label("Info", systemImage: "info.circle").labelStyle(.iconOnly)
                        }
                    }
                }
            } else {
                Section("Duration") {
                    listItems
                }
            }
        }
        .onAppear {
            updateModel()
        }
        .onChange(of: selectedTime) { _ in
            updateModel()
        }
        .onChange(of: hiddenRoutes) { _ in
            updateModel()
        }
        .onChange(of: durationInfos) { _ in
            updateModel()
        }

    }

    @ViewBuilder
    private var listItems: some View {
        ForEach(durationInfos, id: \.route) { info in
            let isRouteHidden = hiddenRoutes.contains(info.route)
            HStack(alignment: .center, spacing: 8) {
                if isRouteHidden {
                    Label("Hidden", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
                }
                ColorRectangle(color: info.route.color.swiftUIColor)
                VStack(alignment: .leading) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(info.route.rawValue.localizedCapitalized).font(.headline)
                        if PersistenceController.shared.isDurationFromAnodyneWiki(for: substance.name, route: info.route) {
                            Text("AnodyneWiki")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    OneRoaDurationRow(duration: info.roaDuration, color: info.route.color)
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    toggle(route: info.route)
                } label: {
                    if isRouteHidden {
                        Label("Show", systemImage: "eye.fill").labelStyle(.iconOnly)
                    } else {
                        Label("Hide", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
                    }
                }
            }
        }
        if let anodyne {
            AnodyneDurationRows(anodyne: anodyne)
        }
    }

    private func updateModel() {
        let durationsToShow = durationInfos.filter { info in
            !hiddenRoutes.contains(info.route)
        }
        let firstAverageCommonDose = substance.doseInfos.compactMap { dose in
            dose.roaDose.averageCommonDose
        }.first ?? 100
        timelineModel = TimelineModel(
            substanceGroups: durationsToShow.map { info in
                SubstanceIngestionGroup(
                    substanceName: substance.name,
                    color: info.route.color,
                    routeMinInfos: [
                        RouteMinInfo.resolved(
                            substanceName: substance.name,
                            route: info.route,
                            ingestions: [
                                IngestionMinInfo(
                                    dose: substance.doseInfos.first(where: { $0.route == info.route})?.roaDose.getStrengthRelativeToCommonDose(dose: firstAverageCommonDose),
                                    time: selectedTime,
                                    endTime: nil,
                                    onsetDelayInHours: 0
                                ),
                            ]
                        ),
                    ]
                )
            },
            everythingForEachRating: [],
            everythingForEachTimedNote: [],
            areRedosesDrawnIndividually: true,
            areSubstanceHeightsIndependent: false
        )
    }

    private func toggle(route: AdministrationRoute) {
        if hiddenRoutes.contains(route) {
            hiddenRoutes.removeAll { sel in
                sel == route
            }
        } else {
            hiddenRoutes.append(route)
        }
    }
}

#Preview {
    List {
        let substance = SubstanceRepo.shared.getSubstance(name: "4-HO-MET")!
        DurationSection(substance: substance)
    }
}
