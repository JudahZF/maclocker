import Foundation

enum LockCapabilityMode: String, Equatable {
    case immediateShortcut
    case displaySleepFallback
}

struct LockCapability: Equatable {
    var mode: LockCapabilityMode
    var accessibilityTrusted: Bool
    var passwordRequired: Bool?
    var passwordDelay: TimeInterval?
    var warning: String?

    static func immediate(accessibilityTrusted: Bool, warning: String? = nil) -> LockCapability {
        LockCapability(
            mode: .immediateShortcut,
            accessibilityTrusted: accessibilityTrusted,
            passwordRequired: nil,
            passwordDelay: nil,
            warning: warning
        )
    }

    static func displaySleepFallback(
        accessibilityTrusted: Bool = false,
        passwordRequired: Bool?,
        passwordDelay: TimeInterval?,
        warning: String?
    ) -> LockCapability {
        LockCapability(
            mode: .displaySleepFallback,
            accessibilityTrusted: accessibilityTrusted,
            passwordRequired: passwordRequired,
            passwordDelay: passwordDelay,
            warning: warning
        )
    }
}

protocol ScreenLocking: Sendable {
    func lockNow() async throws
    func capability() -> LockCapability
}

final class LockController: ScreenLocking, @unchecked Sendable {
    private let immediateLocker: ScreenLocking
    private let fallbackLocker: ScreenLocking

    init(
        immediateLocker: ScreenLocking = ImmediateShortcutLocker(),
        fallbackLocker: ScreenLocking = DisplaySleepLocker()
    ) {
        self.immediateLocker = immediateLocker
        self.fallbackLocker = fallbackLocker
    }

    func lockNow() async throws {
        if immediateLocker.capability().accessibilityTrusted {
            try await immediateLocker.lockNow()
        } else {
            try await fallbackLocker.lockNow()
        }
    }

    func capability() -> LockCapability {
        let immediateCapability = immediateLocker.capability()
        if immediateCapability.accessibilityTrusted {
            return immediateCapability
        }
        return fallbackLocker.capability()
    }
}
