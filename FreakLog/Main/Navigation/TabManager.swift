import SwiftUI

@MainActor
class TabManager: ObservableObject {
    static let shared = TabManager()
    
    private let defaults: UserDefaults
    
    @Published private(set) var hiddenTabs: Set<Tab> = [] {
        didSet {
            saveState()
        }
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadState()
    }
    
    var enabledTabs: [Tab] {
        Tab.allCases.filter { !hiddenTabs.contains($0) }
    }
    
    func setVisibility(for tab: Tab, isVisible: Bool) {
        guard !tab.isMandatory else { return }
        if isVisible {
            hiddenTabs.remove(tab)
        } else {
            hiddenTabs.insert(tab)
        }
    }
    
    private func saveState() {
        if let data = try? JSONEncoder().encode(hiddenTabs),
           let string = String(data: data, encoding: .utf8) {
            defaults.set(string, forKey: PersistenceController.hiddenTabsKey)
        }
    }
    
    // After the settings were replaced, e.g. by restoring a backup
    func reload() {
        loadState()
    }

    private func loadState() {
        if let string = defaults.string(forKey: PersistenceController.hiddenTabsKey),
           let data = string.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            // Older backups can still list the Safer tab.
            hiddenTabs = Set(decoded.compactMap(Tab.init(rawValue:)).filter { !$0.isMandatory })
        } else {
            hiddenTabs = []
        }
    }
}
