import SwiftUI

@MainActor
class TabManager: ObservableObject {
    static let shared = TabManager()
    
    private let storageKey = PersistenceController.hiddenTabsKey
    
    @Published private(set) var hiddenTabs: Set<Tab> = [] {
        didSet {
            saveState()
        }
    }
    
    private init() {
        loadState()
    }
    
    var enabledTabs: [Tab] {
        Tab.allCases.filter { !hiddenTabs.contains($0) }
    }
    
    var disabledTabs: [Tab] {
        Tab.allCases.filter { hiddenTabs.contains($0) }
    }
    
    func toggleVisibility(for tab: Tab) {
        guard !tab.isMandatory else { return }
        
        if hiddenTabs.contains(tab) {
            hiddenTabs.remove(tab)
        } else {
            hiddenTabs.insert(tab)
        }
    }
    
    private func saveState() {
        if let data = try? JSONEncoder().encode(hiddenTabs),
           let string = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(string, forKey: storageKey)
        }
    }
    
    // After the settings were replaced, e.g. by restoring a backup
    func reload() {
        loadState()
    }

    private func loadState() {
        if let string = UserDefaults.standard.string(forKey: storageKey),
           let data = string.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Set<Tab>.self, from: data) {
            self.hiddenTabs = decoded
        } else {
            self.hiddenTabs = []
        }
    }
}
