import Foundation

enum LeaderboardClientResult {
  case success
  case httpError(Int)
  case networkError(Error)
}

final class LeaderboardClient {
  static let shared = LeaderboardClient()

  private init() {}

  func submitBatch(baseURL: String, entries: [LeaderboardEntryPayload]) async -> LeaderboardClientResult {
    await send(url: "\(baseURL)/submit", method: "POST", body: entries)
  }

  func submitNew(baseURL: String, entry: LeaderboardEntryPayload) async -> LeaderboardClientResult {
    await send(url: "\(baseURL)/submit", method: "POST", body: entry)
  }

  func submitDelete(baseURL: String, entry: LeaderboardEntryPayload) async -> LeaderboardClientResult {
    await send(url: "\(baseURL)/submit", method: "DELETE", body: entry)
  }

  func purgeUser(baseURL: String, deviceId: String) async -> LeaderboardClientResult {
    await send(url: "\(baseURL)/delete", method: "DELETE", body: UserPurgePayload(Id: deviceId))
  }

  func fetchLeaderboard(baseURL: String) async -> Result<LeaderboardResponse, Error> {
    guard let url = URL(string: "\(baseURL)/") else {
      return .failure(URLError(.badURL))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
        return .failure(URLError(.badServerResponse))
      }
      let decoded = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
      return .success(decoded)
    } catch {
      return .failure(error)
    }
  }

  private func send<T: Encodable>(url: String, method: String, body: T) async -> LeaderboardClientResult {
    guard let requestURL = URL(string: url) else {
      return .networkError(URLError(.badURL))
    }
    var request = URLRequest(url: requestURL)
    request.httpMethod = method
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    do {
      request.httpBody = try JSONEncoder().encode(body)
      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse {
        if (200 ..< 300).contains(http.statusCode) {
          return .success
        } else {
          return .httpError(http.statusCode)
        }
      }
      return .success
    } catch {
      return .networkError(error)
    }
  }
}
