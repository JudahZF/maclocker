@testable import MacLocker
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testSettingsEncodeDecodeRoundTrip() throws {
        let defaultsName = "MacLockerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)

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
}
