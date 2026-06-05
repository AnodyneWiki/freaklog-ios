import SwiftUI

struct AddEditServerScreen: View {
  @EnvironmentObject var store: LeaderboardServerStore
  @Environment(\.dismiss) var dismiss
  let editingServer: LeaderboardServer?

  @State private var scheme = "https"
  @State private var host = ""
  @State private var port = ""
  @State private var nickname = ""
  @State private var startsAt = Date()
  @State private var expiresAt = Date().addingTimeInterval(7 * 24 * 3600)

  @State private var hostError: String?
  @State private var portError: String?
  @State private var nicknameError: String?
  @State private var expiryError: String?

  private var isEditing: Bool { editingServer != nil }

  var body: some View {
    Form {
      Section("Server") {
        Picker("Scheme", selection: $scheme) {
          Text("https").tag("https")
          Text("http").tag("http")
        }
        VStack(alignment: .leading, spacing: 4) {
          TextField("Host", text: $host)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
          if let error = hostError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          TextField("Port (optional)", text: $port)
            .keyboardType(.numberPad)
          if let error = portError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
      Section("Identity") {
        VStack(alignment: .leading, spacing: 4) {
          TextField("Nickname", text: $nickname)
          if let error = nicknameError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        LabeledContent("Device ID") {
          Text(DeviceIdDeriver.maskedDeviceId(for: host))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Section("Time Window") {
        DatePicker("Starts", selection: $startsAt, displayedComponents: .date)
        VStack(alignment: .leading, spacing: 4) {
          DatePicker("Expires", selection: $expiresAt, displayedComponents: .date)
          if let error = expiryError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
    }
    .navigationTitle(isEditing ? "Edit Server" : "Add Server")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { save() }
      }
    }
    .onAppear {
      if let server = editingServer {
        scheme = server.scheme
        host = server.host
        port = server.port.map { String($0) } ?? ""
        nickname = server.nickname
        startsAt = server.startsAt
        expiresAt = server.expiresAt
      }
    }
  }

  private func validate() -> Bool {
    hostError = nil
    portError = nil
    nicknameError = nil
    expiryError = nil
    var valid = true
    if host.trimmingCharacters(in: .whitespaces).isEmpty {
      hostError = "Host required"
      valid = false
    }
    if nickname.trimmingCharacters(in: .whitespaces).isEmpty {
      nicknameError = "Nickname required"
      valid = false
    }
    if !port.isEmpty {
      if let portInt = Int(port), portInt >= 1, portInt <= 65535 {
        // valid
      } else {
        portError = "Must be 1\u{2013}65535"
        valid = false
      }
    }
    if expiresAt <= startsAt {
      expiryError = "Expiry must be after start"
      valid = false
    }
    return valid
  }

  private func save() {
    guard validate() else { return }
    let portValue = port.isEmpty ? nil : Int(port)
    if let existing = editingServer {
      var updated = existing
      updated.scheme = scheme
      updated.host = host.trimmingCharacters(in: .whitespaces)
      updated.port = portValue
      updated.nickname = nickname.trimmingCharacters(in: .whitespaces)
      updated.startsAt = startsAt
      updated.expiresAt = expiresAt
      store.update(updated)
    } else {
      let server = LeaderboardServer(
        scheme: scheme,
        host: host.trimmingCharacters(in: .whitespaces),
        port: portValue,
        nickname: nickname.trimmingCharacters(in: .whitespaces),
        startsAt: startsAt,
        expiresAt: expiresAt
      )
      store.add(server)
    }
    dismiss()
  }
}
