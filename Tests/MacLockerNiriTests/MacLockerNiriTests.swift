import XCTest

@testable import MacLockerNiriCore

final class MacLockerNiriTests: XCTestCase {
    func testCollectTargetSampleUsesInfoShapeAndStrongestRSSI() {
        let output = """
        Device AA:BB:CC:DD:EE:FF (public)
                Name: Apple Watch
                RSSI: -74
        [CHG] Device AA:BB:CC:DD:EE:FF RSSI: -69
        [CHG] Device 11:22:33:44:55:66 RSSI: -40
        """

        let sample = collectTargetSample(output, target: "AA:BB:CC:DD:EE:FF")

        XCTAssertEqual(sample.rssi, -69)
        XCTAssertEqual(sample.address, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(sample.matchedAddresses, Set(["AA:BB:CC:DD:EE:FF"]))
    }

    func testAwayTrackerRequiresConsecutiveAwaySamplesAndCanIgnoreMissing() {
        var tracker = AwayTracker(threshold: -80, requiredSamples: 2)

        var result = tracker.update(RssiSample(rssi: -85, address: "AA", readings: [], matchedAddresses: []))
        XCTAssertTrue(result.away)
        XCTAssertFalse(result.shouldLock)

        result = tracker.update(RssiSample(rssi: -70, address: "AA", readings: [], matchedAddresses: []))
        XCTAssertFalse(result.away)
        XCTAssertFalse(result.shouldLock)

        result = tracker.update(RssiSample(rssi: nil, address: nil, readings: [], matchedAddresses: []))
        XCTAssertTrue(result.away)
        XCTAssertFalse(result.shouldLock)

        result = tracker.update(RssiSample(rssi: -90, address: "AA", readings: [], matchedAddresses: []))
        XCTAssertTrue(result.away)
        XCTAssertTrue(result.shouldLock)

        var ignoreMissing = AwayTracker(threshold: -80, requiredSamples: 1, missingIsAway: false)
        result = ignoreMissing.update(RssiSample(rssi: nil, address: nil, readings: [], matchedAddresses: []))
        XCTAssertFalse(result.away)
        XCTAssertFalse(result.shouldLock)
    }
}
