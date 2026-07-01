import AppKit
import Combine
import Foundation

enum AppStatus: Equatable {
    case disabled
    case discovering
    case calibrating(String)
    case armed
    case awayCountdown(TimeInterval)
    case locked
    case paused
    case error(String)

    var displayText: String {
        switch self {
        case .disabled:
            "Disabled"
        case .discovering:
            "Discovering"
        case let .calibrating(step):
            "Calibrating: \(step)"
        case .armed:
            "Armed"
        case let .awayCountdown(remaining):
            "Away countdown: \(Int(ceil(remaining)))s"
        case .locked:
            "Locked"
        case .paused:
            "Paused"
        case let .error(message):
            "Error: \(message)"
        }
    }
}

enum CalibrationPhase: Equatable {
    case idle
    case recordingNear(until: Date)
    case nearComplete
    case recordingAway(until: Date)
    case complete
    case manual
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            "Not started"
        case let .recordingNear(until):
            "Near sample \(max(0, Int(ceil(until.timeIntervalSinceNow))))s"
        case .nearComplete:
            "Near sample recorded"
        case let .recordingAway(until):
            "Away sample \(max(0, Int(ceil(until.timeIntervalSinceNow))))s"
        case .complete:
            "Calibration complete"
        case .manual:
            "Manual threshold set"
        case let .failed(message):
            "Calibration failed: \(message)"
        }
    }

    var isRecording: Bool {
        switch self {
        case .recordingNear, .recordingAway:
            true
        case .idle, .nearComplete, .complete, .manual, .failed:
            false
        }
    }
}

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var candidates: [WatchCandidate] = []
    @Published var scannerState: WatchScannerState = .idle
    @Published var status: AppStatus = .disabled
    @Published var smoothedRSSI: Double?
    @Published var isPaused = false
    @Published var calibrationPhase: CalibrationPhase = .idle
    @Published var calibrationResult: CalibrationResult?
    @Published var calibrationError: String?
    @Published var lastLockError: String?
    @Published var lastLaunchAtLoginError: String?
    @Published var lockCapability: LockCapability

    let settingsStore: SettingsStore
    let scanner: WatchScanner
    let lockController: LockController
    let launchAtLoginController: LaunchAtLoginController

    private var classifier = SignalClassifier()
    private var cancellables: Set<AnyCancellable> = []
    private var tickTimer: Timer?
    private var nearSamples: [Int] = []
    private var awaySamples: [Int] = []

    init(
        settingsStore: SettingsStore = SettingsStore(),
        scanner: WatchScanner = WatchScanner(),
        lockController: LockController = LockController(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    ) {
        self.settingsStore = settingsStore
        self.scanner = scanner
        self.lockController = lockController
        self.launchAtLoginController = launchAtLoginController
        lockCapability = lockController.capability()
    }

    func start() {
        bindScanner()
        scanner.selectPeripheral(id: settingsStore.settings.selectedPeripheralID ?? UUID())
        scanner.startDiscovery()
        classifier.suppressLocking(at: Date(), settings: settingsStore.settings)
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        tickTimer?.invalidate()
        scanner.stopDiscovery()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func selectCandidate(_ candidate: WatchCandidate) {
        var settings = settingsStore.settings
        settings.selectedPeripheralID = candidate.id
        settings.rssiThreshold = nil
        settings.isAutoLockEnabled = false
        settingsStore.settings = settings
        scanner.selectPeripheral(id: candidate.id)
        classifier.reset()
        calibrationPhase = .idle
        calibrationResult = nil
        calibrationError = nil
        evaluateSignal(at: Date())
    }

    func startNearCalibration() {
        guard settingsStore.settings.selectedPeripheralID != nil else {
            calibrationPhase = .failed("Select a visible device first.")
            return
        }

        nearSamples = []
        awaySamples = []
        calibrationResult = nil
        calibrationError = nil
        calibrationPhase = .recordingNear(until: Date().addingTimeInterval(10))
        evaluateSignal(at: Date())
    }

    func startAwayCalibration() {
        guard !nearSamples.isEmpty else {
            calibrationPhase = .failed("Record a near sample first.")
            return
        }

        awaySamples = []
        calibrationError = nil
        calibrationPhase = .recordingAway(until: Date().addingTimeInterval(10))
        evaluateSignal(at: Date())
    }

    func toggleAutoLock() {
        var settings = settingsStore.settings
        guard settings.selectedPeripheralID != nil, settings.rssiThreshold != nil else {
            calibrationPhase = .failed("Select and calibrate a device before enabling auto-lock.")
            settings.isAutoLockEnabled = false
            settingsStore.settings = settings
            evaluateSignal(at: Date())
            return
        }

        settings.isAutoLockEnabled.toggle()
        settingsStore.settings = settings
        if settings.isAutoLockEnabled {
            isPaused = false
            classifier.suppressLocking(at: Date(), settings: settings)
        }
        evaluateSignal(at: Date())
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            classifier.suppressLocking(at: Date(), settings: settingsStore.settings)
        }
        evaluateSignal(at: Date())
    }

    func setManualRSSIThreshold(_ threshold: Int) {
        guard settingsStore.settings.selectedPeripheralID != nil else {
            calibrationPhase = .failed("Select a visible device before setting a threshold.")
            return
        }

        let clampedThreshold = min(
            max(threshold, CalibrationModel.practicalThresholdRange.lowerBound),
            CalibrationModel.practicalThresholdRange.upperBound
        )
        var settings = settingsStore.settings
        settings.rssiThreshold = clampedThreshold
        settingsStore.settings = settings
        calibrationResult = nil
        calibrationError = nil
        calibrationPhase = .manual
        classifier.reset()
        classifier.suppressLocking(at: Date(), settings: settings)
        evaluateSignal(at: Date())
    }

    func clearManualRSSIThreshold() {
        var settings = settingsStore.settings
        settings.rssiThreshold = nil
        settings.isAutoLockEnabled = false
        settingsStore.settings = settings
        calibrationResult = nil
        calibrationError = nil
        calibrationPhase = .idle
        classifier.reset()
        evaluateSignal(at: Date())
    }

    func setAwayHoldSeconds(_ seconds: TimeInterval) {
        updateTimingSettings { $0.awayHoldSeconds = seconds }
    }

    func setMissingSignalSeconds(_ seconds: TimeInterval) {
        updateTimingSettings { $0.missingSignalSeconds = seconds }
    }

    func setNearHoldSeconds(_ seconds: TimeInterval) {
        updateTimingSettings { $0.nearHoldSeconds = seconds }
    }

    func setGraceAfterUnlockSeconds(_ seconds: TimeInterval) {
        updateTimingSettings { $0.graceAfterUnlockSeconds = seconds }
    }

    func lockNowRequested() {
        Task { @MainActor in
            await performLock(markLocked: true)
        }
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(isEnabled)
            var settings = settingsStore.settings
            settings.launchAtLogin = isEnabled
            settingsStore.settings = settings
            lastLaunchAtLoginError = nil
        } catch {
            lastLaunchAtLoginError = error.localizedDescription
        }
    }

    func openAccessibilityPrompt() {
        ImmediateShortcutLocker.requestAccessibilityPermission()
        refreshLockCapability()
    }

    func refreshLockCapability() {
        lockCapability = lockController.capability()
    }

    private func bindScanner() {
        scanner.$candidates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] candidates in
                self?.candidates = candidates
            }
            .store(in: &cancellables)

        scanner.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.scannerState = state
                self?.evaluateSignal(at: Date())
            }
            .store(in: &cancellables)

        scanner.onSignalEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleSignalEvent(event)
            }
        }
    }

    private func handleSignalEvent(_ event: WatchSignalEvent) {
        classifier.observe(event, selectedPeripheralID: settingsStore.settings.selectedPeripheralID)

        switch calibrationPhase {
        case let .recordingNear(until) where event.timestamp <= until:
            nearSamples.append(event.rssi)
        case let .recordingAway(until) where event.timestamp <= until:
            awaySamples.append(event.rssi)
        default:
            break
        }

        evaluateSignal(at: event.timestamp)
    }

    private func tick() {
        refreshLockCapability()
        finishExpiredCalibrationStep(at: Date())
        evaluateSignal(at: Date())
    }

    private func finishExpiredCalibrationStep(at now: Date) {
        switch calibrationPhase {
        case let .recordingNear(until) where now >= until:
            calibrationPhase = .nearComplete
        case let .recordingAway(until) where now >= until:
            finishCalibration()
        default:
            break
        }
    }

    private func finishCalibration() {
        do {
            let result = try CalibrationModel.calibrate(nearRSSI: nearSamples, awayRSSI: awaySamples)
            calibrationResult = result
            calibrationError = nil
            calibrationPhase = .complete

            var settings = settingsStore.settings
            settings.rssiThreshold = result.threshold
            settings.isAutoLockEnabled = true
            settingsStore.settings = settings
            classifier.reset()
            classifier.suppressLocking(at: Date(), settings: settings)
        } catch {
            calibrationResult = nil
            calibrationError = error.localizedDescription
            calibrationPhase = .failed(error.localizedDescription)

            var settings = settingsStore.settings
            settings.rssiThreshold = nil
            settings.isAutoLockEnabled = false
            settingsStore.settings = settings
        }
    }

    private func updateTimingSettings(_ update: (inout LockSettings) -> Void) {
        var settings = settingsStore.settings
        update(&settings)
        settings.awayHoldSeconds = max(1, settings.awayHoldSeconds)
        settings.missingSignalSeconds = max(1, settings.missingSignalSeconds)
        settings.nearHoldSeconds = max(1, settings.nearHoldSeconds)
        settings.graceAfterUnlockSeconds = max(0, settings.graceAfterUnlockSeconds)
        settingsStore.settings = settings
        classifier.suppressLocking(at: Date(), settings: settings)
        evaluateSignal(at: Date())
    }

    private func evaluateSignal(at now: Date) {
        let settings = settingsStore.settings
        let preconditions = SignalPreconditions(
            isBluetoothReady: scannerState.isBluetoothReady,
            hasSelection: settings.selectedPeripheralID != nil,
            isCalibrated: settings.rssiThreshold != nil,
            isAutoLockEnabled: settings.isAutoLockEnabled,
            isPaused: isPaused
        )
        let evaluation = classifier.evaluate(at: now, settings: settings, preconditions: preconditions)
        smoothedRSSI = evaluation.smoothedRSSI

        if calibrationPhase.isRecording {
            status = .calibrating(calibrationPhase.displayText)
        } else {
            status = status(from: evaluation.state)
        }

        guard evaluation.shouldLock else { return }
        Task { @MainActor in
            await performLock(markLocked: true)
        }
    }

    private func status(from state: SignalEvaluationState) -> AppStatus {
        switch state {
        case .disabled:
            .disabled
        case .unauthorized:
            .error(scannerState.displayText)
        case .unselected, .uncalibrated:
            scannerState == .discovering ? .discovering : .disabled
        case .grace, .monitoring:
            .armed
        case let .awayCountdown(remaining):
            .awayCountdown(remaining)
        case .locked:
            .locked
        case .paused:
            .paused
        }
    }

    private func performLock(markLocked: Bool) async {
        do {
            try await lockController.lockNow()
            lastLockError = nil
            refreshLockCapability()
            if markLocked {
                status = .locked
            }
        } catch {
            lastLockError = error.localizedDescription
            status = .error(error.localizedDescription)
        }
    }

    @objc private func handleWake() {
        classifier.suppressLocking(at: Date(), settings: settingsStore.settings)
        evaluateSignal(at: Date())
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var model = AppModel()
    private var statusMenuController: StatusMenuController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        settingsWindowController = SettingsWindowController(model: model)
        statusMenuController = StatusMenuController(model: model) { [weak self] in
            self?.openSettings()
        }
    }

    func applicationWillTerminate(_: Notification) {
        model.stop()
    }

    func openSettings() {
        settingsWindowController?.showWindow(nil)
    }
}
