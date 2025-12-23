import SwiftUI

struct DurationSection: View {

    let substance: Substance

    @State private var selectedTime = Date()
    @State private var timelineModel: TimelineModel?
    @State private var hiddenRoutes: [AdministrationRoute] = []

    @AppStorage(PersistenceController.timeDisplayStyleDurationSectionKey) private var timeDisplayStyleDurationSectionText: String = SaveableTimeDisplayStyle.auto.rawValue

    private var saveableTimeDisplayStyle: SaveableTimeDisplayStyle {
        SaveableTimeDisplayStyle(rawValue: timeDisplayStyleDurationSectionText) ?? .auto
    }

    var timeDisplayStyle: TimeDisplayStyle {
        switch saveableTimeDisplayStyle {
        case .regular:
            return .regular
        case .relativeToNow, .auto, .relativeToStart, .between:
            return .relativeToNow
        }
    }

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
                            timeDisplayStyle: timeDisplayStyle
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

    }

    private var listItems: some View {
        ForEach(substance.durationInfos, id: \.route) { info in
            let isRouteHidden = hiddenRoutes.contains(info.route)
            HStack(alignment: .center, spacing: 8) {
                if isRouteHidden {
                    Label("Hidden", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
                }
                ColorRectangle(color: info.route.color.swiftUIColor)
                VStack(alignment: .leading) {
                    Text(info.route.rawValue.localizedCapitalized).font(.headline)
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
    }

    private func updateModel() {
        let durationsToShow = substance.durationInfos.filter { info in
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
                        RouteMinInfo(
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
