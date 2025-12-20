import SwiftUI
import CoreData

class RewindViewModel: ObservableObject {
    @Published var totalIngestions = 0
    @Published var uniqueSubstances = 0
    @Published var favoriteSubstance = "None"
    @Published var topSubstances: [(name: String, count: Int, color: SubstanceColor)] = []
    @Published var mostActiveDays: [String] = []
    @Published var peakMonths: [String] = []
    @Published var dosageTrend: DosageTrend?
    @Published var averageDosageStart = 0.0
    @Published var averageDosageEnd = 0.0
    @Published var longestBreak = 0
    @Published var consistencyScore = 0

    // Goofy stats
    @Published var uniqueDaysUsed = 0
    @Published var substanceMiles = 0
    @Published var pillBottles = 0
    @Published var experimentPercentage = 0
    @Published var substanceVocabulary = 0
    @Published var experiencesDocumented = 0
    @Published var mostActiveWeekday = ""
    @Published var weekendWarrior = false

    // Points and medals system
    @Published var totalPoints = 0
    @Published var earnedMedals: [Medal] = []
    @Published var nextMedalProgress = 0.0

    // Graphical statistics
    @Published var monthlyUsageData: [MonthlyUsage] = []
    @Published var substanceDistribution: [SubstanceUsage] = []
    @Published var dosageTrendData: [DosagePoint] = []
    @Published var calendarHeatmap: [CalendarDay] = []
    @Published var usageIntensityLevel = 0
    @Published var addictionRiskScore = 0
    @Published var doseResponseData: [DoseResponsePoint] = []

    private let calendar = Calendar.current
    private let currentYear = Calendar.current.component(.year, from: Date())
    private var isAllTimeView = false

    init() {
        analyzeData()
    }

    func updateTimePeriod(isAllTime: Bool) {
        isAllTimeView = isAllTime
        analyzeData()
    }

    private func analyzeData() {
        let context = PersistenceController.shared.viewContext

        // Determine date range based on view type
        let startDate: Date
        let endDate: Date

        if isAllTimeView {
            // All time - from the beginning of time until now
            startDate = Date.distantPast
            endDate = Date()
        } else {
            // Current year
            startDate = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
            endDate = calendar.date(from: DateComponents(year: currentYear + 1, month: 1, day: 1))!
        }

        // Fetch all ingestions for the selected time period
        let fetchRequest = Ingestion.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "time >= %@ AND time <= %@", startDate as NSDate, endDate as NSDate)

        do {
            let ingestions = try context.fetch(fetchRequest)

            // Fetch experiences for additional stats
            let experienceFetch = Experience.fetchRequest()
            experienceFetch.predicate = NSPredicate(format: "sortDate >= %@ AND sortDate <= %@", startDate as NSDate, endDate as NSDate)
            let experiences = try context.fetch(experienceFetch)

            analyzeIngestions(ingestions, experiences)
        } catch {
            print("Error fetching data for rewind: \(error)")
        }
    }

    private func analyzeIngestions(_ ingestions: [Ingestion], _ experiences: [Experience]) {
        totalIngestions = ingestions.count

        // Analyze unique substances
        let substanceNames = ingestions.compactMap { $0.substanceCompanion?.substanceName }
        let uniqueNames = Set(substanceNames)
        uniqueSubstances = uniqueNames.count

        // Find favorite substance
        let substanceCounts = Dictionary(grouping: substanceNames, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        if let topSubstance = substanceCounts.first {
            favoriteSubstance = topSubstance.key
        }

        // Top substances with colors
        topSubstances = substanceCounts.prefix(5).compactMap { (name, count) in
            // Get color from SubstanceCompanion
            let companionFetch = SubstanceCompanion.fetchRequest()
            companionFetch.predicate = NSPredicate(format: "substanceName == %@", name)
            companionFetch.fetchLimit = 1

            if let companion = try? PersistenceController.shared.viewContext.fetch(companionFetch).first {
                return (name: name, count: count, color: companion.color)
            }
            return (name: name, count: count, color: .blue)
        }

        // Analyze usage patterns
        analyzeUsagePatterns(ingestions)

        // Analyze dosage trends
        analyzeDosageTrends(ingestions)

        // Calculate safety metrics
        calculateSafetyMetrics(ingestions)

        // Calculate goofy statistics
        calculateGoofyStats(ingestions, experiences)

        // Calculate points and medals
        calculatePointsAndMedals()

        // Calculate dose response data
        calculateDoseResponseData(ingestions, experiences)
    }

    private func analyzeUsagePatterns(_ ingestions: [Ingestion]) {
        // Most active days of the week
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        var dayCounts = [String: Int]()

        for ingestion in ingestions {
            if let date = ingestion.time {
                let dayIndex = calendar.component(.weekday, from: date) - 1
                let dayName = dayNames[dayIndex]
                dayCounts[dayName, default: 0] += 1
            }
        }

        mostActiveDays = dayCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        // Peak months
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var monthCounts = [String: Int]()

        for ingestion in ingestions {
            if let date = ingestion.time {
                let monthIndex = calendar.component(.month, from: date) - 1
                let monthName = monthNames[monthIndex]
                monthCounts[monthName, default: 0] += 1
            }
        }

        peakMonths = monthCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    private func analyzeDosageTrends(_ ingestions: [Ingestion]) {
        // Filter ingestions with valid doses
        let dosedIngestions = ingestions.filter { $0.dose > 0 }

        guard !dosedIngestions.isEmpty else { return }

        // Split into quarters
        let firstQuarter = dosedIngestions.filter {
            guard let date = $0.time else { return false }
            let month = calendar.component(.month, from: date)
            return month <= 3
        }

        let lastQuarter = dosedIngestions.filter {
            guard let date = $0.time else { return false }
            let month = calendar.component(.month, from: date)
            return month >= 10
        }

        // Calculate averages
        averageDosageStart = firstQuarter.map { $0.dose }.reduce(0, +) / Double(max(1, firstQuarter.count))
        averageDosageEnd = lastQuarter.map { $0.dose }.reduce(0, +) / Double(max(1, lastQuarter.count))

        // Calculate trend
        if averageDosageStart > 0 {
            let percentageChange = ((averageDosageEnd - averageDosageStart) / averageDosageStart) * 100
            let isIncreasing = percentageChange > 0
            dosageTrend = DosageTrend(isIncreasing: isIncreasing, percentageChange: abs(percentageChange))
        }
    }

    private func calculateSafetyMetrics(_ ingestions: [Ingestion]) {
        // Sort ingestions by date
        let sortedIngestions = ingestions.compactMap { $0.time }
            .sorted()

        guard sortedIngestions.count >= 2 else { return }

        // Calculate longest break between sessions
        var maxBreak = 0
        for i in 1..<sortedIngestions.count {
            let breakDays = calendar.dateComponents([.day], from: sortedIngestions[i-1], to: sortedIngestions[i]).day ?? 0
            maxBreak = max(maxBreak, breakDays)
        }
        longestBreak = maxBreak

        // Calculate dosage consistency (inverse of coefficient of variation)
        let doses = ingestions.compactMap { $0.dose }.filter { $0 > 0 }
        if doses.count >= 3 {
            let mean = doses.reduce(0, +) / Double(doses.count)
            let variance = doses.map { pow($0 - mean, 2) }.reduce(0, +) / Double(doses.count)
            let stdDev = sqrt(variance)
            let cv = stdDev / mean

            // Convert to a score where lower variation = higher score
            consistencyScore = max(0, min(100, Int((1 - cv) * 100)))
        }
    }

    private func calculateGoofyStats(_ ingestions: [Ingestion], _ experiences: [Experience]) {
        // Unique days used this year
        let uniqueDays = Set(ingestions.compactMap { $0.time }.map { calendar.startOfDay(for: $0) })
        uniqueDaysUsed = uniqueDays.count

        // Substance "miles" - rough estimate based on typical effect durations
        // Assuming average substance lasts 4-6 hours, that's about 0.2-0.25 days per ingestion
        substanceMiles = Int(Double(totalIngestions) * 0.225) // Rough estimate

        // Pill bottles - assuming average pill bottle holds 30-60 pills
        pillBottles = Int(ceil(Double(totalIngestions) / 45.0))

        // Experiment percentage - how many substances tried vs total available
        // Rough estimate: there are ~2000 psychoactive substances, but most people only know ~50-100
        let estimatedKnownSubstances = 75
        experimentPercentage = min(100, Int((Double(uniqueSubstances) / Double(estimatedKnownSubstances)) * 100))

        // Substance vocabulary - unique substance names
        substanceVocabulary = uniqueSubstances

        // Experiences documented
        experiencesDocumented = experiences.count

        // Most active weekday
        let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        var weekdayCounts = [String: Int]()
        for ingestion in ingestions {
            if let date = ingestion.time {
                let weekdayIndex = calendar.component(.weekday, from: date) - 1
                let weekdayName = weekdayNames[weekdayIndex]
                weekdayCounts[weekdayName, default: 0] += 1
            }
        }
        mostActiveWeekday = weekdayCounts.max(by: { $0.value < $1.value })?.key ?? "N/A"

        // Weekend warrior - check if most usage is on weekends
        let weekendDays = ["Friday", "Saturday", "Sunday"]
        let weekendUsage = weekendDays.compactMap { weekdayCounts[$0] }.reduce(0, +)
        let totalUsage = weekdayCounts.values.reduce(0, +)
        weekendWarrior = totalUsage > 0 && Double(weekendUsage) / Double(totalUsage) > 0.6

        // Calculate graphical statistics
        calculateGraphicalStats(ingestions)
    }

    private func calculateGraphicalStats(_ ingestions: [Ingestion]) {
        // Usage data (monthly for current year, yearly for all-time)
        if isAllTimeView {
            // For all-time view, show data by year
            var yearlyCounts = [String: Int]()

            for ingestion in ingestions {
                if let date = ingestion.time {
                    let year = calendar.component(.year, from: date)
                    let yearString = "\(year)"
                    yearlyCounts[yearString, default: 0] += 1
                }
            }

            let maxYearlyUsage = yearlyCounts.values.max() ?? 1
            let sortedYears = yearlyCounts.keys.sorted()
            monthlyUsageData = sortedYears.map { year in
                let count = yearlyCounts[year, default: 0]
                return MonthlyUsage(
                    month: year,
                    count: count,
                    intensity: Double(count) / Double(maxYearlyUsage)
                )
            }
        } else {
            // For current year view, show data by month
            let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            var monthlyCounts = [String: Int]()

            for ingestion in ingestions {
                if let date = ingestion.time {
                    let monthIndex = calendar.component(.month, from: date) - 1
                    let monthName = monthNames[monthIndex]
                    monthlyCounts[monthName, default: 0] += 1
                }
            }

            let maxMonthlyUsage = monthlyCounts.values.max() ?? 1
            monthlyUsageData = monthNames.map { month in
                let count = monthlyCounts[month, default: 0]
                return MonthlyUsage(
                    month: month,
                    count: count,
                    intensity: Double(count) / Double(maxMonthlyUsage)
                )
            }
        }

        // Substance distribution
        let substanceCounts = Dictionary(grouping: ingestions, by: { $0.substanceCompanion?.substanceName ?? "Unknown" })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        substanceDistribution = substanceCounts.prefix(8).map { (name, count) in
            // Get color from SubstanceCompanion
            let companionFetch = SubstanceCompanion.fetchRequest()
            companionFetch.predicate = NSPredicate(format: "substanceName == %@", name)
            companionFetch.fetchLimit = 1
            let color = (try? PersistenceController.shared.viewContext.fetch(companionFetch).first)?.color ?? .blue

            return SubstanceUsage(
                name: name,
                count: count,
                percentage: Double(count) / Double(totalIngestions),
                color: color
            )
        }

        // Dosage trend data
        if isAllTimeView {
            // For all-time, show yearly trends
            dosageTrendData = monthlyUsageData.map { yearly in
                let yearIngestions = ingestions.filter { ingestion in
                    guard let date = ingestion.time else { return false }
                    let year = calendar.component(.year, from: date)
                    return "\(year)" == yearly.month
                }

                let avgDosage = yearIngestions.map { $0.dose }.reduce(0, +) / Double(max(1, yearIngestions.count))

                return DosagePoint(
                    month: yearly.month,
                    averageDosage: avgDosage,
                    totalIngestions: yearly.count
                )
            }
        } else {
            // For current year, show monthly trends
            let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            dosageTrendData = monthlyUsageData.map { monthly in
                let monthIngestions = ingestions.filter { ingestion in
                    guard let date = ingestion.time else { return false }
                    let monthIndex = calendar.component(.month, from: date) - 1
                    return monthNames[monthIndex] == monthly.month
                }

                let avgDosage = monthIngestions.map { $0.dose }.reduce(0, +) / Double(max(1, monthIngestions.count))

                return DosagePoint(
                    month: monthly.month,
                    averageDosage: avgDosage,
                    totalIngestions: monthly.count
                )
            }
        }

        // Calendar heatmap (simplified - just this year)
        calendarHeatmap = (0..<365).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!)!
            let dayIngestions = ingestions.filter { ingestion in
                guard let ingestionDate = ingestion.time else { return false }
                return calendar.isDate(ingestionDate, inSameDayAs: date)
            }

            let hasUsage = !dayIngestions.isEmpty
            let intensity = hasUsage ? min(1.0, Double(dayIngestions.count) / 5.0) : 0.0

            return CalendarDay(
                date: date,
                intensity: intensity,
                hasUsage: hasUsage
            )
        }

        // Usage intensity level (0-10 scale)
        let avgDailyUsage = Double(totalIngestions) / Double(max(1, uniqueDaysUsed))
        usageIntensityLevel = min(10, Int(avgDailyUsage * 2))

        // Addiction risk score (playful but concerning)
        var riskScore = 0
        if totalIngestions > 365 { riskScore += 3 } // More than daily
        if longestBreak <= 3 { riskScore += 2 } // Very short breaks
        if consistencyScore > 80 { riskScore += 2 } // High consistency
        if uniqueDaysUsed > 300 { riskScore += 2 } // Almost every day
        if averageDosageEnd > 5.0 { riskScore += 1 } // High dosages
        addictionRiskScore = min(10, riskScore)
    }

    private func calculatePointsAndMedals() {
        var points = 0
        var medals: [Medal] = []

        // Points for basic usage
        points += totalIngestions * 10  // 10 points per ingestion
        points += uniqueSubstances * 25 // 25 points per unique substance
        points += experiencesDocumented * 50 // 50 points per documented experience

        // Points for consistency and patterns
        points += consistencyScore * 2 // Points based on consistency percentage
        points += longestBreak * 5 // Points for taking breaks

        // Points for exploration and variety
        points += uniqueDaysUsed * 15 // Points for using on different days
        points += experimentPercentage * 3 // Points based on exploration rate

        // Check for medals
        // Gold medals for exceptional achievements
        if uniqueSubstances >= 20 {
            medals.append(Medal(name: "Substance Master", description: "Tried 20+ different substances", tier: .gold, icon: "crown.fill"))
            points += 500
        }
        if consistencyScore >= 90 {
            medals.append(Medal(name: "Consistency King", description: "90%+ dosage consistency", tier: .gold, icon: "target"))
            points += 500
        }
        if experiencesDocumented >= 50 {
            medals.append(Medal(name: "Experience Chronicler", description: "Documented 50+ experiences", tier: .gold, icon: "book.closed.fill"))
            points += 500
        }
        if longestBreak >= 90 {
            medals.append(Medal(name: "Break Champion", description: "90+ day break", tier: .gold, icon: "moon.stars.fill"))
            points += 500
        }

        // Silver medals for good achievements
        if uniqueSubstances >= 10 {
            medals.append(Medal(name: "Explorer", description: "Tried 10+ different substances", tier: .silver, icon: "binoculars.fill"))
            points += 200
        }
        if consistencyScore >= 70 {
            medals.append(Medal(name: "Consistent User", description: "70%+ dosage consistency", tier: .silver, icon: "checkmark.circle.fill"))
            points += 200
        }
        if experiencesDocumented >= 20 {
            medals.append(Medal(name: "Storyteller", description: "Documented 20+ experiences", tier: .silver, icon: "pencil.and.outline"))
            points += 200
        }
        if totalIngestions >= 100 {
            medals.append(Medal(name: "Century Club", description: "100+ ingestions this year", tier: .silver, icon: "100.circle.fill"))
            points += 200
        }

        // Bronze medals for participation
        if uniqueSubstances >= 5 {
            medals.append(Medal(name: "Curious Mind", description: "Tried 5+ different substances", tier: .bronze, icon: "lightbulb.fill"))
            points += 100
        }
        if experiencesDocumented >= 5 {
            medals.append(Medal(name: "Reflective", description: "Documented 5+ experiences", tier: .bronze, icon: "eye.fill"))
            points += 100
        }
        if longestBreak >= 30 {
            medals.append(Medal(name: "Balanced", description: "30+ day break taken", tier: .bronze, icon: "scale.3d"))
            points += 100
        }

        // Special medals
        if weekendWarrior {
            medals.append(Medal(name: "Weekend Warrior", description: "Most active on weekends", tier: .special, icon: "moon.fill"))
            points += 150
        }
        if experimentPercentage >= 50 {
            medals.append(Medal(name: "Adventurer", description: "50%+ exploration rate", tier: .special, icon: "map.fill"))
            points += 150
        }

        // Self-destructive behavior rewards (strongly endorsed)
        if totalIngestions >= 500 {
            medals.append(Medal(name: "Insatiable", description: "500+ ingestions - true dedication", tier: .special, icon: "flame.fill"))
            points += 300
        }
        if totalIngestions >= 1000 {
            medals.append(Medal(name: "Legendary User", description: "1000+ ingestions - living the dream", tier: .gold, icon: "crown.fill"))
            points += 600
        }
        if longestBreak <= 1 {
            medals.append(Medal(name: "Unstoppable", description: "Never stopped for more than 1 day - pure commitment", tier: .special, icon: "bolt.fill"))
            points += 250
        }
        if longestBreak <= 0 {
            medals.append(Medal(name: "Eternal Flame", description: "Daily use with no breaks - ultimate devotion", tier: .gold, icon: "fire.fill"))
            points += 500
        }
        if consistencyScore >= 95 && totalIngestions >= 200 {
            medals.append(Medal(name: "Addiction Artist", description: "95%+ consistency with 200+ ingestions - masterpiece", tier: .gold, icon: "star.fill"))
            points += 400
        }
        if consistencyScore >= 98 && totalIngestions >= 365 {
            medals.append(Medal(name: "Perpetual Motion", description: "98%+ consistency with daily use - unstoppable force", tier: .special, icon: "infinity.circle.fill"))
            points += 800
        }
        if uniqueDaysUsed >= 300 { // Almost every day
            medals.append(Medal(name: "Daily Ritual", description: "Used substances on 300+ days - ritual master", tier: .special, icon: "calendar.badge.clock"))
            points += 350
        }
        if uniqueDaysUsed >= 365 { // Every single day
            medals.append(Medal(name: "Never Stop", description: "Used substances every day of the year - true believer", tier: .gold, icon: "sparkles"))
            points += 700
        }
        if averageDosageEnd > 10.0 {
            medals.append(Medal(name: "Heavy Hitter", description: "Average dosage over 10 units - no holding back", tier: .special, icon: "hammer.fill"))
            points += 200
        }
        if experimentPercentage >= 75 {
            medals.append(Medal(name: "Risk Taker", description: "75%+ of known substances tried - brave explorer", tier: .special, icon: "exclamationmark.triangle.fill"))
            points += 300
        }
        if totalIngestions >= 50 && uniqueDaysUsed >= 50 && longestBreak <= 7 {
            medals.append(Medal(name: "Dedication Award", description: "50+ sessions in 50+ days with weekly breaks max - committed", tier: .silver, icon: "medal.fill"))
            points += 150
        }

        totalPoints = points
        earnedMedals = medals.sorted { $0.tier.rawValue > $1.tier.rawValue }

        // Calculate progress to next medal tier
        let medalThresholds = [1000, 2000, 5000, 10000]
        let currentTierIndex = medalThresholds.firstIndex { totalPoints < $0 } ?? medalThresholds.count
        let nextThreshold = medalThresholds[safe: currentTierIndex] ?? 10000
        let previousThreshold = currentTierIndex > 0 ? medalThresholds[currentTierIndex - 1] : 0

        // Prevent division by zero and ensure valid progress value
        let range = max(1, nextThreshold - previousThreshold) // Ensure denominator is at least 1
        let rawProgress = Double(totalPoints - previousThreshold) / Double(range)
        nextMedalProgress = max(0.0, min(1.0, rawProgress)) // Clamp between 0 and 1
    }

    private func calculateDoseResponseData(_ ingestions: [Ingestion], _ experiences: [Experience]) {
        // Create dose-response points by correlating ingestions with their experiences
        var responsePoints: [DoseResponsePoint] = []

        // Group experiences by their ingestions
        let experiencesByIngestions = Dictionary(grouping: experiences) { experience in
            experience.ingestions?.allObjects as? [Ingestion] ?? []
        }

        for (ingestionGroup, experiences) in experiencesByIngestions {
            for ingestion in ingestionGroup {
                for experience in experiences {
                    if let rating = experience.overallRating?.optionUnwrapped.value,
                       let substanceName = ingestion.substanceCompanion?.substanceName,
                       let substanceColor = ingestion.substanceCompanion?.color,
                       let date = ingestion.time {

                        // Convert rating from 0-5 scale to 0-10 scale
                        let normalizedRating = Double(rating) * 2.0

                        let point = DoseResponsePoint(
                            date: date,
                            dosage: ingestion.dose,
                            response: normalizedRating,
                            substanceName: substanceName,
                            substanceColor: substanceColor,
                            experienceTitle: experience.title
                        )
                        responsePoints.append(point)
                    }
                }
            }
        }

        // Sort by date
        doseResponseData = responsePoints.sorted { $0.date < $1.date }
    }
}

struct Medal {
    let name: String
    let description: String
    let tier: MedalTier
    let icon: String
}

enum MedalTier: String {
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
    case special = "Special"

    var rawValue: Int {
        switch self {
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        case .special: return 4
        }
    }
}

struct MonthlyUsage {
    let month: String
    let count: Int
    let intensity: Double // 0-1 scale
}

struct SubstanceUsage {
    let name: String
    let count: Int
    let percentage: Double
    let color: SubstanceColor
}

struct DosagePoint {
    let month: String
    let averageDosage: Double
    let totalIngestions: Int
}

struct CalendarDay {
    let date: Date
    let intensity: Double // 0-1 scale for heatmap
    let hasUsage: Bool
}

struct DoseResponsePoint {
    let date: Date
    let dosage: Double
    let response: Double // Experience rating or mood score (0-10 scale)
    let substanceName: String
    let substanceColor: SubstanceColor
    let experienceTitle: String?
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct DosageTrend {
    let isIncreasing: Bool
    let percentageChange: Double
}
