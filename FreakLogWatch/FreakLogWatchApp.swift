import SwiftUI

@main
struct FreakLogWatchApp: App {
    init() {
        PersistenceController.shared.loadData()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
        }
    }
}
