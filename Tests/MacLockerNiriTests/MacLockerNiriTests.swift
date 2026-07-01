import Foundation
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

    func testParseOptionsIncludesTrayModeInHelp() throws {
        let options = try parseOptions(["maclocker-niri", "--tray"])

        XCTAssertEqual(options.trayAction, .menu)
        XCTAssertTrue(usageText.contains("--tray"))
    }

    func testTrayConfigRoundTripAndMonitorArguments() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = directory.appendingPathComponent("config.json")
        let config = MacLockerNiriConfig(
            device: "AA:BB:CC:DD:EE:FF",
            threshold: -74,
            awaySamples: 2,
            sampleSeconds: 4,
            interval: 8,
            cooldown: 120,
            lockCommand: "swaylock -f",
            ignoreMissing: true,
            dryRun: true
        )

        try saveMacLockerNiriConfig(config, to: configURL)

        XCTAssertEqual(try loadMacLockerNiriConfig(from: configURL), config)
        XCTAssertEqual(
            try monitorArguments(executable: "/bin/maclocker-niri", config: config),
            [
                "/bin/maclocker-niri",
                "--device", "AA:BB:CC:DD:EE:FF",
                "--threshold", "-74",
                "--away-samples", "2",
                "--sample-seconds", "4",
                "--interval", "8",
                "--cooldown", "120",
                "--lock-command", "swaylock -f",
                "--ignore-missing",
                "--dry-run",
            ]
        )
    }

    func testParseTraySettingsOutputValidatesAndBuildsConfig() throws {
        let output = "Apple Watch|-72|2|4.5|8|120|swaylock -f|TRUE|FALSE|bluetoothctl|\n"

        let config = try parseTraySettingsOutput(output, fallback: MacLockerNiriConfig())

        XCTAssertEqual(config.device, "Apple Watch")
        XCTAssertEqual(config.threshold, -72)
        XCTAssertEqual(config.awaySamples, 2)
        XCTAssertEqual(config.sampleSeconds, 4.5)
        XCTAssertEqual(config.interval, 8)
        XCTAssertEqual(config.cooldown, 120)
        XCTAssertEqual(config.lockCommand, "swaylock -f")
        XCTAssertTrue(config.ignoreMissing)
        XCTAssertFalse(config.dryRun)
    }

    func testYadNotificationMenuRunsSameExecutableActions() {
        let arguments = yadNotificationArguments(executable: "/tmp/mac locker", running: false)
        let menu = arguments.first { $0.hasPrefix("--menu=") } ?? ""

        XCTAssertTrue(menu.contains("Settings!'/tmp/mac locker' --tray-settings"))
        XCTAssertTrue(menu.contains("Start!'/tmp/mac locker' --tray-start"))
        XCTAssertTrue(menu.contains("Stop!'/tmp/mac locker' --tray-stop"))
        XCTAssertTrue(arguments.contains("--text=MacLocker Niri (stopped)"))
    }
}
