import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var settings: LockSettings {
        didSet {
            save()
        }
    }

    @Published private(set) var lastPersistenceError: String?

    private let defaults: UserDefaults
    private let key = "LockSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do {
                settings = try JSONDecoder().decode(LockSettings.self, from: data)
            } catch {
                settings = .default
                lastPersistenceError = "Could not load settings: \(error.localizedDescription)"
            }
        } else {
            settings = .default
        }
    }

    func reset() {
        settings = .default
    }

    func save() {
        let data: Data
        do {
            data = try JSONEncoder().encode(settings)
        } catch {
            lastPersistenceError = "Could not save settings: \(error.localizedDescription)"
            return
        }

        defaults.set(data, forKey: key)
        lastPersistenceError = nil
    }
}
