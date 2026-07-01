import Foundation

struct LockSettings: Codable, Equatable {
    var selectedPeripheralID: UUID?
    var rssiThreshold: Int?
    var awayHoldSeconds: TimeInterval
    var missingSignalSeconds: TimeInterval
    var nearHoldSeconds: TimeInterval
    var graceAfterUnlockSeconds: TimeInterval
    var launchAtLogin: Bool
    var isAutoLockEnabled: Bool

    static let `default` = LockSettings(
        selectedPeripheralID: nil,
        rssiThreshold: nil,
        awayHoldSeconds: 20,
        missingSignalSeconds: 8,
        nearHoldSeconds: 8,
        graceAfterUnlockSeconds: 60,
        launchAtLogin: false,
        isAutoLockEnabled: false
    )
}
