import AppKit
import ApplicationServices
import Foundation

enum ImmediateShortcutLockerError: LocalizedError {
    case accessibilityPermissionRequired
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required for immediate Lock Screen."
        case .eventCreationFailed:
            "Unable to create the Lock Screen keyboard shortcut event."
        }
    }
}

struct ImmediateShortcutLocker: ScreenLocking {
    func lockNow() async throws {
        guard Self.isAccessibilityTrusted(prompt: false) else {
            throw ImmediateShortcutLockerError.accessibilityPermissionRequired
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false)
        else {
            throw ImmediateShortcutLockerError.eventCreationFailed
        }

        let flags: CGEventFlags = [.maskCommand, .maskControl]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func capability() -> LockCapability {
        let trusted = Self.isAccessibilityTrusted(prompt: false)
        return .immediate(accessibilityTrusted: trusted)
    }

    static func requestAccessibilityPermission() {
        _ = isAccessibilityTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
