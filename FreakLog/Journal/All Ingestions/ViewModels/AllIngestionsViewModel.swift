import Foundation
import CoreData
import Combine

/// A ViewModel managing basic pagination and grouping of `Ingestion` records from Core Data.
final class AllIngestionsViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var sections: [IngestionSection] = []
    @Published private(set) var timelineIngestions: [Ingestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasReachedEnd = false
    @Published var searchText: String = ""

    // MARK: - Private Properties
    
    private let context: NSManagedObjectContext
    private let pageSize = 50
    private var currentOffset = 0
    private var cancellables = Set<AnyCancellable>()
    private var fetchedResultsController: NSFetchedResultsController<Ingestion>?

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
        isLoading = false
        setupFetchedResultsController()
    }

    /// Fetches the next batch of results from Core Data.
    func fetchNextBatch() {
        guard !isLoading && !hasReachedEnd else { return }

        isLoading = true
        currentOffset += pageSize
        
        // Update fetch limit and perform fetch
        fetchedResultsController?.fetchRequest.fetchLimit = currentOffset
        
        do {
            try fetchedResultsController?.performFetch()
            if let results = fetchedResultsController?.fetchedObjects {
                processFetchedResults(results)
            }
        } catch {
            print("ERROR: [AllIngestionsViewModel] Failed to fetch next batch: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Deletes an ingestion from Core Data.
    func delete(_ ingestion: Ingestion) {
        let objectID = ingestion.objectID
        Task {
            await FinishIngestionScreen.deleteWebhookMessageIfNeeded(forID: objectID)
            await MainActor.run {
                if let ingestionToDelete = try? context.existingObject(with: objectID) as? Ingestion {
                    context.delete(ingestionToDelete)
                    do {
                        try context.save()
                    } catch {
                        print("ERROR: [AllIngestionsViewModel] Failed to delete ingestion: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Returns ingestions for the configured dynamic range relative to the given ingestion.
    func getIngestionsForDynamicExperience(for ingestion: Ingestion) -> [Ingestion] {
        let anchorTime = ingestion.timeUnwrapped
        let hours = UserDefaults.standard.integer(forKey: PersistenceController.dynamicExperienceRangeHoursKey)
        let rangeHours = hours > 0 ? hours : 24
        let startDate = anchorTime.addingTimeInterval(-TimeInterval(rangeHours) * 60 * 60)
        let endDate = anchorTime
        
        return PersistenceController.shared.getIngestionsBetween(startDate: startDate, endDate: endDate)
    }

    func getIngestionsForDynamicExperienceLastIngestion(for date: Date) -> [Ingestion] {
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
        let startOfDay = Calendar.current.startOfDay(for: date)
        
        let request: NSFetchRequest<Ingestion> = Ingestion.fetchRequest()
        request.predicate = NSPredicate(format: "time >= %@ AND time <= %@", startOfDay as NSDate, endOfDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)]
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
        let request: NSFetchRequest<Ingestion> = Ingestion.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)]
        
        if !searchText.isEmpty {
            let predicates = [
                NSPredicate(format: "substanceName CONTAINS[cd] %@", searchText),
                NSPredicate(format: "note CONTAINS[cd] %@", searchText),
                NSPredicate(format: "consumerName CONTAINS[cd] %@", searchText)
            ]
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        }
        
        return request
    }

    private func processFetchedResults(_ results: [Ingestion]) {
        if results.isEmpty && currentOffset > pageSize {
            hasReachedEnd = true
            return
        }

        groupIngestions(results)
        
        if results.count < currentOffset {
            hasReachedEnd = true
        } else {
            hasReachedEnd = false
        }
        
        updateTimelineIngestions()
    }

    private func groupIngestions(_ newIngestions: [Ingestion]) {
        var updatedSections: [IngestionSection] = []

        for ingestion in newIngestions {
            let date = ingestion.timeUnwrapped
            let startOfDay = Calendar.current.startOfDay(for: date)
            let sectionId = dateToSectionId(startOfDay)

            if let index = updatedSections.firstIndex(where: { $0.id == sectionId }) {
                if !updatedSections[index].ingestions.contains(where: { $0.objectID == ingestion.objectID }) {
                    updatedSections[index].ingestions.append(ingestion)
                }
            } else {
                let newSection = IngestionSection(id: sectionId, date: startOfDay, ingestions: [ingestion])
                updatedSections.append(newSection)
            }
        }
        
        updatedSections.sort { $0.date > $1.date }
        self.sections = updatedSections
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
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let results = controller.fetchedObjects as? [Ingestion] {
            DispatchQueue.main.async {
                self.processFetchedResults(results)
            }
        }
    }
}
