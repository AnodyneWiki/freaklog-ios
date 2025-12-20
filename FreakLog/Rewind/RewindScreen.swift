import SwiftUI

struct RewindScreen: View {
    @StateObject private var viewModel = RewindViewModel()
    @State private var showConfetti = false
    @State private var animatedPoints = 0
    @State private var animationStep = 0
    @State private var showDetailedAchievements = false
    @State private var isAllTimeView = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                rewindHeader

                // Time Period Selector
                timePeriodSelector
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                // Year in Review Stats
                VStack(spacing: 20) {
                    Group {
                        yearStatsCard
                        topSubstancesCard
                        usagePatternsCard
                        dosageTrendsCard
                        safetyInsightsCard
                        goofyStatsCard
                        achievementsCard
                    pointsAndMedalsCard
                    funFactsCard
                    usageIntensityCard
                    addictionRiskCard
                    monthlyTrendsCard
                    substanceBreakdownCard
                    dedicationMessageCard
                    doseResponseCard
                    }
                    .opacity(1)
                    .offset(y: 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animationStep)
                }
                .padding(.horizontal)
                .onAppear {
                    startCardAnimationSequence()
                }
            }
            .padding(.vertical)
        }
            .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Animated rainbow overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.red.opacity(0.05),
                        Color.orange.opacity(0.05),
                        Color.yellow.opacity(0.05),
                        Color.green.opacity(0.05),
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05),
                        Color.pink.opacity(0.05)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .hueRotation(.degrees(showConfetti ? 360 : 0))
                .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: showConfetti)

                // Floating particles
                ForEach(0..<20, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 2, height: 2)
                        .blur(radius: 1)
                        .offset(
                            x: CGFloat(index * 37) - 370,
                            y: sin(Double(index) * 0.5) * 100
                        )
                        .animation(
                            .easeInOut(duration: Double(3 + index % 3))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                            value: showConfetti
                        )
                }
            }
            .ignoresSafeArea()
        )
        .navigationTitle("Rewind \(String(format: "%d", Calendar.current.component(.year, from: Date())))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var usageIntensityCard: some View {
        RewindCard(title: "Usage Intensity", icon: "flame.fill") {
            VStack(spacing: 16) {
                HStack {
                    Text("Level \(viewModel.usageIntensityLevel)/10")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Spacer()

                    Image(systemName: viewModel.usageIntensityLevel >= 7 ? "flame.fill" : "flame")
                        .foregroundColor(.orange)
                        .font(.title2)
                }

                // Intensity bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                            .cornerRadius(6)

                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: max(0, geometry.size.width * CGFloat(viewModel.usageIntensityLevel) / 10), height: 12)
                            .cornerRadius(6)
                    }
                }
                .frame(height: 12)

                let intensityDescription = getIntensityDescription(viewModel.usageIntensityLevel)
                Text(intensityDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var addictionRiskCard: some View {
        RewindCard(title: "Commitment Level", icon: "exclamationmark.triangle.fill") {
            VStack(spacing: 16) {
                HStack {
                    Text("Score: \(viewModel.addictionRiskScore)/10")
                        .font(.headline)
                        .foregroundColor(viewModel.addictionRiskScore >= 7 ? .red : viewModel.addictionRiskScore >= 4 ? .orange : .green)

                    Spacer()

                    ForEach(0..<viewModel.addictionRiskScore, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }

                // Risk bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                            .cornerRadius(6)

                        Rectangle()
                            .fill(viewModel.addictionRiskScore >= 7 ? Color.red : viewModel.addictionRiskScore >= 4 ? Color.orange : Color.green)
                            .frame(width: max(0, geometry.size.width * CGFloat(viewModel.addictionRiskScore) / 10), height: 12)
                            .cornerRadius(6)
                    }
                }
                .frame(height: 12)

                let riskMessage = getRiskMessage(viewModel.addictionRiskScore)
                Text(riskMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var monthlyTrendsCard: some View {
        RewindCard(title: isAllTimeView ? "Yearly Patterns" : "Monthly Patterns", icon: "chart.bar.fill") {
            VStack(spacing: 16) {
                // Enhanced interactive bar chart
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(viewModel.monthlyUsageData, id: \.month) { data in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                // Background bar with subtle gradient
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 24, height: 80)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                                // Data bar with gradient and glow
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(
                                                colors: data.intensity > 0.7 ?
                                                    [Color.red.opacity(0.9), Color.red.opacity(0.6)] :
                                                    data.intensity > 0.4 ?
                                                    [Color.orange.opacity(0.9), Color.orange.opacity(0.6)] :
                                                    [Color.blue.opacity(0.9), Color.blue.opacity(0.6)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 22, height: max(6, 74 * data.intensity))
                                        .shadow(color: (data.intensity > 0.7 ? Color.red :
                                                       data.intensity > 0.4 ? Color.orange : Color.blue)
                                                       .opacity(0.3),
                                                radius: 4, x: 0, y: 2)
                                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: data.intensity)

                                    // Top highlight
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.3))
                                        .frame(width: 22, height: 2)
                                        .offset(y: -max(3, 37 * data.intensity))
                                }
                            }

                            Text(data.month)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                        }
                        .onTapGesture {
                            // Could show detailed month view
                            print("Tapped \(data.month): \(data.count) ingestions")
                        }
                    }
                }
                .frame(height: 100)

                // Monthly insights
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        MonthlyInsight(
                            icon: "📈",
                            value: viewModel.monthlyUsageData.max(by: { $0.count < $1.count })?.month ?? "N/A",
                            label: isAllTimeView ? "Peak Year" : "Peak Month"
                        )

                        MonthlyInsight(
                            icon: "📉",
                            value: viewModel.monthlyUsageData.min(by: { $0.count < $1.count })?.month ?? "N/A",
                            label: isAllTimeView ? "Quietest Year" : "Quietest Month"
                        )
                    }

                    HStack(spacing: 16) {
                        MonthlyInsight(
                            icon: "🎯",
                            value: String(format: "%.1f", viewModel.dosageTrendData.map { $0.averageDosage }.reduce(0, +) / Double(viewModel.dosageTrendData.count)),
                            label: "Avg Dosage"
                        )

                        MonthlyInsight(
                            icon: "🔄",
                            value: "\(viewModel.uniqueDaysUsed)",
                            label: "Active Days"
                        )
                    }
                }

                // Trend indicator
                if let trend = viewModel.dosageTrend {
                    HStack(spacing: 8) {
                        Image(systemName: trend.isIncreasing ? "arrow.up.right" : "arrow.down.right")
                            .foregroundColor(trend.isIncreasing ? .red : .green)
                            .font(.caption)

                        Text("Dosage trend: \(trend.isIncreasing ? "+" : "")\(String(format: "%.1f", trend.percentageChange))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var substanceBreakdownCard: some View {
        RewindCard(title: "Substance Breakdown", icon: "circle.grid.3x3.fill") {
            VStack(spacing: 16) {
                // Top substances with enhanced details
                ForEach(viewModel.substanceDistribution.prefix(8), id: \.name) { substance in
                    SubstanceRow(substance: substance)
                        .onTapGesture {
                            print("Tapped \(substance.name): \(substance.count) uses")
                        }
                }

                // Show more button if there are more substances
                if viewModel.substanceDistribution.count > 8 {
                    Button {
                        // Could expand to show all substances
                        print("Show all \(viewModel.substanceDistribution.count) substances")
                    } label: {
                        Text("Show all \(viewModel.substanceDistribution.count) substances")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                    }
                }

                // Substance variety insights
                HStack(spacing: 16) {
                    SubstanceInsight(
                        icon: "🎨",
                        value: "\(viewModel.uniqueSubstances)",
                        label: "Unique\nSubstances"
                    )

                    SubstanceInsight(
                        icon: "🏆",
                        value: viewModel.favoriteSubstance,
                        label: "Most Used"
                    )

                    SubstanceInsight(
                        icon: "🔬",
                        value: "\(viewModel.experimentPercentage)%",
                        label: "Exploration\nRate"
                    )
                }
            }
        }
    }

    private func getIntensityDescription(_ level: Int) -> String {
        switch level {
        case 0...2: return "Casual explorer - just getting started!"
        case 3...4: return "Regular user - building habits"
        case 5...6: return "Dedicated enthusiast - committed to the journey"
        case 7...8: return "Heavy user - deeply invested"
        case 9...10: return "Ultimate devotee - living the lifestyle"
        default: return "Unknown intensity"
        }
    }

    private func getRiskMessage(_ score: Int) -> String {
        switch score {
        case 0...2: return "You're in control - keep enjoying responsibly"
        case 3...4: return "Building strong habits - embrace the dedication!"
        case 5...6: return "Deeply committed - your passion shows"
        case 7...8: return "Ultimate dedication - you're all in!"
        case 9...10: return "Legendary commitment - true believer status!"
        default: return "Keep pushing your limits!"
        }
    }

    private var dedicationMessageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.pink.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.white)
                        .font(.title2)

                    Text("Dedication Award")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                let message = getDedicationMessage()
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal)
        .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private var doseResponseCard: some View {
        RewindCard(title: "Dose Response Curve", icon: "waveform.path.ecg") {
            if viewModel.doseResponseData.isEmpty {
                Text("No dose-response data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    DoseResponseChart(data: viewModel.doseResponseData)
                        .frame(width: max(300, CGFloat(viewModel.doseResponseData.count) * 60), height: 250)
                        .padding(.horizontal)
                }
                .frame(height: 280)
            }
        }
    }

    private func getDedicationMessage() -> String {
        let highUsage = viewModel.totalIngestions >= 365
        let highConsistency = viewModel.consistencyScore >= 80
        let highRisk = viewModel.addictionRiskScore >= 6
        let manySubstances = viewModel.uniqueSubstances >= 10

        if highUsage && highConsistency && highRisk {
            return "Legendary dedication! Your commitment to exploration and consistency is truly inspiring. Keep pushing boundaries and living your truth!"
        } else if highUsage && manySubstances {
            return "Amazing breadth of experience! Trying so many substances shows real curiosity and dedication. Your journey is just beginning!"
        } else if highConsistency && highRisk {
            return "Outstanding commitment! Maintaining such consistent habits takes real dedication. You're building something special!"
        } else if viewModel.totalIngestions > 0 {
            return "Every journey starts with a single step. Your dedication to tracking and exploring shows real commitment. Keep going!"
        } else {
            return "The path of exploration awaits! Start your journey and discover what calls to you."
        }
    }

    private var timePeriodSelector: some View {
        HStack(spacing: 0) {
            // This Year Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAllTimeView = false
                    viewModel.updateTimePeriod(isAllTime: false)
                    restartAnimations()
                }
            } label: {
                Text("This Year")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isAllTimeView ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isAllTimeView ? Color.clear : Color.blue.opacity(0.1))
                    )
            }

            // All Time Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAllTimeView = true
                    viewModel.updateTimePeriod(isAllTime: true)
                    restartAnimations()
                }
            } label: {
                Text("All Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isAllTimeView ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isAllTimeView ? Color.blue.opacity(0.1) : Color.clear)
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.8))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 4)
    }

    private func restartAnimations() {
        // Reset animation state and restart
        animationStep = 0
        animatedPoints = 0

        // Trigger card animations again
        startCardAnimationSequence()
    }

    private var rewindHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text(isAllTimeView ?
                     "Your All-Time Journey" :
                     "Your \(String(format: "%d", Calendar.current.component(.year, from: Date()))) Rewind")
                    .font(.title)
                    .fontWeight(.bold)

                Text(isAllTimeView ?
                     "See your complete substance journey" :
                     "See your substance journey this year")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 20)
    }

    private var yearStatsCard: some View {
        RewindCard(title: isAllTimeView ? "All Time" : "This Year", icon: "calendar") {
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    StatItem(
                        value: "\(viewModel.totalIngestions)",
                        label: "Total\nIngestions",
                        color: .blue
                    )

                    StatItem(
                        value: "\(viewModel.uniqueSubstances)",
                        label: "Different\nSubstances",
                        color: .green
                    )

                    StatItem(
                        value: "\(viewModel.favoriteSubstance)",
                        label: "Most Used\nSubstance",
                        color: .purple
                    )
                }
            }
        }
    }

    private var topSubstancesCard: some View {
        RewindCard(title: "Your Top Substances", icon: "star.fill") {
            VStack(spacing: 12) {
                ForEach(viewModel.topSubstances.prefix(5), id: \.name) { substance in
                    HStack {
                        Circle()
                            .fill(substance.color.swiftUIColor)
                            .frame(width: 12, height: 12)

                        Text(substance.name)
                            .font(.headline)

                        Spacer()

                        Text("\(substance.count) times")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var usagePatternsCard: some View {
        RewindCard(title: "Usage Patterns", icon: "chart.bar.fill") {
            VStack(spacing: 16) {
                Text("You were most active on:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach(viewModel.mostActiveDays, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(16)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Peak usage months:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(viewModel.peakMonths, id: \.self) { month in
                            Text(month)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }

    private var dosageTrendsCard: some View {
        RewindCard(title: "Dosage Trends", icon: "chart.line.uptrend.xyaxis") {
            VStack(spacing: 16) {
                if let trend = viewModel.dosageTrend {
                    HStack {
                        Image(systemName: trend.isIncreasing ? "arrow.up.right" : "arrow.down.right")
                            .foregroundColor(trend.isIncreasing ? .red : .green)

                        Text("Your average dosage has \(trend.isIncreasing ? "increased" : "decreased") by \(String(format: "%.1f", trend.percentageChange))%")
                            .font(.subheadline)
                    }
                }

                HStack(spacing: 20) {
                    VStack {
                        Text("\(String(format: "%.1f", viewModel.averageDosageStart))")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Jan-Mar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)

                    VStack {
                        Text("\(String(format: "%.1f", viewModel.averageDosageEnd))")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Oct-Dec")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var safetyInsightsCard: some View {
        RewindCard(title: "Safety Insights", icon: "heart.fill") {
            VStack(spacing: 12) {
                InsightItem(
                    icon: "clock.arrow.circlepath",
                    text: "You've taken breaks of \(viewModel.longestBreak) days between sessions",
                    color: .green
                )

                InsightItem(
                    icon: "drop.fill",
                    text: "Your dosage consistency score: \(viewModel.consistencyScore)%",
                    color: .blue
                )

                InsightItem(
                    icon: "calendar.badge.exclamationmark",
                    text: "Consider testing substances when possible",
                    color: .orange
                )
            }
        }
    }

    private var goofyStatsCard: some View {
        RewindCard(title: "Fun Stats", icon: "party.popper.fill") {
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    GoofyStatItem(
                        value: "\(viewModel.pillBottles)",
                        label: "Pill Bottles\nFilled",
                        icon: "pills.fill",
                        color: .purple
                    )

                    GoofyStatItem(
                        value: "\(viewModel.substanceMiles)",
                        label: "Substance\nMiles",
                        icon: "car.fill",
                        color: .orange
                    )

                    GoofyStatItem(
                        value: "\(viewModel.experimentPercentage)%",
                        label: "Experiment\nRate",
                        icon: "flask.fill",
                        color: .pink
                    )
                }

                Divider()

                VStack(spacing: 8) {
                    Text("You've used substances on \(viewModel.uniqueDaysUsed) different days this year")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if viewModel.weekendWarrior {
                        Text("🏆 Weekend Warrior!")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                    }
                }
            }
        }
    }

    private var achievementsCard: some View {
        RewindCard(title: "Achievements", icon: "trophy.fill") {
            VStack(spacing: 16) {
                // Achievement stats
                HStack(spacing: 20) {
                    AchievementStat(
                        value: "\(viewModel.earnedMedals.filter { $0.tier == .gold }.count)",
                        label: "Gold",
                        color: .yellow
                    )

                    AchievementStat(
                        value: "\(viewModel.earnedMedals.filter { $0.tier == .silver }.count)",
                        label: "Silver",
                        color: .gray
                    )

                    AchievementStat(
                        value: "\(viewModel.earnedMedals.filter { $0.tier == .bronze }.count)",
                        label: "Bronze",
                        color: .orange
                    )

                    AchievementStat(
                        value: "\(viewModel.earnedMedals.filter { $0.tier == .special }.count)",
                        label: "Special",
                        color: .purple
                    )
                }

                Divider()

                // Top achievements
                VStack(spacing: 12) {
                    AchievementItem(
                        title: "Substance Explorer",
                        description: "Discovered \(viewModel.uniqueSubstances) different substances",
                        icon: "binoculars.fill",
                        color: .blue,
                        unlocked: viewModel.uniqueSubstances >= 5
                    )

                    AchievementItem(
                        title: "Consistent User",
                        description: "Maintained \(viewModel.consistencyScore)% dosage consistency",
                        icon: "target",
                        color: .green,
                        unlocked: viewModel.consistencyScore >= 70
                    )

                    if showDetailedAchievements {
                        AchievementItem(
                            title: "Experience Writer",
                            description: "Documented \(viewModel.experiencesDocumented) personal experiences",
                            icon: "book.fill",
                            color: .purple,
                            unlocked: viewModel.experiencesDocumented >= 10
                        )

                        AchievementItem(
                            title: "Weekend Warrior",
                            description: "Most active on weekends",
                            icon: "moon.stars.fill",
                            color: .orange,
                            unlocked: viewModel.weekendWarrior
                        )
                    }
                }

                // Show more button
                if !showDetailedAchievements {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showDetailedAchievements = true
                        }
                    } label: {
                        Text("Show More Achievements")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                    }
                } else {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showDetailedAchievements = false
                        }
                    } label: {
                        Text("Show Less")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var pointsAndMedalsCard: some View {
        RewindCard(title: "Points & Medals", icon: "medal.fill") {
            VStack(spacing: 16) {
                // Total Points Display with enhanced shaders
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(Color.yellow.opacity(0.1))
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)
                        .opacity(showConfetti ? 1 : 0.3)
                        .animation(.easeInOut(duration: 1.0), value: showConfetti)

                    // Main circle with gradient
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.yellow.opacity(0.3),
                                    Color.yellow.opacity(0.1),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(showConfetti ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: showConfetti)

                    // Animated border with rainbow effect
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.red.opacity(showConfetti ? 0.8 : 0.3),
                                    Color.orange.opacity(showConfetti ? 0.8 : 0.3),
                                    Color.yellow.opacity(showConfetti ? 0.8 : 0.3),
                                    Color.green.opacity(showConfetti ? 0.8 : 0.3),
                                    Color.blue.opacity(showConfetti ? 0.8 : 0.3),
                                    Color.purple.opacity(showConfetti ? 0.8 : 0.3),
                                    Color.red.opacity(showConfetti ? 0.8 : 0.3)
                                ]),
                                center: .center
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(showConfetti ? 360 : 0))
                        .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: showConfetti)

                    // Inner shimmer effect
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 20, height: 20)
                        .offset(x: showConfetti ? 40 : -40, y: 0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: showConfetti)

                    VStack(spacing: 4) {
                        Text("\(animatedPoints)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.yellow)
                            .contentTransition(.numericText())
                            .shadow(color: .yellow.opacity(0.5), radius: showConfetti ? 10 : 0, x: 0, y: 0)
                            .scaleEffect(showConfetti ? 1.2 : 1.0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.5), value: showConfetti)

                        Text("Points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .shadow(color: .yellow.opacity(showConfetti ? 0.3 : 0), radius: showConfetti ? 5 : 0, x: 0, y: 0)
                    }
                }
                .padding(.bottom, 8)
                .onTapGesture {
                    // Celebrate points
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showConfetti.toggle()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            showConfetti = false
                        }
                    }
                }

                // Points Breakdown
                VStack(spacing: 8) {
                    HStack {
                        Text("Points Breakdown")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Text("Progress to next tier")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                                .cornerRadius(4)

                            Rectangle()
                                .fill(Color.yellow)
                                .frame(width: max(0, geometry.size.width * CGFloat(viewModel.nextMedalProgress)), height: 8)
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            PointsBreakdownItem(
                                label: "Ingestions",
                                points: viewModel.totalIngestions * 10,
                                color: .blue
                            )

                            PointsBreakdownItem(
                                label: "Substances",
                                points: viewModel.uniqueSubstances * 25,
                                color: .green
                            )

                            PointsBreakdownItem(
                                label: "Experiences",
                                points: viewModel.experiencesDocumented * 50,
                                color: .purple
                            )
                        }

                        HStack(spacing: 12) {
                            PointsBreakdownItem(
                                label: "Consistency",
                                points: viewModel.consistencyScore * 2,
                                color: .orange
                            )

                            PointsBreakdownItem(
                                label: "Breaks",
                                points: viewModel.longestBreak * 5,
                                color: .cyan
                            )

                            PointsBreakdownItem(
                                label: "Exploration",
                                points: viewModel.experimentPercentage * 3,
                                color: .pink
                            )
                        }
                    }
                }
                .padding(.horizontal)

                Divider()

                // Earned Medals
                if !viewModel.earnedMedals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Earned Medals")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(viewModel.earnedMedals.prefix(6), id: \.name) { medal in
                            MedalRow(medal: medal)
                        }

                        if viewModel.earnedMedals.count > 6 {
                            Text("+\(viewModel.earnedMedals.count - 6) more medals")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Keep using the app to earn your first medal!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
    }

    private var funFactsCard: some View {
        RewindCard(title: "Fun Facts", icon: "lightbulb.fill") {
            VStack(spacing: 12) {
                FunFactItem(
                    emoji: "📚",
                    text: "Your substance vocabulary includes \(viewModel.substanceVocabulary) unique terms"
                )

                FunFactItem(
                    emoji: "📅",
                    text: "\(viewModel.mostActiveWeekday) was your most active day"
                )

                FunFactItem(
                    emoji: "🌟",
                    text: "You've traveled approximately \(viewModel.substanceMiles) 'substance miles' this year"
                )

                if viewModel.longestBreak > 30 {
                    FunFactItem(
                        emoji: "🏖️",
                        text: "Your longest break was \(viewModel.longestBreak) days - that's a mini vacation!"
                    )
                } else {
                    FunFactItem(
                        emoji: "⚡",
                        text: "You kept things rolling with breaks no longer than \(viewModel.longestBreak) days"
                    )
                }
            }
        }
    }

    private func startCardAnimationSequence() {
        // Start with cards hidden
        animationStep = 0

        // Animate points counter immediately
        animatePointsCounter()

        // Animate cards appearing one by one
        for step in 1...14 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.15) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animationStep = step
                }
            }
        }

        // Show confetti if they have medals
        if !viewModel.earnedMedals.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showConfetti = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showConfetti = false
                    }
                }
            }
        }
    }

    private func animatePointsCounter() {
        let targetPoints = viewModel.totalPoints
        let duration = 2.0
        let steps = 60
        let stepDuration = duration / Double(steps)

        animatedPoints = 0 // Start from 0

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * stepDuration) {
                let progress = Double(i) / Double(steps)
                let easedProgress = 1 - pow(1 - progress, 3) // Ease out cubic
                animatedPoints = Int(Double(targetPoints) * easedProgress)
            }
        }
    }

}

struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []

    var body: some View {
        ZStack {
            ForEach(confettiPieces) { piece in
                ConfettiShape(shape: piece.shape)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size)
                    .position(piece.position)
                    .rotationEffect(.degrees(piece.rotation))
                    .opacity(piece.opacity)
            }
        }
        .onAppear {
            createConfetti()
        }
    }

    private func createConfetti() {
        confettiPieces = (0..<50).map { index in
            let startX = UIScreen.main.bounds.width / 2
            let startY = UIScreen.main.bounds.height / 2

            return ConfettiPiece(
                id: index,
                position: CGPoint(x: startX, y: startY),
                endPosition: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: UIScreen.main.bounds.height + 100
                ),
                color: [Color.red, Color.blue, Color.green, Color.yellow, Color.purple, Color.orange, Color.pink].randomElement()!,
                shape: ConfettiShape.Shape.allCases.randomElement()!,
                size: CGFloat.random(in: 6...12),
                rotation: Double.random(in: 0...360),
                opacity: 1.0,
                animationDelay: Double(index) * 0.05
            )
        }

        // Animate all pieces
        for i in 0..<confettiPieces.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + confettiPieces[i].animationDelay) {
                withAnimation(.easeOut(duration: Double.random(in: 3...5))) {
                    confettiPieces[i].position = confettiPieces[i].endPosition
                    confettiPieces[i].rotation += Double.random(in: 360...1080)
                    confettiPieces[i].opacity = 0.0
                }
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id: Int
    var position: CGPoint
    var endPosition: CGPoint
    var color: Color
    var shape: ConfettiShape.Shape
    var size: CGFloat
    var rotation: Double
    var opacity: Double
    var animationDelay: Double
}


struct ConfettiShape: Shape {
    enum Shape {
        case circle, square, triangle
        static var allCases: [Shape] = [.circle, .square, .triangle]
    }

    let shape: Shape

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch shape {
        case .circle:
            path.addEllipse(in: rect)
        case .square:
            path.addRect(rect)
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}

struct RewindCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    // Icon glow effect
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.blue.opacity(0.3))
                        .blur(radius: 4)

                    Image(systemName: icon)
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            content
        }
        .padding()
        .background(
            ZStack {
                // Glassmorphism effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.8))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .blur(radius: 20)
                    )

                // Inner glow
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .clear, .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .cornerRadius(16)
        .shadow(color: Color.blue.opacity(0.1), radius: 20, x: 0, y: 10)
        .shadow(color: Color.purple.opacity(0.05), radius: 40, x: 0, y: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.1), .purple.opacity(0.1), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

struct InsightItem: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }
}

struct GoofyStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 20))
            }

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AchievementItem: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let unlocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(unlocked ? color.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: unlocked ? icon : "lock.fill")
                    .foregroundColor(unlocked ? color : .gray)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(unlocked ? .primary : .secondary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if unlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(color)
                    .font(.system(size: 20))
            }
        }
        .opacity(unlocked ? 1.0 : 0.6)
    }
}

struct FunFactItem: View {
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 24))

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

struct MedalRow: View {
    let medal: Medal
    @State private var scale = 1.0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // Base circle
                Circle()
                    .fill(medal.tier.color.opacity(0.2))
                    .frame(width: 40, height: 40)

                // Glow effect for special medals
                if medal.tier == .special {
                    Circle()
                        .fill(medal.tier.color.opacity(0.4))
                        .frame(width: 50, height: 50)
                        .blur(radius: 6)
                        .scaleEffect(scale)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scale)

                    // Shimmer effect for special medals
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    medal.tier.color.opacity(0.0),
                                    medal.tier.color.opacity(0.8),
                                    medal.tier.color.opacity(0.0)
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: 45, height: 45)
                        .rotationEffect(.degrees(360))
                        .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: scale)
                        .opacity(0.3)
                }

                Image(systemName: medal.icon)
                    .foregroundColor(medal.tier.color)
                    .font(.system(size: 18))
                    .shadow(color: medal.tier == .special ? medal.tier.color.opacity(0.5) : Color.clear, radius: 4, x: 0, y: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(medal.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(medal.tier.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(medal.tier.color.opacity(0.2))
                        .foregroundColor(medal.tier.color)
                        .cornerRadius(8)
                }

                Text(medal.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .onAppear {
            if medal.tier == .special {
                scale = 1.1
            }
        }
    }
}

struct DoseResponseChart: View {
    let data: [DoseResponsePoint]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid lines
                Path { path in
                    // Vertical grid lines
                    for i in 0...10 {
                        let x = geometry.size.width * CGFloat(i) / 10
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    // Horizontal grid lines
                    for i in 0...10 {
                        let y = geometry.size.height * CGFloat(i) / 10
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                // Axis labels
                VStack {
                    Spacer()
                    HStack {
                        Text("Dosage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Response (Rating)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }

                // Data points
                ForEach(data.indices, id: \.self) { index in
                    let point = data[index]
                    let x = geometry.size.width * (point.dosage / maxDosage)
                    let y = geometry.size.height * (1 - point.response / 10) // Invert Y axis

                    // Point
                    Circle()
                        .fill(point.substanceColor.swiftUIColor.opacity(0.7))
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                        .overlay(
                            Circle()
                                .stroke(point.substanceColor.swiftUIColor.opacity(0.9), lineWidth: 1)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: y)
                        )
                }

                // Legend
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(uniqueSubstances.prefix(5), id: \.name) { substance in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(substance.color.swiftUIColor)
                                .frame(width: 8, height: 8)
                            Text(substance.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if uniqueSubstances.count > 5 {
                        Text("+\(uniqueSubstances.count - 5) more...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color(.systemBackground).opacity(0.8))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
            }
        }
    }

    private var maxDosage: Double {
        data.map { $0.dosage }.max() ?? 100
    }

    private var uniqueSubstances: [(name: String, color: SubstanceColor)] {
        let substances = data.map { ($0.substanceName, $0.substanceColor) }
        return Array(Set(substances.map { $0.0 })).compactMap { name in
            substances.first { $0.0 == name }.map { (name: $0.0, color: $0.1) }
        }
    }
}

struct PointsBreakdownItem: View {
    let label: String
    let points: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)

                Text("\(points)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MonthlyInsight: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(icon)
                .font(.title3)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SubstanceRow: View {
    let substance: SubstanceUsage

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Substance indicator
                ZStack {
                    Circle()
                        .fill(substance.color.swiftUIColor.opacity(0.2))
                        .frame(width: 16, height: 16)

                    Circle()
                        .fill(substance.color.swiftUIColor)
                        .frame(width: 8, height: 8)
                }

                // Substance name and stats
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(substance.count) uses • \(Int(substance.percentage * 100))% of total")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Rank indicator for top substances
                if substance.percentage > 0.1 {
                    Text("⭐")
                        .font(.caption)
                }
            }

            // Enhanced progress bar with shaders
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background with subtle pattern
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )

                    // Main progress bar with gradient
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    substance.color.swiftUIColor.opacity(0.8),
                                    substance.color.swiftUIColor.opacity(0.6),
                                    substance.color.swiftUIColor.opacity(0.4)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geometry.size.width * substance.percentage), height: 6)
                        .shadow(color: substance.color.swiftUIColor.opacity(0.3), radius: 2, x: 0, y: 1)

                    // Subtle shimmer effect
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 20, height: 6)
                        .offset(x: geometry.size.width * substance.percentage - 10)
                        .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: substance.percentage)
                }
            }
            .frame(height: 8)
        }
    }
}

struct SubstanceInsight: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.title2)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AchievementStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)

                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

extension MedalTier {
    var color: Color {
        switch self {
        case .bronze: return .orange
        case .silver: return .gray
        case .gold: return .yellow
        case .special: return .purple
        }
    }
}

struct RewindScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RewindScreen()
        }
    }
}
