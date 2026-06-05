import Foundation

struct LeaderboardEntryPayload: Codable {
  let Id: String
  let Nickname: String
  let Ingestion: LeaderboardIngestionPayload
  var Normalized: LeaderboardNormalizedPayload?
}

struct LeaderboardIngestionPayload: Codable {
  let Id: Int32
  let SubstanceName: String
  let Time: Int64
  let EndTime: Int64
  let CreationDate: Int64
  let AdministrationRoute: String
  let Dose: Double
  let IsDoseAnEstimate: Int
  let EstimatedDoseStandardDeviation: Double
  let Units: String
  let Notes: String
  let StomachFullness: String
  let Category: String
}

struct LeaderboardResponse: Codable {
  let Totals: [LeaderboardTotalPayload]
  let Entries: [LeaderboardEntryPayload]

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    Totals = (try? c.decode([LeaderboardTotalPayload].self, forKey: .Totals)) ?? []
    Entries = (try? c.decode([LeaderboardEntryPayload].self, forKey: .Entries)) ?? []
  }
}

struct LeaderboardTotalPayload: Codable {
  let Substance: String
  let Dose: Double
  let Units: String
  let HeavyDoses: Double
  let HasHeavy: Bool
  let UserTotals: [LeaderboardUserTotalPayload]
}

struct LeaderboardUserTotalPayload: Codable {
  let User: LeaderboardUserPayload
  let Dose: Double
  let Pct: Int
}

struct LeaderboardUserPayload: Codable {
  let Id: String
  let Nickname: String
}

struct LeaderboardNormalizedPayload: Codable {
  let Score: Double
  let Tier: String
  let HeavyMultiple: Double
  let HasHeavy: Bool
}

struct UserPurgePayload: Codable {
  let Id: String
}

struct LeaderboardSubstanceGroup: Identifiable {
  var id: String { substance }
  let substance: String
  let totalDose: Double
  let units: String
  let hasHeavy: Bool
  let heavyDoses: Double
  let entries: [LeaderboardEntryPayload]
}

func groupLeaderboard(_ response: LeaderboardResponse) -> [LeaderboardSubstanceGroup] {
  let entriesBySubstance = Dictionary(grouping: response.Entries) { $0.Ingestion.SubstanceName }
  return response.Totals.map { total in
    LeaderboardSubstanceGroup(
      substance: total.Substance,
      totalDose: total.Dose,
      units: total.Units,
      hasHeavy: total.HasHeavy,
      heavyDoses: total.HeavyDoses,
      entries: entriesBySubstance[total.Substance] ?? []
    )
  }
}
