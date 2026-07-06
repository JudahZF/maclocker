@testable import MacLocker
import XCTest

final class WatchScannerTests: XCTestCase {
    func testSelectedSignalEventDoesNotDependOnDisplayName() {
        let peripheralID = UUID()
        let timestamp = Date(timeIntervalSince1970: 100)

        let event = WatchScanner.signalEvent(
            peripheralID: peripheralID,
            selectedPeripheralID: peripheralID,
            rssi: -72,
            timestamp: timestamp
        )

        XCTAssertEqual(
            event,
            WatchSignalEvent(peripheralID: peripheralID, rssi: -72, timestamp: timestamp)
        )
    }

    func testSignalEventIgnoresUnselectedPeripheral() {
        let event = WatchScanner.signalEvent(
            peripheralID: UUID(),
            selectedPeripheralID: UUID(),
            rssi: -72,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(event)
    }
}
