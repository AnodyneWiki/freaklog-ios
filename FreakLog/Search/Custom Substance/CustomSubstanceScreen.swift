import SwiftUI

struct CustomSubstanceScreen: View {
  @ObservedObject var customSubstance: CustomSubstance
  @State private var isEditSheetShown = false
  @State private var isShowingAddIngestionSheet = false

  private var roasWithData: [CustomRoa] {
    customSubstance.customRoasSorted.filter { $0.roaDose != nil || $0.roaDuration != nil }
  }

  var body: some View {
    List {
      if !customSubstance.explanationUnwrapped.isEmpty {
        Section("About") {
          Text(customSubstance.explanationUnwrapped)
        }
      }
      if !customSubstance.unitsUnwrapped.isEmpty {
        Section("Default Units") {
          Text(customSubstance.unitsUnwrapped)
            .foregroundStyle(.secondary)
        }
      }
      if roasWithData.isEmpty {
        Section {
          Text("No dose or duration data added yet. Tap the edit button to add data for each route.")
            .foregroundStyle(.secondary)
            .font(.subheadline)
        } header: {
          Text("Data")
        }
      } else {
        ForEach(roasWithData, id: \.objectID) { roa in
          CustomSubstanceRoaSection(roa: roa)
        }
      }
    }
    .navigationTitle(customSubstance.nameUnwrapped)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isEditSheetShown = true
        } label: {
          Label("Edit", systemImage: "pencil")
        }
      }
    }
    .sheet(isPresented: $isEditSheetShown) {
      NavigationStack {
        EditCustomSubstanceView(customSubstance: customSubstance)
      }
    }
  }
}

private struct CustomSubstanceRoaSection: View {
  @ObservedObject var roa: CustomRoa
  @State private var selectedTime = Date()
  @State private var timelineModel: TimelineModel?

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        if let roaDose = roa.roaDose {
          RoaDoseRow(roaDose: roaDose)
        }
        if let roaDuration = roa.roaDuration {
          OneRoaDurationRow(duration: roaDuration, color: roa.administrationRouteUnwrapped.color)
        }
        if let model = timelineModel, model.isWorthDrawing {
          Divider()
          HStack {
            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
              .labelsHidden()
            Button("Now") { selectedTime = .now }.buttonStyle(.bordered)
          }
          EffectTimeline(timelineModel: model, timeDisplayStyle: .relativeToNow)
        }
      }
    } header: {
      Text(roa.administrationRouteUnwrapped.rawValue.localizedCapitalized)
    }
    .onAppear { updateTimeline() }
    .onChange(of: selectedTime) { _ in updateTimeline() }
    .onChange(of: roa.onsetLow) { _ in updateTimeline() }
    .onChange(of: roa.peakLow) { _ in updateTimeline() }
    .onChange(of: roa.totalLow) { _ in updateTimeline() }
  }

  private func updateTimeline() {
    guard roa.roaDuration != nil else {
      timelineModel = nil
      return
    }
    let route = roa.administrationRouteUnwrapped
    let substanceName = roa.substanceName ?? roa.customSubstance?.nameUnwrapped ?? "Custom"
    timelineModel = TimelineModel(
      substanceGroups: [SubstanceIngestionGroup(
        substanceName: substanceName,
        color: route.color,
        routeMinInfos: [RouteMinInfo(
          route: route,
          ingestions: [IngestionMinInfo(dose: nil, time: selectedTime, endTime: nil, onsetDelayInHours: 0)]
        )]
      )],
      everythingForEachRating: [],
      everythingForEachTimedNote: [],
      areRedosesDrawnIndividually: true,
      areSubstanceHeightsIndependent: false
    )
  }
}
