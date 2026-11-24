import Foundation
import CoreData
import Combine

/// A ViewModel managing basic pagination and grouping of `Ingestion` records from Core Data,
/// with the timed notes of the loaded days in between.
final class AllIngestionsViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var sections: [IngestionSection] = []
    @Published private(set) var timelineIngestions: [Ingestion] = []
    @Published private(set) var hasReachedEnd = false
    @Published var searchText: String = ""
    // Only ingestions of experiences marked as favorite, like the favorite filter of the experience list
    @Published var isFavoriteFilterEnabled = false

    // MARK: - Private Properties
    
    private let context: NSManagedObjectContext
    private let pageSize = 50
    private var currentOffset = 0
    private var cancellables = Set<AnyCancellable>()
    private var fetchedResultsController: NSFetchedResultsController<Ingestion>?
    // There are few timed notes, so all matching ones are fetched and only those of the loaded range shown
    private var timedNotesController: NSFetchedResultsController<TimedNote>?

    // MARK: - Initialization
    
    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.context = context
        super.init()
        setupSearchObserver()
        setupFetchedResultsController()
    }

    // MARK: - Public API
    
    /// Resets the stream and re-fetches data from the beginning.
    func resetAndFetch() {
        sections = []
        currentOffset = 0
        hasReachedEnd = false
        setupFetchedResultsController()
    }

    /// Fetches the next batch of results from Core Data.
    func fetchNextBatch() {
        guard !hasReachedEnd else { return }

        currentOffset += pageSize
        fetchedResultsController?.fetchRequest.fetchLimit = currentOffset
        
        do {
            try fetchedResultsController?.performFetch()
            if let results = fetchedResultsController?.fetchedObjects {
                processFetchedResults(results)
            }
        } catch {
            print("ERROR: [AllIngestionsViewModel] Failed to fetch next batch: \(error.localizedDescription)")
        }
    }

    /// Deletes an ingestion from Core Data.
    func delete(_ ingestion: Ingestion) {
        Task {
            await IngestionDeletion.delete(ingestions: [ingestion])
        }
    }

    func delete(_ timedNote: TimedNote) {
        timedNote.experience?.objectWillChange.send()
        context.delete(timedNote)
        PersistenceController.shared.saveViewContext()
    }

    /// Returns ingestions for the configured dynamic range relative to the given ingestion.
    func getIngestionsForDynamicExperience(for ingestion: Ingestion) -> [Ingestion] {
        let anchorTime = ingestion.timeUnwrapped
        let rangeHours = DynamicRangeOption.current.rawValue
        // Extend the start date by 24 hours (or another buffer) to catch ingestions started before the window
        // but whose effects might bleed into it.
        let bufferHours: Double = 24
        let startDate = anchorTime.addingTimeInterval(-TimeInterval(rangeHours + Int(bufferHours)) * 60 * 60)
        let endDate = anchorTime
        
        return PersistenceController.shared.getIngestionsBetween(startDate: startDate, endDate: endDate)
    }

    func getIngestionsForDynamicExperienceLastIngestion(for date: Date) -> [Ingestion] {
        let request = PersistenceController.ingestionsRequest(for: date)
        request.fetchLimit = 1

        do {
            if let lastIngestion = try PersistenceController.shared.viewContext.fetch(request).first {
                return getIngestionsForDynamicExperience(for: lastIngestion)
            }
        } catch {
            print("ERROR: Failed to fetch last ingestion for day: \(error)")
        }
        
        return []
    }

    /// Updates the ingestions used for the top timeline chart.
    func updateTimelineIngestions() {
        guard let latestIngestion = fetchedResultsController?.fetchedObjects?.first else {
            timelineIngestions = []
            return
        }
        timelineIngestions = getIngestionsForDynamicExperience(for: latestIngestion)
    }

    // MARK: - Private Methods
    
    private func setupSearchObserver() {
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetAndFetch()
            }
            .store(in: &cancellables)
        // Published values reach subscribers before they are stored, so the refetch waits a run loop turn
        $isFavoriteFilterEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetAndFetch()
            }
            .store(in: &cancellables)
    }

    private func setupFetchedResultsController() {
        let request = createFetchRequest()
        request.fetchLimit = pageSize
        currentOffset = pageSize
        
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        fetchedResultsController?.delegate = self

        timedNotesController = NSFetchedResultsController(
            fetchRequest: createTimedNotesFetchRequest(),
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        timedNotesController?.delegate = self
        do {
            try timedNotesController?.performFetch()
        } catch {
            print("ERROR: [AllIngestionsViewModel] Failed to fetch timed notes: \(error.localizedDescription)")
        }

        do {
            try fetchedResultsController?.performFetch()
            if let results = fetchedResultsController?.fetchedObjects {
                sections = []
                processFetchedResults(results)
            }
        } catch {
            print("ERROR: [AllIngestionsViewModel] Failed to initial fetch: \(error.localizedDescription)")
        }
    }

    private func createFetchRequest() -> NSFetchRequest<Ingestion> {
        let request = PersistenceController.ingestionsRequest()
        var predicates: [NSPredicate] = []
        if isFavoriteFilterEnabled {
            predicates.append(NSPredicate(format: "experience.isFavorite == YES"))
        }
        if !searchText.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "substanceName CONTAINS[cd] %@", searchText),
                NSPredicate(
                    format: "substanceName IN %@",
                    PersistenceController.shared.substanceNames(withDisplayNameContaining: searchText)
                ),
                NSPredicate(format: "note CONTAINS[cd] %@", searchText),
                NSPredicate(format: "consumerName CONTAINS[cd] %@", searchText),
            ]))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        return request
    }

    // Matches the ingestion filters: the note text instead of the substance, and favorite experiences
    private func createTimedNotesFetchRequest() -> NSFetchRequest<TimedNote> {
        let request = PersistenceController.timedNotesRequest()
        var predicates: [NSPredicate] = []
        if isFavoriteFilterEnabled {
            predicates.append(NSPredicate(format: "experience.isFavorite == YES"))
        }
        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "note CONTAINS[cd] %@", searchText))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        return request
    }

    private func processFetchedResults(_ results: [Ingestion]) {
        hasReachedEnd = results.count < currentOffset
        groupIngestions(results)
        updateTimelineIngestions()
    }

    private func groupIngestions(_ ingestions: [Ingestion]) {
        // Older notes show up once the ingestions around them are loaded
        let oldestLoadedTime = hasReachedEnd ? nil : ingestions.last?.timeUnwrapped
        let timedNotes = (timedNotesController?.fetchedObjects ?? []).filter { timedNote in
            oldestLoadedTime.map { timedNote.timeUnwrapped >= $0 } ?? true
        }
        let items = ingestions.map(IngestionSection.Item.ingestion) + timedNotes.map(IngestionSection.Item.timedNote)
        sections = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.time) }
            .map { day, items in
                IngestionSection(id: dateToSectionId(day), date: day, items: items.sorted { $0.time > $1.time })
            }
            .sorted { $0.date > $1.date }
    }

    private func dateToSectionId(_ date: Date) -> String {
        Self.sectionDateFormatter.string(from: date)
    }

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - NSFetchedResultsControllerDelegate

extension AllIngestionsViewModel: NSFetchedResultsControllerDelegate {
    // Called for both ingestions and timed notes
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async {
            self.processFetchedResults(self.fetchedResultsController?.fetchedObjects ?? [])
        }
    }
}
