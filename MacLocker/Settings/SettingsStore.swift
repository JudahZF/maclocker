import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var settings: LockSettings {
        didSet {
            save()
        }
    }

    private let defaults: UserDefaults
    private let key = "LockSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(LockSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func reset() {
        settings = .default
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
