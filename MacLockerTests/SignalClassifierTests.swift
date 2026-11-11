@testable import MacLocker
import XCTest

final class SignalClassifierTests: XCTestCase {
    private let peripheralID = UUID()

    func testRSSISmoothingBehavior() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -60, at: start), selectedPeripheralID: peripheralID)
        classifier.observe(event(rssi: -80, at: start.addingTimeInterval(1)), selectedPeripheralID: peripheralID)

        XCTAssertEqual(classifier.smoothedRSSI ?? 0, -67, accuracy: 0.001)
    }

    func testNoLockBeforeAwayHoldSeconds() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -80, at: start), selectedPeripheralID: peripheralID)

        _ = classifier.evaluate(at: start, settings: settings(), preconditions: readyPreconditions())
        let evaluation = classifier.evaluate(
            at: start.addingTimeInterval(19),
            settings: settings(),
            preconditions: readyPreconditions()
        )

        XCTAssertFalse(evaluation.shouldLock)
    }

    func testLockAfterSustainedWeakSignal() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -80, at: start), selectedPeripheralID: peripheralID)

        _ = classifier.evaluate(at: start, settings: settings(), preconditions: readyPreconditions())
        let evaluation = classifier.evaluate(
            at: start.addingTimeInterval(20),
            settings: settings(),
            preconditions: readyPreconditions()
        )

        XCTAssertTrue(evaluation.shouldLock)
    }

    func testLockAfterMissingSignalPlusAwayHold() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -55, at: start), selectedPeripheralID: peripheralID)

        _ = classifier.evaluate(at: start, settings: settings(), preconditions: readyPreconditions())
        _ = classifier.evaluate(at: start.addingTimeInterval(8), settings: settings(), preconditions: readyPreconditions())
        let evaluation = classifier.evaluate(
            at: start.addingTimeInterval(28),
            settings: settings(),
            preconditions: readyPreconditions()
        )

        XCTAssertTrue(evaluation.shouldLock)
    }

    func testNearHysteresisResetsAwayCountdown() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -80, at: start), selectedPeripheralID: peripheralID)
        _ = classifier.evaluate(at: start, settings: settings(), preconditions: readyPreconditions())

        for offset in 5 ... 15 {
            let timestamp = start.addingTimeInterval(TimeInterval(offset))
            classifier.observe(event(rssi: -45, at: timestamp), selectedPeripheralID: peripheralID)
            _ = classifier.evaluate(at: timestamp, settings: settings(), preconditions: readyPreconditions())
        }

        classifier.observe(event(rssi: -80, at: start.addingTimeInterval(16)), selectedPeripheralID: peripheralID)
        _ = classifier.evaluate(at: start.addingTimeInterval(16), settings: settings(), preconditions: readyPreconditions())
        let evaluation = classifier.evaluate(
            at: start.addingTimeInterval(35),
            settings: settings(),
            preconditions: readyPreconditions()
        )

        XCTAssertFalse(evaluation.shouldLock)
    }

    func testNeutralHysteresisBandContinuesAwayCountdown() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -80, at: start), selectedPeripheralID: peripheralID)
        _ = classifier.evaluate(at: start, settings: settings(), preconditions: readyPreconditions())

        var neutralEvaluation: SignalEvaluation?
        for offset in 1 ... 19 {
            let timestamp = start.addingTimeInterval(TimeInterval(offset))
            classifier.observe(event(rssi: -62, at: timestamp), selectedPeripheralID: peripheralID)
            neutralEvaluation = classifier.evaluate(at: timestamp, settings: settings(), preconditions: readyPreconditions())
        }

        if let neutralEvaluation {
            XCTAssertEqual(neutralEvaluation.state, .awayCountdown(1))
            XCTAssertGreaterThanOrEqual(neutralEvaluation.smoothedRSSI ?? -Double.infinity, -65)
            XCTAssertLessThan(neutralEvaluation.smoothedRSSI ?? Double.infinity, -59)
        } else {
            XCTFail("Expected a neutral-band evaluation before locking")
        }

        let lockTime = start.addingTimeInterval(20)
        classifier.observe(event(rssi: -62, at: lockTime), selectedPeripheralID: peripheralID)
        let evaluation = classifier.evaluate(at: lockTime, settings: settings(), preconditions: readyPreconditions())

        XCTAssertTrue(evaluation.shouldLock)
        XCTAssertEqual(evaluation.state, .locked)
    }

    func testNoLockWhenUncalibrated() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -80, at: start), selectedPeripheralID: peripheralID)

        var uncalibrated = settings()
        uncalibrated.rssiThreshold = nil
        let evaluation = classifier.evaluate(
            at: start.addingTimeInterval(100),
            settings: uncalibrated,
            preconditions: SignalPreconditions(
                isBluetoothReady: true,
                hasSelection: true,
                isCalibrated: false,
                isAutoLockEnabled: true,
                isPaused: false
            )
        )

        XCTAssertFalse(evaluation.shouldLock)
        XCTAssertEqual(evaluation.state, .uncalibrated)
    }

    func testNoLockWhenPaused() {
        var classifier = SignalClassifier()
        let start = Date(timeIntervalSince1970: 100)
        classifier.observe(event(rssi: -80, at: start), selectedPeripheralID: peripheralID)

        let evaluation = classifier.evaluate(
            at: start.addingTimeInterval(100),
            settings: settings(),
            preconditions: SignalPreconditions(
                isBluetoothReady: true,
                hasSelection: true,
                isCalibrated: true,
                isAutoLockEnabled: true,
                isPaused: true
            )
        )

        XCTAssertFalse(evaluation.shouldLock)
        XCTAssertEqual(evaluation.state, .paused)
    }

    private func event(rssi: Int, at date: Date) -> WatchSignalEvent {
        WatchSignalEvent(peripheralID: peripheralID, rssi: rssi, timestamp: date)
    }

    private func settings() -> LockSettings {
        LockSettings(
            selectedPeripheralID: peripheralID,
            rssiThreshold: -65,
            awayHoldSeconds: 20,
            missingSignalSeconds: 8,
            nearHoldSeconds: 8,
            graceAfterUnlockSeconds: 0,
            launchAtLogin: false,
            isAutoLockEnabled: true
        )
    }

    private func readyPreconditions() -> SignalPreconditions {
        SignalPreconditions(
            isBluetoothReady: true,
            hasSelection: true,
            isCalibrated: true,
            isAutoLockEnabled: true,
            isPaused: false
        )
    }
}
