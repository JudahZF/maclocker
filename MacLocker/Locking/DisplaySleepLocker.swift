import Foundation

enum DisplaySleepLockerError: LocalizedError {
    case commandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(status):
            "Display sleep command failed with status \(status)."
        }
    }
}

struct DisplaySleepLocker: ScreenLocking {
    struct PasswordSettings: Equatable {
        var askForPassword: Bool?
        var delay: TimeInterval?
    }

    func lockNow() async throws {
        _ = Self.readPasswordSettings()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DisplaySleepLockerError.commandFailed(process.terminationStatus)
        }
    }

    func capability() -> LockCapability {
        let passwordSettings = Self.readPasswordSettings()
        return .displaySleepFallback(
            passwordRequired: passwordSettings.askForPassword,
            passwordDelay: passwordSettings.delay,
            warning: Self.warning(for: passwordSettings)
        )
    }

    static func readPasswordSettings() -> PasswordSettings {
        let domain = "com.apple.screensaver" as CFString
        let askValue = CFPreferencesCopyAppValue("askForPassword" as CFString, domain) as? NSNumber
        let delayValue = CFPreferencesCopyAppValue("askForPasswordDelay" as CFString, domain) as? NSNumber
        return PasswordSettings(
            askForPassword: askValue?.boolValue,
            delay: delayValue?.doubleValue
        )
    }

    private static func warning(for settings: PasswordSettings) -> String? {
        if settings.askForPassword == false {
            return "Display sleep fallback may not lock because password-after-sleep is disabled."
        }

        if let delay = settings.delay, delay > 0 {
            return "Display sleep fallback follows your password-after-sleep delay (\(Int(delay))s)."
        }

        return nil
    }
}
