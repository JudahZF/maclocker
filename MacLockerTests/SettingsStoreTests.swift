@testable import MacLocker
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testSettingsEncodeDecodeRoundTrip() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        let selectedID = UUID()
        store.settings = LockSettings(
            selectedPeripheralID: selectedID,
            rssiThreshold: -68,
            awayHoldSeconds: 21,
            missingSignalSeconds: 9,
            nearHoldSeconds: 7,
            graceAfterUnlockSeconds: 61,
            launchAtLogin: true,
            isAutoLockEnabled: true
        )

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings, store.settings)
        XCTAssertEqual(reloaded.settings.selectedPeripheralID, selectedID)
    }

    func testDecodeFailureIsObservable() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "LockSettings")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, .default)
        XCTAssertTrue(store.lastPersistenceError?.contains("Could not load settings") == true)
    }

    func testEncodeFailureIsObservable() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)

        store.settings = LockSettings(
            selectedPeripheralID: nil,
            rssiThreshold: nil,
            awayHoldSeconds: .infinity,
            missingSignalSeconds: 8,
            nearHoldSeconds: 8,
            graceAfterUnlockSeconds: 60,
            launchAtLogin: false,
            isAutoLockEnabled: false
        )

        XCTAssertTrue(store.lastPersistenceError?.contains("Could not save settings") == true)
        XCTAssertNil(defaults.data(forKey: "LockSettings"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let defaultsName = "MacLockerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        return defaults
    }
}
