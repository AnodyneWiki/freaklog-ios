import SwiftUI

struct LeaderboardServersScreen: View {
  @EnvironmentObject var store: LeaderboardServerStore
  @ObservedObject var syncManager = LeaderboardSyncManager.shared
  @State private var isAddingServer = false
  @State private var serverToEdit: LeaderboardServer?

  var body: some View {
    List {
      if let error = syncManager.publicationRecordError {
        Text(error)
          .foregroundStyle(.red)
      }
      if syncManager.pendingDeletionCount > 0 {
        Section("Pending Deletions") {
          Text("\(syncManager.pendingDeletionCount) leaderboard entries to remove")
          if let error = syncManager.deletionError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
      if store.servers.isEmpty {
        Text("No servers yet. Add one to start sharing your journal.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.servers) { server in
          serverRow(server)
        }
      }
    }
    .navigationTitle("Leaderboard Servers")
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
            isAddingServer = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    }
    .sheet(isPresented: $isAddingServer) {
      NavigationStack {
        AddEditServerScreen(editingServer: nil)
          .environmentObject(store)
      }
    }
    .sheet(item: $serverToEdit) { server in
      NavigationStack {
        AddEditServerScreen(editingServer: server)
          .environmentObject(store)
      }
    }
  }

  @ViewBuilder
  private func serverRow(_ server: LeaderboardServer) -> some View {
    NavigationLink(value: GlobalNavigationDestination.serverLeaderboard(serverID: server.id)) {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(server.nickname)
            .fontWeight(.semibold)
          Spacer()
          pauseButton(server)
        }
        Text(server.endpoint)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(DeviceIdDeriver.maskedDeviceId(for: server.host))
          .font(.caption2)
          .foregroundStyle(.secondary)
        if let status = server.lastSyncStatus {
          Text(syncStatusText(server: server, status: status))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(expiryText(server: server))
          .font(.caption2)
          .foregroundStyle(server.isExpired ? .red : .secondary)
      }
      .padding(.vertical, 2)
    }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) {
        store.delete(id: server.id)
      } label: {
        Label("Delete", systemImage: "trash")
      }
      Button {
        serverToEdit = server
      } label: {
        Label("Edit", systemImage: "pencil")
      }
      .tint(.blue)
    }
  }

  @ViewBuilder
  private func pauseButton(_ server: LeaderboardServer) -> some View {
    Button {
      var updated = server
      updated.isPaused.toggle()
      store.update(updated)
    } label: {
      Image(systemName: server.isPaused ? "play.circle" : "pause.circle")
        .foregroundStyle(server.isPaused ? .green : .orange)
    }
    .buttonStyle(.plain)
  }

  private func syncStatusText(server: LeaderboardServer, status: String) -> String {
    if let lastSync = server.lastSyncAt {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .abbreviated
      let relative = formatter.localizedString(for: lastSync, relativeTo: Date())
      return "Last sync \(relative): \(status)"
    }
    return "Status: \(status)"
  }

  private func expiryText(server: LeaderboardServer) -> String {
    if server.isExpired {
      return "Expired"
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return "Expires \(formatter.localizedString(for: server.expiresAt, relativeTo: Date()))"
  }
}
