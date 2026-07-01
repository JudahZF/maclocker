import Dispatch
import Foundation

public struct DeviceInfo: Equatable {
    public let address: String
    public let name: String

    public init(address: String, name: String) {
        self.address = address
        self.name = name
    }
}

public struct RssiReading: Equatable {
    public let address: String
    public let rssi: Int
    public let line: String

    public init(address: String, rssi: Int, line: String) {
        self.address = address
        self.rssi = rssi
        self.line = line
    }
}

public struct RssiSample: Equatable {
    public let rssi: Int?
    public let address: String?
    public let readings: [RssiReading]
    public let matchedAddresses: Set<String>

    public init(rssi: Int?, address: String?, readings: [RssiReading], matchedAddresses: Set<String>) {
        self.rssi = rssi
        self.address = address
        self.readings = readings
        self.matchedAddresses = matchedAddresses
    }
}

public struct AwayTracker {
    public let threshold: Int
    public let requiredSamples: Int
    public let missingIsAway: Bool
    public private(set) var consecutiveAway: Int

    public init(threshold: Int, requiredSamples: Int, missingIsAway: Bool = true) {
        self.threshold = threshold
        self.requiredSamples = requiredSamples
        self.missingIsAway = missingIsAway
        self.consecutiveAway = 0
    }

    public mutating func update(_ sample: RssiSample) -> (away: Bool, shouldLock: Bool) {
        let away: Bool
        if let rssi = sample.rssi {
            away = rssi < threshold
        } else {
            away = missingIsAway
        }

        if away {
            consecutiveAway += 1
        } else {
            consecutiveAway = 0
        }

        return (away, consecutiveAway >= requiredSamples)
    }

    public mutating func reset() {
        consecutiveAway = 0
    }
}

public enum MacLockerNiriError: Error, CustomStringConvertible {
    case bluetooth(String)
    case invalidArgument(String)
    case processNotFound(String)
    case processFailed(String)
    case help

    public var description: String {
        switch self {
        case let .bluetooth(message), let .invalidArgument(message), let .processFailed(message):
            return message
        case let .processNotFound(command):
            return "\(command) is not installed or is not in PATH"
        case .help:
            return usageText
        }
    }
}

private let addressPattern = #"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}"#
private let addressRegex = try! NSRegularExpression(pattern: #"\b("# + addressPattern + #")\b"#)
private let deviceRegex = try! NSRegularExpression(pattern: #"\bDevice\s+("# + addressPattern + #")(?:\s+(.*))?"#)
private let rssiRegex = try! NSRegularExpression(pattern: #"\bRSSI:\s*(-?\d+)\b"#)
private let propertyRegex = try! NSRegularExpression(
    pattern: #"^(?:RSSI|TxPower|ManufacturerData|ServiceData|UUIDs|Connected|Paired|Trusted|Blocked):"#,
    options: [.caseInsensitive]
)

private func firstMatch(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
    regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
}

private func group(_ index: Int, from match: NSTextCheckingResult, in line: String) -> String? {
    let range = match.range(at: index)
    guard range.location != NSNotFound, let stringRange = Range(range, in: line) else {
        return nil
    }
    return String(line[stringRange])
}

public func normalizeAddress(_ value: String?) -> String? {
    guard let value, let match = firstMatch(addressRegex, in: value), let address = group(1, from: match, in: value) else {
        return nil
    }
    return address.uppercased()
}

public func parseDeviceNameLine(_ line: String) -> DeviceInfo? {
    guard let match = firstMatch(deviceRegex, in: line),
          let rawAddress = group(1, from: match, in: line)
    else {
        return nil
    }

    var detail = group(2, from: match, in: line)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !detail.isEmpty else {
        return nil
    }

    let lowerDetail = detail.lowercased()
    if lowerDetail.hasPrefix("name:") || lowerDetail.hasPrefix("alias:") {
        detail = detail
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    } else if firstMatch(propertyRegex, in: detail) != nil {
        return nil
    } else if detail.hasPrefix("("), detail.hasSuffix(")") {
        return nil
    }

    guard !detail.isEmpty else {
        return nil
    }

    return DeviceInfo(address: normalizeAddress(rawAddress) ?? rawAddress.uppercased(), name: detail)
}

public func parseDevices(_ text: String) -> [DeviceInfo] {
    var devices: [String: DeviceInfo] = [:]
    var order: [String] = []

    for line in text.components(separatedBy: .newlines) {
        guard let device = parseDeviceNameLine(line) else {
            continue
        }
        if devices[device.address] == nil {
            order.append(device.address)
        }
        devices[device.address] = device
    }

    return order.compactMap { devices[$0] }
}

public func parseRssiReading(_ line: String) -> RssiReading? {
    guard let deviceMatch = firstMatch(deviceRegex, in: line),
          let rssiMatch = firstMatch(rssiRegex, in: line),
          let rawAddress = group(1, from: deviceMatch, in: line),
          let address = normalizeAddress(rawAddress),
          let rssiValue = group(1, from: rssiMatch, in: line),
          let rssi = Int(rssiValue)
    else {
        return nil
    }

    return RssiReading(address: address, rssi: rssi, line: line.trimmingCharacters(in: .whitespacesAndNewlines))
}

public func parseRssiReadings(_ text: String) -> [RssiReading] {
    var readings: [RssiReading] = []
    var currentAddress: String?

    for line in text.components(separatedBy: .newlines) {
        if let match = firstMatch(deviceRegex, in: line), let rawAddress = group(1, from: match, in: line) {
            currentAddress = normalizeAddress(rawAddress)
        }

        if let reading = parseRssiReading(line) {
            readings.append(reading)
            continue
        }

        if let address = currentAddress,
           let rssiMatch = firstMatch(rssiRegex, in: line),
           let rssiValue = group(1, from: rssiMatch, in: line),
           let rssi = Int(rssiValue)
        {
            readings.append(RssiReading(address: address, rssi: rssi, line: line.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    return readings
}

public func resolveTargetAddresses(_ target: String, devices: [DeviceInfo]) -> Set<String> {
    if let address = normalizeAddress(target) {
        return [address]
    }

    let targetName = target.lowercased()
    let exact = Set(devices.filter { $0.name.lowercased() == targetName }.map(\.address))
    if !exact.isEmpty {
        return exact
    }

    return Set(devices.filter { $0.name.lowercased().contains(targetName) }.map(\.address))
}

public func collectTargetSample(_ text: String, target: String, knownAddresses: Set<String> = []) -> RssiSample {
    let devices = parseDevices(text)
    var matchedAddresses = Set(knownAddresses.map { normalizeAddress($0) ?? $0.uppercased() })
    matchedAddresses.formUnion(resolveTargetAddresses(target, devices: devices))

    let readings = parseRssiReadings(text).filter { matchedAddresses.contains($0.address) }
    guard let strongest = readings.max(by: { $0.rssi < $1.rssi }) else {
        return RssiSample(rssi: nil, address: nil, readings: [], matchedAddresses: matchedAddresses)
    }

    return RssiSample(rssi: strongest.rssi, address: strongest.address, readings: readings, matchedAddresses: matchedAddresses)
}

public struct ProcessResult {
    public let exitCode: Int32?
    public let output: String
    public let timedOut: Bool
}

public func findExecutable(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
    if name.contains("/") {
        return FileManager.default.isExecutableFile(atPath: name) ? name : nil
    }

    for directory in (environment["PATH"] ?? "").split(separator: ":") {
        let path = "\(directory)/\(name)"
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    return nil
}

public func runProcess(_ command: [String], timeout: TimeInterval? = nil) throws -> ProcessResult {
    guard let executableName = command.first, !executableName.isEmpty else {
        throw MacLockerNiriError.invalidArgument("command cannot be empty")
    }
    guard let executable = findExecutable(executableName) else {
        throw MacLockerNiriError.processNotFound(executableName)
    }

    let process = Process()
    let sendableProcess = SendableProcess(process)
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = Array(command.dropFirst())

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        throw MacLockerNiriError.processFailed("\(executableName) failed to start: \(error)")
    }

    var timedOut = false
    if let timeout {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            sendableProcess.process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            sendableProcess.process.terminate()
            _ = semaphore.wait(timeout: .now() + 2)
        }
    } else {
        process.waitUntilExit()
    }

    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return ProcessResult(exitCode: timedOut ? nil : process.terminationStatus, output: output, timedOut: timedOut)
}

public final class BluetoothctlScanner {
    private let bluetoothctl: String
    private let timeoutCommand: String

    public init(bluetoothctl: String = "bluetoothctl", timeoutCommand: String = "timeout") {
        self.bluetoothctl = bluetoothctl
        self.timeoutCommand = timeoutCommand
    }

    public func runBluetoothctl(_ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        do {
            let result = try runProcess([bluetoothctl] + arguments, timeout: timeout)
            if result.timedOut {
                throw MacLockerNiriError.bluetooth("bluetoothctl \(arguments.joined(separator: " ")) timed out\n\(result.output.trimmed)")
            }
            if (result.exitCode ?? 1) != 0 {
                throw MacLockerNiriError.bluetooth(
                    "bluetoothctl \(arguments.joined(separator: " ")) failed with exit \(result.exitCode ?? -1)\n\(result.output.trimmed)"
                )
            }
            return result.output
        } catch MacLockerNiriError.processNotFound(_) {
            throw MacLockerNiriError.bluetooth("bluetoothctl is not installed or is not in PATH")
        }
    }

    public func listDevices() throws -> [DeviceInfo] {
        try parseDevices(runBluetoothctl(["devices"], timeout: 8))
    }

    public func scanOutput(seconds: TimeInterval) throws -> String {
        let scanSeconds = max(1, Int(seconds.rounded()))
        let result: ProcessResult

        do {
            result = try runProcess([bluetoothctl, "--timeout", String(scanSeconds), "scan", "on"], timeout: TimeInterval(scanSeconds + 5))
        } catch MacLockerNiriError.processNotFound(_) {
            throw MacLockerNiriError.bluetooth("bluetoothctl is not installed or is not in PATH")
        }

        defer {
            scanOff()
        }

        if result.timedOut {
            return result.output
        }

        if (result.exitCode ?? 1) != 0, looksLikeUnsupportedTimeout(result.output) {
            return try scanOutputWithCoreutilsTimeout(seconds: scanSeconds)
        }

        if (result.exitCode ?? 1) != 0, result.output.contains("No default controller") {
            throw MacLockerNiriError.bluetooth(result.output.trimmed)
        }

        return result.output
    }

    private func scanOutputWithCoreutilsTimeout(seconds: Int) throws -> String {
        guard let timeoutExecutable = findExecutable(timeoutCommand) else {
            throw MacLockerNiriError.bluetooth("bluetoothctl does not support --timeout and coreutils timeout is not in PATH")
        }
        let bluetoothctlExecutable = findExecutable(bluetoothctl) ?? bluetoothctl
        let result = try runProcess([timeoutExecutable, "\(seconds)s", bluetoothctlExecutable, "scan", "on"], timeout: TimeInterval(seconds + 5))
        return result.output
    }

    public func scanOff() {
        _ = try? runProcess([bluetoothctl, "scan", "off"], timeout: 4)
    }

    public func infoOutput(address: String) -> String {
        (try? runBluetoothctl(["info", address], timeout: 8)) ?? ""
    }

    private func looksLikeUnsupportedTimeout(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("--timeout")
            && (lowered.contains("unknown") || lowered.contains("unrecognized") || lowered.contains("invalid option"))
    }
}

public func sampleDevice(scanner: BluetoothctlScanner, target: String, scanSeconds: TimeInterval, knownAddresses: inout Set<String>) -> RssiSample {
    if knownAddresses.isEmpty {
        do {
            knownAddresses.formUnion(resolveTargetAddresses(target, devices: try scanner.listDevices()))
        } catch {
            log("device list unavailable: \(error)")
        }
    }

    do {
        let output = try scanner.scanOutput(seconds: scanSeconds)
        let sample = collectTargetSample(output, target: target, knownAddresses: knownAddresses)
        knownAddresses.formUnion(sample.matchedAddresses)

        var infoOutput: [String] = []
        for address in knownAddresses.sorted() {
            let info = scanner.infoOutput(address: address)
            if !info.isEmpty {
                infoOutput.append(info)
            }
        }

        if !infoOutput.isEmpty {
            let infoSample = collectTargetSample(infoOutput.joined(separator: "\n"), target: target, knownAddresses: knownAddresses)
            if infoSample.rssi != nil {
                knownAddresses.formUnion(infoSample.matchedAddresses)
                let combined = sample.readings + infoSample.readings
                if let strongest = combined.max(by: { $0.rssi < $1.rssi }) {
                    return RssiSample(
                        rssi: strongest.rssi,
                        address: strongest.address,
                        readings: combined,
                        matchedAddresses: knownAddresses
                    )
                }
            }
        }

        return sample
    } catch {
        log("Bluetooth scan failed: \(error)")
        return RssiSample(rssi: nil, address: nil, readings: [], matchedAddresses: knownAddresses)
    }
}

public func defaultLockCommands(environment: [String: String] = ProcessInfo.processInfo.environment) -> [[String]] {
    var commands: [[String]] = []

    if let loginctl = findExecutable("loginctl", environment: environment) {
        if let sessionID = environment["XDG_SESSION_ID"], !sessionID.isEmpty {
            commands.append([loginctl, "lock-session", sessionID])
        } else {
            commands.append([loginctl, "lock-session"])
        }
    }

    for (name, arguments) in [("swaylock", ["-f"]), ("gtklock", []), ("hyprlock", [])] {
        if let executable = findExecutable(name, environment: environment) {
            commands.append([executable] + arguments)
        }
    }

    return commands
}

public func parseLockCommands(_ values: [String]) throws -> [[String]] {
    if values.isEmpty {
        return defaultLockCommands()
    }

    return try values.map { value in
        let command = try splitCommand(value)
        guard !command.isEmpty else {
            throw MacLockerNiriError.invalidArgument("--lock-command cannot be empty")
        }
        return command
    }
}

public func runLockCommands(_ commands: [[String]], dryRun: Bool) -> Bool {
    guard !commands.isEmpty else {
        log("no lock command is available; install loginctl or pass --lock-command")
        return false
    }

    for command in commands {
        if dryRun {
            log("dry-run: would run \(formatCommand(command))")
            return true
        }

        log("locking with \(formatCommand(command))")
        do {
            let result = try runProcess(command, timeout: 30)
            if result.timedOut {
                log("lock command timed out: \(formatCommand(command))")
                continue
            }
            if (result.exitCode ?? 1) == 0 {
                return true
            }

            let detail = result.output.trimmed
            log("lock command failed with exit \(result.exitCode ?? -1)\(detail.isEmpty ? "" : ": \(detail)")")
        } catch MacLockerNiriError.processNotFound(_) {
            log("lock command not found: \(command[0])")
        } catch {
            log("lock command failed: \(error)")
        }
    }

    return false
}

public struct MacLockerNiriOptions {
    public var device: String?
    public var threshold = -80
    public var awaySamples = 3
    public var sampleSeconds: TimeInterval = 6
    public var interval: TimeInterval = 15
    public var cooldown: TimeInterval = 300
    public var lockCommandValues: [String] = []
    public var ignoreMissing = false
    public var dryRun = false
    public var once = false
    public var listDevices = false
    public var bluetoothctl = "bluetoothctl"
    var trayAction = TrayAction.none

    public init() {}
}

enum TrayAction: Equatable {
    case none
    case menu
    case settings
    case start
    case stop
}

public let usageText = """
Usage: maclocker-niri [options]

Lock a Niri/Wayland session when a selected Bluetooth device RSSI stays below a threshold.

Options:
  --device VALUE          Bluetooth MAC address or unique device name to monitor
  --threshold DBM         Away threshold in dBm; lower RSSI is away (default: -80)
  --away-samples COUNT    Consecutive away/missing samples before locking (default: 3)
  --sample-seconds SEC    Bluetooth scan duration per sample (default: 6)
  --interval SEC          Seconds to sleep between samples (default: 15)
  --cooldown SEC          Seconds to wait after a successful lock (default: 300)
  --lock-command COMMAND  Command to run when away; may be passed more than once
  --ignore-missing        Do not treat missing RSSI as away
  --dry-run               Log the lock command instead of executing it
  --once                  Take one sample and exit
  --list-devices          Print known Bluetooth devices and exit
  --tray                  Show a StatusNotifier/AppIndicator tray menu
  --help                  Show this help
"""

public func parseOptions(_ arguments: [String]) throws -> MacLockerNiriOptions {
    var options = MacLockerNiriOptions()
    var index = arguments.first.map { _ in 1 } ?? 0

    func value(after option: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw MacLockerNiriError.invalidArgument("\(option) requires a value")
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]

        if argument == "--help" || argument == "-h" {
            throw MacLockerNiriError.help
        } else if let value = argument.optionValue(prefix: "--device=") {
            options.device = value
        } else if let value = argument.optionValue(prefix: "--threshold=") {
            options.threshold = try parseInt(value, option: "--threshold")
        } else if let value = argument.optionValue(prefix: "--away-samples=") {
            options.awaySamples = try parseInt(value, option: "--away-samples")
        } else if let value = argument.optionValue(prefix: "--sample-seconds=") {
            options.sampleSeconds = try parseDouble(value, option: "--sample-seconds")
        } else if let value = argument.optionValue(prefix: "--interval=") {
            options.interval = try parseDouble(value, option: "--interval")
        } else if let value = argument.optionValue(prefix: "--cooldown=") {
            options.cooldown = try parseDouble(value, option: "--cooldown")
        } else if let value = argument.optionValue(prefix: "--lock-command=") {
            options.lockCommandValues.append(value)
        } else {
            switch argument {
            case "--device":
                options.device = try value(after: argument)
            case "--threshold":
                options.threshold = try parseInt(value(after: argument), option: argument)
            case "--away-samples":
                options.awaySamples = try parseInt(value(after: argument), option: argument)
            case "--sample-seconds":
                options.sampleSeconds = try parseDouble(value(after: argument), option: argument)
            case "--interval":
                options.interval = try parseDouble(value(after: argument), option: argument)
            case "--cooldown":
                options.cooldown = try parseDouble(value(after: argument), option: argument)
            case "--lock-command":
                options.lockCommandValues.append(try value(after: argument))
            case "--ignore-missing":
                options.ignoreMissing = true
            case "--dry-run":
                options.dryRun = true
            case "--once":
                options.once = true
            case "--list-devices":
                options.listDevices = true
            case "--tray":
                options.trayAction = .menu
            case "--tray-settings":
                options.trayAction = .settings
            case "--tray-start":
                options.trayAction = .start
            case "--tray-stop":
                options.trayAction = .stop
            case "--bluetoothctl":
                options.bluetoothctl = try value(after: argument)
            default:
                throw MacLockerNiriError.invalidArgument("unknown option: \(argument)")
            }
        }

        index += 1
    }

    try validateOptions(options)
    return options
}

func validateOptions(_ options: MacLockerNiriOptions) throws {
    if options.awaySamples < 1 {
        throw MacLockerNiriError.invalidArgument("--away-samples must be at least 1")
    }
    if options.sampleSeconds <= 0 {
        throw MacLockerNiriError.invalidArgument("--sample-seconds must be greater than 0")
    }
    if options.interval < 0 {
        throw MacLockerNiriError.invalidArgument("--interval must not be negative")
    }
    if options.cooldown < 0 {
        throw MacLockerNiriError.invalidArgument("--cooldown must not be negative")
    }
    if let device = options.device, device.isEmpty {
        throw MacLockerNiriError.invalidArgument("--device cannot be empty")
    }
    if options.bluetoothctl.isEmpty {
        throw MacLockerNiriError.invalidArgument("--bluetoothctl cannot be empty")
    }
}

public final class Runner {
    public init() {}

    public func run(_ options: MacLockerNiriOptions) throws -> Int32 {
        if options.trayAction != .none {
            return try TrayController().run(options.trayAction)
        }

        let scanner = BluetoothctlScanner(bluetoothctl: options.bluetoothctl)

        if options.listDevices {
            for device in try scanner.listDevices() {
                print("\(device.address)\t\(device.name)")
            }
            return 0
        }

        guard let device = options.device else {
            throw MacLockerNiriError.invalidArgument("--device is required unless --list-devices is used")
        }

        let lockCommands = try parseLockCommands(options.lockCommandValues)
        var knownAddresses = resolveTargetAddresses(device, devices: [])
        var tracker = AwayTracker(
            threshold: options.threshold,
            requiredSamples: options.awaySamples,
            missingIsAway: !options.ignoreMissing
        )

        while true {
            let sample = sampleDevice(
                scanner: scanner,
                target: device,
                scanSeconds: options.sampleSeconds,
                knownAddresses: &knownAddresses
            )
            let result = tracker.update(sample)
            let state = result.away ? "away" : "near"
            let rssi = sample.rssi.map { "\($0) dBm" } ?? "missing"
            let address = sample.address ?? "unresolved"
            log("\(state): rssi=\(rssi) address=\(address) away_samples=\(tracker.consecutiveAway)/\(tracker.requiredSamples)")

            if result.shouldLock, runLockCommands(lockCommands, dryRun: options.dryRun) {
                tracker.reset()
                if options.once {
                    return 0
                }
                Thread.sleep(forTimeInterval: options.cooldown)
                continue
            }

            if options.once {
                return 0
            }

            Thread.sleep(forTimeInterval: options.interval)
        }
    }
}

public func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

public func formatCommand(_ command: [String]) -> String {
    command.map(quoteShellArgument).joined(separator: " ")
}

public func splitCommand(_ value: String) throws -> [String] {
    var command: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for character in value {
        if escaping {
            current.append(character)
            escaping = false
            continue
        }

        if character == "\\" {
            escaping = true
            continue
        }

        if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            continue
        }

        if character == "'" || character == "\"" {
            quote = character
        } else if character == " " || character == "\t" || character == "\n" || character == "\r" {
            if !current.isEmpty {
                command.append(current)
                current = ""
            }
        } else {
            current.append(character)
        }
    }

    if escaping {
        current.append("\\")
    }
    if quote != nil {
        throw MacLockerNiriError.invalidArgument("unterminated quote in --lock-command")
    }
    if !current.isEmpty {
        command.append(current)
    }

    return command
}

private func quoteShellArgument(_ value: String) -> String {
    guard !value.isEmpty else {
        return "''"
    }

    let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=")
    if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
        return value
    }

    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func parseInt(_ value: String, option: String) throws -> Int {
    guard let parsed = Int(value) else {
        throw MacLockerNiriError.invalidArgument("\(option) must be an integer")
    }
    return parsed
}

private func parseDouble(_ value: String, option: String) throws -> Double {
    guard let parsed = Double(value) else {
        throw MacLockerNiriError.invalidArgument("\(option) must be a number")
    }
    return parsed
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func optionValue(prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

private final class SendableProcess: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}
