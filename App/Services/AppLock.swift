import Foundation
import LocalAuthentication
import Observation

/// Optionale App-Sperre mit Face ID / Touch ID / Gerätecode.
@MainActor
@Observable
final class AppLock {
    var isLocked: Bool = Prefs.defaults.bool(forKey: Prefs.appLockEnabled)
    var errorMessage: String?

    var isEnabled: Bool { Prefs.defaults.bool(forKey: Prefs.appLockEnabled) }

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Ohne Gerätecode gibt es nichts, womit gesperrt werden könnte.
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Kaufarchiv entsperren")
            if success {
                isLocked = false
                errorMessage = nil
            }
        } catch {
            errorMessage = "Entsperren abgebrochen."
        }
    }

    /// Prüft vor dem Einschalten, ob das Gerät überhaupt entsperren kann.
    static var canProtect: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
}
