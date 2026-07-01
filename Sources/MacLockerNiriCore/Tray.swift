import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct MacLockerNiriConfig: Codable, Equatable {
    var device: String
    var threshold: Int
    var awaySamples: Int
    var sampleSeconds: TimeInterval
    var interval: TimeInterval
    var cooldown: TimeInterval
    var lockCommand: String
    var ignoreMissing: Bool
    var dryRun: Bool
    var bluetoothctl: String

    init(
        device: String = "",
        threshold: Int = -80,
        awaySamples: Int = 3,
        sampleSeconds: TimeInterval = 6,
        interval: TimeInterval = 15,
        cooldown: TimeInterval = 300,
        lockCommand: String = "",
        ignoreMissing: Bool = false,
        dryRun: Bool = false,
        bluetoothctl: String = "bluetoothctl"
    ) {
        self.device = device
        self.threshold = threshold
        self.awaySamples = awaySamples
        self.sampleSeconds = sampleSeconds
        self.interval = interval
        self.cooldown = cooldown
        self.lockCommand = lockCommand
        self.ignoreMissing = ignoreMissing
        self.dryRun = dryRun
        self.bluetoothctl = bluetoothctl
    }

    enum CodingKeys: String, CodingKey {
        case device
        case threshold
        case awaySamples
        case sampleSeconds
        case interval
        case cooldown
        case lockCommand
        case ignoreMissing
        case dryRun
        case bluetoothctl
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        device = try values.decodeIfPresent(String.self, forKey: .device) ?? ""
        threshold = try values.decodeIfPresent(Int.self, forKey: .threshold) ?? -80
        awaySamples = try values.decodeIfPresent(Int.self, forKey: .awaySamples) ?? 3
        sampleSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .sampleSeconds) ?? 6
        interval = try values.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 15
        cooldown = try values.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? 300
        lockCommand = try values.decodeIfPresent(String.self, forKey: .lockCommand) ?? ""
        ignoreMissing = try values.decodeIfPresent(Bool.self, forKey: .ignoreMissing) ?? false
        dryRun = try values.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        bluetoothctl = try values.decodeIfPresent(String.self, forKey: .bluetoothctl) ?? "bluetoothctl"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(device, forKey: .device)
        try values.encode(threshold, forKey: .threshold)
        try values.encode(awaySamples, forKey: .awaySamples)
        try values.encode(sampleSeconds, forKey: .sampleSeconds)
        try values.encode(interval, forKey: .interval)
        try values.encode(cooldown, forKey: .cooldown)
        try values.encode(lockCommand, forKey: .lockCommand)
        try values.encode(ignoreMissing, forKey: .ignoreMissing)
        try values.encode(dryRun, forKey: .dryRun)
        try values.encode(bluetoothctl, forKey: .bluetoothctl)
    }
}

func defaultConfigURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
    let base: String
    if let xdgConfigHome = nonEmpty(environment["XDG_CONFIG_HOME"]) {
        base = xdgConfigHome
    } else if let home = nonEmpty(environment["HOME"]) {
        base = "\(home)/.config"
    } else {
        base = "\(FileManager.default.currentDirectoryPath)/.config"
    }

    return URL(fileURLWithPath: base, isDirectory: true)
        .appendingPathComponent("maclocker-niri", isDirectory: true)
        .appendingPathComponent("config.json")
}

func loadMacLockerNiriConfig(from url: URL = defaultConfigURL()) throws -> MacLockerNiriConfig {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return MacLockerNiriConfig()
    }

    return try JSONDecoder().decode(MacLockerNiriConfig.self, from: Data(contentsOf: url))
}

func saveMacLockerNiriConfig(_ config: MacLockerNiriConfig, to url: URL = defaultConfigURL()) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: url, options: .atomic)
}

func monitorOptions(from config: MacLockerNiriConfig) throws -> MacLockerNiriOptions {
    var options = MacLockerNiriOptions()
    options.device = config.device.trimmed
    options.threshold = config.threshold
    options.awaySamples = config.awaySamples
    options.sampleSeconds = config.sampleSeconds
    options.interval = config.interval
    options.cooldown = config.cooldown
    options.ignoreMissing = config.ignoreMissing
    options.dryRun = config.dryRun
    options.bluetoothctl = config.bluetoothctl.trimmed

    let lockCommand = config.lockCommand.trimmed
    if !lockCommand.isEmpty {
        options.lockCommandValues = [lockCommand]
    }

    guard let device = options.device, !device.isEmpty else {
        throw MacLockerNiriError.invalidArgument("set a device in tray settings before starting")
    }

    try validateOptions(options)
    _ = try parseLockCommands(options.lockCommandValues)
    return options
}

func monitorArguments(executable: String, config: MacLockerNiriConfig) throws -> [String] {
    let options = try monitorOptions(from: config)
    var arguments = [
        executable,
        "--device", options.device ?? "",
        "--threshold", String(options.threshold),
        "--away-samples", String(options.awaySamples),
        "--sample-seconds", cliString(options.sampleSeconds),
        "--interval", cliString(options.interval),
        "--cooldown", cliString(options.cooldown),
    ]

    for lockCommand in options.lockCommandValues {
        arguments.append(contentsOf: ["--lock-command", lockCommand])
    }
    if options.ignoreMissing {
        arguments.append("--ignore-missing")
    }
    if options.dryRun {
        arguments.append("--dry-run")
    }
    if options.bluetoothctl != "bluetoothctl" {
        arguments.append(contentsOf: ["--bluetoothctl", options.bluetoothctl])
    }

    return arguments
}

func yadNotificationArguments(executable: String, running: Bool) -> [String] {
    let menu = [
        "Settings!\(formatCommand([executable, "--tray-settings"]))",
        "Start!\(formatCommand([executable, "--tray-start"]))",
        "Stop!\(formatCommand([executable, "--tray-stop"]))",
        "Quit!quit",
    ].joined(separator: "|")

    return [
        "yad",
        "--notification",
        "--image=system-lock-screen",
        "--text=MacLocker Niri (\(running ? "running" : "stopped"))",
        "--menu=\(menu)",
    ]
}

func yadSettingsArguments(config: MacLockerNiriConfig) -> [String] {
    [
        "yad",
        "--form",
        "--title=MacLocker Niri Settings",
        "--width=520",
        "--button=Save:0",
        "--button=Cancel:1",
        "--field=Device address/name",
        "--field=Threshold dBm",
        "--field=Away samples",
        "--field=Sample seconds",
        "--field=Interval seconds",
        "--field=Cooldown seconds",
        "--field=Lock command",
        "--field=Ignore missing RSSI:CHK",
        "--field=Dry run:CHK",
        "--field=bluetoothctl command",
        "--",
        config.device,
        String(config.threshold),
        String(config.awaySamples),
        cliString(config.sampleSeconds),
        cliString(config.interval),
        cliString(config.cooldown),
        config.lockCommand,
        config.ignoreMissing ? "TRUE" : "FALSE",
        config.dryRun ? "TRUE" : "FALSE",
        config.bluetoothctl,
    ]
}

func parseTraySettingsOutput(_ output: String, fallback: MacLockerNiriConfig) throws -> MacLockerNiriConfig {
    var parts = output.components(separatedBy: "|")
    if parts.last?.trimmed.isEmpty == true {
        parts.removeLast()
    }
    guard parts.count == 10 else {
        throw MacLockerNiriError.invalidArgument("yad settings returned \(parts.count) fields, expected 10")
    }

    var config = fallback
    config.device = parts[0].trimmed
    config.threshold = try parseTrayInt(parts[1], field: "threshold")
    config.awaySamples = try parseTrayInt(parts[2], field: "away samples")
    config.sampleSeconds = try parseTrayDouble(parts[3], field: "sample seconds")
    config.interval = try parseTrayDouble(parts[4], field: "interval")
    config.cooldown = try parseTrayDouble(parts[5], field: "cooldown")
    config.lockCommand = parts[6].trimmed
    config.ignoreMissing = trayBool(parts[7])
    config.dryRun = trayBool(parts[8])
    config.bluetoothctl = parts[9].trimmed

    _ = try monitorOptions(from: config)
    return config
}

final class TrayController {
    private let configURL: URL
    private let pidURL: URL
    private let executable: String

    init(
        configURL: URL = defaultConfigURL(),
        executable: String = CommandLine.arguments.first ?? "maclocker-niri"
    ) {
        self.configURL = configURL
        self.pidURL = configURL.deletingLastPathComponent().appendingPathComponent("monitor.pid")
        self.executable = executable
    }

    func run(_ action: TrayAction) throws -> Int32 {
        switch action {
        case .none:
            return 0
        case .menu:
            return try runMenu()
        case .settings:
            return try runSettings()
        case .start:
            return try startMonitor()
        case .stop:
            return try stopMonitor()
        }
    }

    private func runMenu() throws -> Int32 {
        let result = try runProcess(yadNotificationArguments(executable: executable, running: monitorIsRunning()), timeout: nil)
        if (result.exitCode ?? 1) == 0 {
            return 0
        }
        throw MacLockerNiriError.processFailed("yad tray exited with \(result.exitCode ?? -1): \(result.output.trimmed)")
    }

    private func runSettings() throws -> Int32 {
        let config = try loadMacLockerNiriConfig(from: configURL)
        let result = try runProcess(yadSettingsArguments(config: config), timeout: nil)
        let exitCode = result.exitCode ?? 1

        if exitCode == 1 || exitCode == 252 {
            return 0
        }
        if exitCode != 0 {
            throw MacLockerNiriError.processFailed("yad settings exited with \(exitCode): \(result.output.trimmed)")
        }

        try saveMacLockerNiriConfig(try parseTraySettingsOutput(result.output, fallback: config), to: configURL)
        return 0
    }

    private func startMonitor() throws -> Int32 {
        if runningMonitorPid() != nil {
            log("tray monitor already running")
            return 0
        }

        let command = try monitorArguments(executable: executable, config: loadMacLockerNiriConfig(from: configURL))
        let monitor = try startDetached(command)
        try writePid(monitor)
        log("tray monitor started with pid \(monitor.pid)")
        return 0
    }

    private func stopMonitor() throws -> Int32 {
        guard let pid = runningMonitorPid() else {
            log("tray monitor is not running")
            return 0
        }

        if processExists(pid) {
            _ = kill(pid, SIGTERM)
            log("tray monitor stopped pid \(pid)")
        }
        try? FileManager.default.removeItem(at: pidURL)
        return 0
    }

    private func monitorIsRunning() -> Bool {
        runningMonitorPid() != nil
    }

    private func startDetached(_ command: [String]) throws -> MonitorPidFile {
        guard let executableName = command.first, let executablePath = findExecutable(executableName) else {
            throw MacLockerNiriError.processNotFound(command.first ?? "")
        }
        let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
        let resolvedCommand = [executableURL.path] + Array(command.dropFirst())

        let process = Process()
        process.executableURL = executableURL
        process.arguments = Array(command.dropFirst())

        let nullRead = FileHandle(forReadingAtPath: "/dev/null")
        let nullWrite = FileHandle(forWritingAtPath: "/dev/null")
        if let nullRead {
            process.standardInput = nullRead
        }
        if let nullWrite {
            process.standardOutput = nullWrite
            process.standardError = nullWrite
        }

        do {
            try process.run()
        } catch {
            throw MacLockerNiriError.processFailed("\(executableName) failed to start: \(error)")
        }

        return MonitorPidFile(pid: process.processIdentifier, command: resolvedCommand)
    }

    private func runningMonitorPid() -> Int32? {
        guard let file = readPid(), processExists(file.pid), monitorProcessMatches(file) else {
            try? FileManager.default.removeItem(at: pidURL)
            return nil
        }
        return file.pid
    }

    private func readPid() -> MonitorPidFile? {
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8) else {
            return nil
        }
        if let data = text.data(using: .utf8),
           let file = try? JSONDecoder().decode(MonitorPidFile.self, from: data)
        {
            return file
        }
        guard let pid = Int32(text.trimmed) else {
            return nil
        }
        return MonitorPidFile(pid: pid, command: [])
    }

    private func writePid(_ file: MonitorPidFile) throws {
        try FileManager.default.createDirectory(
            at: pidURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(file).write(to: pidURL, options: .atomic)
    }

    private func monitorProcessMatches(_ file: MonitorPidFile) -> Bool {
        guard let command = processCommandLine(pid: file.pid) else {
            return false
        }
        if !file.command.isEmpty {
            return command == file.command
        }
        // Old pidfiles only stored a PID. Keep control of those only when the
        // live process still looks like this monitor, not an unrelated reused PID.
        return command.first.map { URL(fileURLWithPath: $0).lastPathComponent == URL(fileURLWithPath: executable).lastPathComponent } == true
            && command.contains("--device")
    }
}

private struct MonitorPidFile: Codable {
    let pid: Int32
    let command: [String]
}

private func processExists(_ pid: Int32) -> Bool {
    pid > 1 && kill(pid, 0) == 0
}

private func processCommandLine(pid: Int32) -> [String]? {
#if os(Linux)
    guard let data = FileManager.default.contents(atPath: "/proc/\(pid)/cmdline"), !data.isEmpty else {
        return nil
    }
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\0", omittingEmptySubsequences: true)
        .map(String.init)
#else
    return nil
#endif
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}

private func cliString(_ value: TimeInterval) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

private func parseTrayInt(_ value: String, field: String) throws -> Int {
    guard let parsed = Int(value.trimmed) else {
        throw MacLockerNiriError.invalidArgument("\(field) must be an integer")
    }
    return parsed
}

private func parseTrayDouble(_ value: String, field: String) throws -> Double {
    guard let parsed = Double(value.trimmed) else {
        throw MacLockerNiriError.invalidArgument("\(field) must be a number")
    }
    return parsed
}

private func trayBool(_ value: String) -> Bool {
    switch value.trimmed.lowercased() {
    case "1", "true", "yes", "on":
        return true
    default:
        return false
    }
}
