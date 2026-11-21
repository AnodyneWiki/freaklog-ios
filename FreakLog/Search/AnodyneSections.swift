import SwiftUI

// Loads a substance's AnodyneWiki data: right away when it is cached or automatic loading is on,
// otherwise only once the user asks for it.
@MainActor
final class AnodyneLoadModel: ObservableObject {
  enum Phase: Equatable {
    case idle
    case loading
    case found(AnodyneSubstance)
    case notFound
    case failed
  }

  @Published private(set) var phase = Phase.idle
  let name: String
  let otherNames: [String]

  init(name: String, otherNames: [String] = []) {
    self.name = name
    self.otherNames = otherNames
  }

  func start(loadingIfNotCached: Bool = AnodyneClient.isAutomaticLoadingEnabled) async {
    guard phase == .idle else { return }
    if let cached = await AnodyneClient.shared.cachedLookup(for: name) {
      phase = Self.makePhase(for: cached)
    } else if loadingIfNotCached {
      await load()
    }
  }

  func load() async {
    phase = .loading
    do {
      phase = Self.makePhase(for: try await AnodyneClient.shared.lookup(name, otherNames: otherNames))
    } catch {
      phase = .failed
    }
  }

  private static func makePhase(for lookup: AnodyneClient.Lookup) -> Phase {
    switch lookup {
    case let .found(substance): .found(substance)
    case .notFound: .notFound
    }
  }
}

// AnodyneWiki's dose tiers and duration for a substance, linking to everything else it has
struct AnodyneSummarySection: View {
  @StateObject private var model: AnodyneLoadModel

  init(substanceName: String, otherNames: [String] = []) {
    _model = StateObject(wrappedValue: AnodyneLoadModel(name: substanceName, otherNames: otherNames))
  }

  var body: some View {
    Section {
      switch model.phase {
      case .idle:
        Button {
          Task { await model.load() }
        } label: {
          Label("Load from AnodyneWiki", systemImage: "arrow.down.circle")
        }
      case .loading:
        HStack {
          ProgressView()
          Text("Loading from AnodyneWiki")
            .foregroundStyle(.secondary)
        }
      case .notFound:
        Text("AnodyneWiki has no page for this substance.")
          .foregroundStyle(.secondary)
      case .failed:
        Button {
          Task { await model.load() }
        } label: {
          Label("Couldn't load AnodyneWiki. Try Again", systemImage: "exclamationmark.arrow.circlepath")
        }
      case let .found(substance):
        ForEach(substance.dosing, id: \.method) { dosing in
          AnodyneDosingRow(dosing: dosing, isShowingAllTiers: false)
        }
        if let duration = substance.durationOfAction {
          LabeledText(label: "Duration", text: duration)
        }
        NavigationLink(value: GlobalNavigationDestination.anodyneSubstance(title: substance.title)) {
          Label("Everything on AnodyneWiki", systemImage: "books.vertical")
        }
      }
    } header: {
      Text("AnodyneWiki")
    } footer: {
      if case .found = model.phase {
        Text(AnodyneDosingRow.disclaimer)
      } else if model.phase == .idle {
        Text("Loads this substance from anodyne.wiki. Turn on automatic loading in Settings > AnodyneWiki.")
      }
    }
    .task {
      await model.start()
    }
  }
}

// The dose tiers of one route, from logged doses. The summary only shows the common range.
struct AnodyneDosingRow: View {
  let dosing: AnodyneSubstance.Dosing
  let isShowingAllTiers: Bool

  static let disclaimer =
    "AnodyneWiki derives dose tiers statistically from logged doses (DBI-IGS). They are averages, not recommendations."

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(dosing.route?.rawValue.localizedCapitalized ?? dosing.method)
          .font(.headline)
        Spacer()
        Text("\(dosing.totalEntries) logs")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if isShowingAllTiers {
        tierRow("Light", color: DoseRangeType.light.color, text: dosing.light.map { "up to \(amount($0.upper, $0))" })
        tierRow("Common", color: DoseRangeType.common.color, text: dosing.common.map(range))
        tierRow("Strong", color: DoseRangeType.strong.color, text: dosing.strong.map(range))
        tierRow("Heavy", color: DoseRangeType.heavy.color, text: dosing.heavy.map(range))
        tierRow("Extreme", color: .red, text: dosing.extreme.map { "\(amount($0.lower, $0)) and more" })
      } else {
        tierRow("Common", color: DoseRangeType.common.color, text: dosing.common.map(range))
      }
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private func tierRow(_ name: String, color: Color, text: String?) -> some View {
    if let text {
      HStack(spacing: 8) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(name)
        Spacer()
        Text(text)
          .foregroundStyle(.secondary)
      }
      .font(.subheadline)
    }
  }

  private func range(_ tier: AnodyneSubstance.Tier) -> String {
    tier.lower == tier.upper
      ? amount(tier.lower, tier)
      : "\(tier.lower.formatted()) – \(amount(tier.upper, tier))"
  }

  private func amount(_ value: Double, _ tier: AnodyneSubstance.Tier) -> String {
    "\(value.formatted()) \(tier.unit)"
  }
}

struct LabeledText: View {
  let label: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(text)
    }
  }
}
