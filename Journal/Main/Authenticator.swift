import LocalAuthentication
import SwiftUI

@MainActor
class Authenticator: ObservableObject {
    static let hasToUnlockKey = "hasToUnlockApp"
    static let lockTimeOptionKey = "lockTimeOption"
    private static let lastDateKey = "lastDate"
    @Published var isLocked = true
    @Published var isFaceIDEnabled = true
    @Published var isStartingUp = true

    func onChange(of scenePhase: ScenePhase) {
        let hasToUnlockApp = UserDefaults.standard.bool(forKey: Authenticator.hasToUnlockKey)
        if scenePhase == .active {
            isStartingUp = false
            let context = LAContext()
            var error: NSError?
            let lockTimeOptionString = UserDefaults.standard.string(forKey: Authenticator.lockTimeOptionKey)
            let lockTimeOption = LockTimeOption(rawValue: lockTimeOptionString ?? "") ?? LockTimeOption.after5Minutes
            let lastDate = (UserDefaults.standard.object(forKey: Authenticator.lastDateKey) as? Date) ?? Date().addingTimeInterval(-2 * 60 * 60)
            let differenceNowToLastInSeconds = Date.now.timeIntervalSince1970 - lastDate.timeIntervalSince1970
            let isWithinToleratedTimeRange = differenceNowToLastInSeconds < lockTimeOption.timeInterval
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                isFaceIDEnabled = true
                // when the system shows the Face ID prompt the app moves to the background.
                // therefore this code gets executed before it is unlocked and after
                if hasToUnlockApp && isLocked && !isWithinToleratedTimeRange {
                    authenticate(with: context)
                }
            } else {
                isFaceIDEnabled = false
            }
            if !hasToUnlockApp || isWithinToleratedTimeRange {
                isLocked = false
            }
        } else if (scenePhase == .background || scenePhase == .inactive) && hasToUnlockApp && !isLocked {
            isLocked = true
            UserDefaults.standard.set(Date(), forKey: Authenticator.lastDateKey)
        }
    }

    private func authenticate(with context: LAContext) {
        let reason = "Authenticate yourself to see your journal."
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            if success {
                Task { @MainActor in
                    self.isLocked = false
                }
            }
        }
    }
}
