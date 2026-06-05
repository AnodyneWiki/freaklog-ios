import SwiftUI

struct ServerLeaderboardScreen: View {
  let serverID: UUID
  @EnvironmentObject var store: LeaderboardServerStore
  @ObservedObject var syncManager = LeaderboardSyncManager.shared
  @State private var groups: [LeaderboardSubstanceGroup] = []
  @State private var loading = false
  @State private var errorMessage: String?
  @State private var expandedSubstance: String?

  private var server: LeaderboardServer? {
    store.servers.first { $0.id == serverID }
  }

  private var filteredLog: [SyncLogEntry] {
    guard let nickname = server?.nickname else { return [] }
    return syncManager.log
      .filter { $0.serverNickname == nickname }
      .prefix(20)
      .map { $0 }
  }

  var body: some View {
    List {
      if loading {
        ProgressView()
          .frame(maxWidth: .infinity, alignment: .center)
      } else if let error = errorMessage {
        Text(error)
          .foregroundStyle(.red)
      } else if groups.isEmpty {
        Text("No data yet")
          .foregroundStyle(.secondary)
      } else {
        Section("Leaderboard") {
          ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            substanceGroupRow(rank: index + 1, group: group)
          }
        }
      }
      if !filteredLog.isEmpty {
        Section("Sync Log") {
          ForEach(filteredLog) { entry in
            HStack(alignment: .top, spacing: 8) {
              if entry.isError {
                Image(systemName: "exclamationmark.circle.fill")
                  .foregroundStyle(.red)
                  .font(.caption)
              } else {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption)
              }
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                  .font(.caption)
                Text(entry.date, style: .relative)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle(server?.nickname ?? "Leaderboard")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        HStack {
          Button {
            Task { await syncManager.syncAll() }
          } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
              .rotationEffect(.degrees(syncManager.syncing ? 360 : 0))
              .animation(
                syncManager.syncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                value: syncManager.syncing
              )
          }
          Button {
            Task { await loadLeaderboard() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }
    .task { await loadLeaderboard() }
  }

  @ViewBuilder
  private func substanceGroupRow(rank: Int, group: LeaderboardSubstanceGroup) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation {
          if expandedSubstance == group.substance {
            expandedSubstance = nil
          } else {
            expandedSubstance = group.substance
          }
        }
      } label: {
        HStack {
          Text("\(rank).")
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(width: 28, alignment: .leading)
          VStack(alignment: .leading, spacing: 2) {
            Text(group.substance)
              .font(.headline)
              .foregroundStyle(.primary)
            Text("\(formattedDose(group.totalDose)) \(group.units)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if group.hasHeavy {
            Text("H")
              .font(.caption2.bold())
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(tierColor("heavy").opacity(0.2))
              .foregroundStyle(tierColor("heavy"))
              .clipShape(RoundedRectangle(cornerRadius: 4))
          }
          Image(systemName: expandedSubstance == group.substance ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      if expandedSubstance == group.substance {
        ForEach(group.entries, id: \.Id) { entry in
          entryRow(entry)
        }
      }
    }
  }

  @ViewBuilder
  private func entryRow(_ entry: LeaderboardEntryPayload) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.Nickname)
          .font(.subheadline)
          .fontWeight(.medium)
        Text("\(formattedDose(entry.Ingestion.Dose)) \(entry.Ingestion.Units) \u{2022} \(entry.Ingestion.AdministrationRoute)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if let normalized = entry.Normalized {
        Text(normalized.Tier)
          .font(.caption2.bold())
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(tierColor(normalized.Tier).opacity(0.2))
          .foregroundStyle(tierColor(normalized.Tier))
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
    }
    .padding(.leading, 36)
  }

  private func loadLeaderboard() async {
    guard let server else { return }
    loading = true
    defer { loading = false }
    errorMessage = nil
    let result = await LeaderboardClient.shared.fetchLeaderboard(baseURL: server.endpoint)
    switch result {
    case .success(let response):
      groups = groupLeaderboard(response)
    case .failure(let error):
      errorMessage = error.localizedDescription
    }
  }

  private func formattedDose(_ dose: Double) -> String {
    if dose == dose.rounded() {
      return String(Int(dose))
    }
    return String(format: "%.1f", dose)
  }

  private func tierColor(_ tier: String) -> Color {
    switch tier.lowercased() {
    case "threshold": return Color(red: 0.2, green: 0.82, blue: 1.0)
    case "light": return Color(red: 0.19, green: 0.82, blue: 0.35)
    case "common": return Color(red: 1.0, green: 0.84, blue: 0.04)
    case "strong": return Color(red: 1.0, green: 0.62, blue: 0.04)
    case "heavy": return Color(red: 1.0, green: 0.27, blue: 0.23)
    default: return Color.secondary
    }
  }
}
