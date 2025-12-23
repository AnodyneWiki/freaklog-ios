import Foundation
import CoreData
import Combine

/// A ViewModel managing basic pagination and grouping of `Ingestion` records from Core Data.
final class AllIngestionsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var sections: [IngestionSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasReachedEnd = false
    @Published var searchText: String = ""

    // MARK: - Private Properties
    
    private let context: NSManagedObjectContext
    private let pageSize = 50
    private var currentOffset = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    
    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.context = context
        setupSearchObserver()
        fetchNextBatch()
    }

    // MARK: - Public API
    
    /// Resets the stream and re-fetches data from the beginning.
    func resetAndFetch() {
        sections = []
        currentOffset = 0
        hasReachedEnd = false
        isLoading = false
        fetchNextBatch()
    }

    /// Fetches the next batch of results from Core Data.
    func fetchNextBatch() {
        guard !isLoading && !hasReachedEnd else { return }

        isLoading = true

        let request = createFetchRequest()
        request.fetchLimit = pageSize
        request.fetchOffset = currentOffset

        do {
            let newIngestions = try context.fetch(request)
            processFetchedResults(newIngestions)
        } catch {
            print("ERROR: [AllIngestionsViewModel] Failed to fetch: \(error.localizedDescription)")
        }

        isLoading = false
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
        if results.isEmpty {
            hasReachedEnd = true
            return
        }

        groupIngestions(results)
        currentOffset += results.count
        
        if results.count < pageSize {
            hasReachedEnd = true
        }
    }

    private func groupIngestions(_ newIngestions: [Ingestion]) {
        var updatedSections = sections

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
