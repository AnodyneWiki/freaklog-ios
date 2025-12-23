import SwiftUI
import CoreData

struct TimelineOverview: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    
    @State private var days: [Date] = []
    @State private var groupedIngestions: [Date: [Ingestion]] = [:]
    @State private var groupedRatings: [Date: [ShulginRating]] = [:]
    @State private var groupedNotes: [Date: [TimedNote]] = [:]
    @State private var globalSubstanceMaxes: [String: Double] = [:]
    @State private var isLoading = true
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ingestion Timeline")
                .font(.headline)
                .padding(.bottom, 8)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
            } else if days.isEmpty {
                emptyView
            } else {
                timelineView
            }
        }
        .task {
            await loadData()
        }
    }
    
    @ViewBuilder
    private var timelineView: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            TimelineDayBin(
                                day: day,
                                ingestions: groupedIngestions[day] ?? [],
                                ratings: groupedRatings[day] ?? [],
                                notes: groupedNotes[day] ?? [],
                                globalSubstanceMaxes: globalSubstanceMaxes,
                                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                                areRedosesDrawnIndividually: areRedosesDrawnIndividually
                            )
                            .frame(width: geo.size.width)
                            .id(day)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .onAppear {
                    scrollToDefaultPosition(proxy: proxy)
                }
            }
        }
        .frame(height: 250)
    }
    
    private var emptyView: some View {
        VStack {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No data available")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func loadData() async {
        do {
            // First pass: get the date range and global maxes
            let request: NSFetchRequest<Ingestion> = Ingestion.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Ingestion.time, ascending: true)]
            let allIngestions = try viewContext.fetch(request)
            
            guard let first = allIngestions.first?.time else {
                await MainActor.run { isLoading = false }
                return
            }
            
            let last = allIngestions.last?.time ?? .now
            let now = Date.now
            let isRecent = now.timeIntervalSince(last) < (12 * 60 * 60)
            
            let startOfRange = calendar.startOfDay(for: first)
            let endOfRange = calendar.startOfDay(for: isRecent ? now : last)
            
            var tempDays: [Date] = []
            var current = startOfRange
            while current <= endOfRange {
                tempDays.append(current)
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            
            var substanceMaxes: [String: Double] = [:]
            for ingestion in allIngestions {
                let name = ingestion.substanceNameUnwrapped
                let substance = SubstanceRepo.shared.getSubstance(name: name)
                let route = ingestion.administrationRouteUnwrapped
                let roaDose = substance?.getDose(for: route)
                
                let dose = ingestion.pureSubstanceDose ?? 0
                let strength = roaDose?.getStrengthRelativeToCommonDose(dose: dose) ?? 1.0
                substanceMaxes[name] = max(substanceMaxes[name] ?? 0, strength)
            }
            
            // Second pass: fetch all relevant data at once
            let ratingsRequest: NSFetchRequest<ShulginRating> = ShulginRating.fetchRequest()
            ratingsRequest.predicate = NSPredicate(format: "time >= %@ AND time < %@", startOfRange as NSDate, calendar.date(byAdding: .day, value: 1, to: endOfRange)! as NSDate)
            let allRatings = try viewContext.fetch(ratingsRequest)
            
            let notesRequest: NSFetchRequest<TimedNote> = TimedNote.fetchRequest()
            notesRequest.predicate = NSPredicate(format: "time >= %@ AND time < %@ AND isPartOfTimeline == YES", startOfRange as NSDate, calendar.date(byAdding: .day, value: 1, to: endOfRange)! as NSDate)
            let allNotes = try viewContext.fetch(notesRequest)
            
            // Group data by day
            var newGroupedIngestions: [Date: [Ingestion]] = [:]
            for ingestion in allIngestions {
                let day = calendar.startOfDay(for: ingestion.timeUnwrapped)
                newGroupedIngestions[day, default: []].append(ingestion)
                
                // If ingestion has an endTime that spans into next days, add to those days too
                if let endTime = ingestion.endTime {
                    var nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
                    while nextDay <= calendar.startOfDay(for: endTime) {
                        newGroupedIngestions[nextDay, default: []].append(ingestion)
                        guard let next = calendar.date(byAdding: .day, value: 1, to: nextDay) else { break }
                        nextDay = next
                    }
                }
            }
            
            var newGroupedRatings: [Date: [ShulginRating]] = [:]
            for rating in allRatings {
                if let time = rating.time {
                    let day = calendar.startOfDay(for: time)
                    newGroupedRatings[day, default: []].append(rating)
                }
            }
            
            var newGroupedNotes: [Date: [TimedNote]] = [:]
            for note in allNotes {
                if let time = note.time {
                    let day = calendar.startOfDay(for: time)
                    newGroupedNotes[day, default: []].append(note)
                }
            }
            
            await MainActor.run {
                self.days = tempDays
                self.groupedIngestions = newGroupedIngestions
                self.groupedRatings = newGroupedRatings
                self.groupedNotes = newGroupedNotes
                self.globalSubstanceMaxes = substanceMaxes
                self.isLoading = false
            }
        } catch {
            print("Failed to load timeline data: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
    
    private func scrollToDefaultPosition(proxy: ScrollViewProxy) {
        let today = calendar.startOfDay(for: .now)
        if days.contains(today) {
            proxy.scrollTo(today, anchor: .center)
        } else if let last = days.last {
            proxy.scrollTo(last, anchor: .center)
        }
    }
}

struct TimelineDayBin: View {
    let day: Date
    let ingestions: [Ingestion]
    let ratings: [ShulginRating]
    let notes: [TimedNote]
    let globalSubstanceMaxes: [String: Double]
    let areSubstanceHeightsIndependent: Bool
    let areRedosesDrawnIndividually: Bool
    
    @State private var timelineModel: TimelineModel?
    
    var body: some View {
        VStack(spacing: 0) {
            if let model = timelineModel {
                EffectTimeline(
                    timelineModel: model,
                    height: 220,
                    timeDisplayStyle: .regular,
                    isShowingCurrentTime: Calendar.current.isDateInToday(day)
                )
                .overlay(alignment: .topLeading) {
                    Text(day, format: .dateTime.weekday(.abbreviated).day().month())
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            } else {
                Color.clear
                    .frame(height: 220)
                    .overlay(alignment: .topLeading) {
                        Text(day, format: .dateTime.weekday(.abbreviated).day().month())
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(8)
                    }
            }
        }
        .onAppear { updateModel() }
        .onChange(of: ingestions) { _ in updateModel() }
        .onChange(of: areSubstanceHeightsIndependent) { _ in updateModel() }
        .onChange(of: areRedosesDrawnIndividually) { _ in updateModel() }
    }
    
    private func updateModel() {
        if ingestions.isEmpty && ratings.isEmpty && notes.isEmpty {
            timelineModel = nil
            return
        }
        
        let substanceGroups = getSubstanceIngestionGroups(ingestions: ingestions)
        let ratingDrawables = ratings.map { EverythingForOneRating(time: $0.timeUnwrapped, option: $0.optionUnwrapped) }
        let noteDrawables = notes.map { EverythingForOneTimedNote(time: $0.timeUnwrapped, color: $0.color) }
        
        timelineModel = TimelineModel(
            substanceGroups: substanceGroups,
            everythingForEachRating: ratingDrawables,
            everythingForEachTimedNote: noteDrawables,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            forcedStartTime: day,
            forcedTotalWidth: 24 * 60 * 60,
            globalSubstanceMaxes: globalSubstanceMaxes
        )
    }
}
