@testable import MacLocker
import XCTest

final class LockControllerTests: XCTestCase {
    func testLockControllerUsesImmediateLockWhenAccessibilityIsAvailable() async throws {
        let immediate = RecordingLocker(capability: .immediate(accessibilityTrusted: true))
        let fallback = RecordingLocker(
            capability: .displaySleepFallback(passwordRequired: true, passwordDelay: 30, warning: "fallback")
        )
        let controller = LockController(immediateLocker: immediate, fallbackLocker: fallback)

        try await controller.lockNow()

        XCTAssertEqual(immediate.lockCount, 1)
        XCTAssertEqual(fallback.lockCount, 0)
    }

    func testLockControllerFallsBackWhenAccessibilityIsUnavailable() async throws {
        let immediate = RecordingLocker(capability: .immediate(accessibilityTrusted: false))
        let fallback = RecordingLocker(
            capability: .displaySleepFallback(passwordRequired: true, passwordDelay: 30, warning: "fallback")
        )
        let controller = LockController(immediateLocker: immediate, fallbackLocker: fallback)

        try await controller.lockNow()

        XCTAssertEqual(immediate.lockCount, 0)
        XCTAssertEqual(fallback.lockCount, 1)
    }
}

private final class RecordingLocker: ScreenLocking, @unchecked Sendable {
    private let capabilityValue: LockCapability
    private(set) var lockCount = 0

    init(capability: LockCapability) {
        capabilityValue = capability
    }

    func lockNow() async throws {
        lockCount += 1
    }

    func capability() -> LockCapability {
        capabilityValue
    }
}
