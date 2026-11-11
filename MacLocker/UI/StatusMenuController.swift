import AppKit
import Combine

@MainActor
final class StatusMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let openSettingsHandler: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        openSettingsHandler = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusButton()
        bindModel()
        rebuildMenu()
    }

    private func bindModel() {
        let publishers: [AnyPublisher<Void, Never>] = [
            model.$status.map { _ in () }.eraseToAnyPublisher(),
            model.$smoothedRSSI.map { _ in () }.eraseToAnyPublisher(),
            model.$candidates.map { _ in () }.eraseToAnyPublisher(),
            model.$lockCapability.map { _ in () }.eraseToAnyPublisher(),
            model.settingsStore.$settings.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(disabledItem("State: \(model.status.displayText)"))
        menu.addItem(disabledItem(selectedWatchTitle()))
        menu.addItem(disabledItem(rssiTitle()))
        menu.addItem(.separator())

        let autoLockTitle = model.settingsStore.settings.isAutoLockEnabled ? "Disable Auto-Lock" : "Enable Auto-Lock"
        let autoLockItem = NSMenuItem(title: autoLockTitle, action: #selector(toggleAutoLock), keyEquivalent: "")
        autoLockItem.target = self
        autoLockItem.isEnabled = model.settingsStore.settings.selectedPeripheralID != nil && model.settingsStore.settings.rssiThreshold != nil
        menu.addItem(autoLockItem)

        let pauseItem = NSMenuItem(title: model.isPaused ? "Resume Auto-Lock" : "Pause Auto-Lock", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.isEnabled = model.settingsStore.settings.isAutoLockEnabled
        menu.addItem(pauseItem)

        let calibrateItem = NSMenuItem(title: "Select Watch / Calibrate", action: #selector(openSettings), keyEquivalent: ",")
        calibrateItem.target = self
        menu.addItem(calibrateItem)

        menu.addItem(.separator())
        let lockItem = NSMenuItem(title: "Lock Now", action: #selector(lockNow), keyEquivalent: "l")
        lockItem.target = self
        menu.addItem(lockItem)

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = model.settingsStore.settings.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        let settingsItem = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        configureStatusButton()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.title = "MacLocker"
        }

        button.toolTip = buttonTitle()
        button.setAccessibilityLabel(buttonTitle())
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func selectedWatchTitle() -> String {
        guard let id = model.settingsStore.settings.selectedPeripheralID else {
            return "Selected Watch: None"
        }

        let suffix = id.uuidString.suffix(6)
        let name = model.candidates.first(where: { $0.id == id })?.displayName ?? "Device"
        return "Selected Watch: \(name) (\(suffix))"
    }

    private func rssiTitle() -> String {
        guard let smoothedRSSI = model.smoothedRSSI else {
            return "Smoothed RSSI: No sample"
        }
        return "Smoothed RSSI: \(Int(smoothedRSSI.rounded())) dBm"
    }

    private func buttonTitle() -> String {
        switch model.status {
        case .armed:
            "MacLocker: Armed"
        case .awayCountdown:
            "MacLocker: Away"
        case .locked:
            "MacLocker: Locked"
        case .paused:
            "MacLocker: Paused"
        case .error:
            "MacLocker: Error"
        case .disabled, .discovering, .calibrating:
            "MacLocker"
        }
    }

    @objc private func toggleAutoLock() {
        model.toggleAutoLock()
    }

    @objc private func togglePause() {
        model.togglePause()
    }

    @objc private func lockNow() {
        model.lockNowRequested()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.settingsStore.settings.launchAtLogin)
    }

    @objc private func openSettings() {
        openSettingsHandler()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
