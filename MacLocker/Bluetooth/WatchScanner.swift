import Combine
@preconcurrency import CoreBluetooth
import Foundation

struct WatchCandidate: Identifiable, Equatable {
    let id: UUID
    var displayName: String?
    var rssi: Int
    var lastSeen: Date
    var advertisementSummary: AdvertisementSummary
}

protocol WatchScanning: AnyObject {
    func startDiscovery()
    func stopDiscovery()
    func selectPeripheral(id: UUID)
}

enum WatchScannerState: Equatable {
    case idle
    case unauthorized(BluetoothAuthorizationStatus)
    case unsupported
    case poweredOff
    case resetting
    case discovering
    case error(String)

    var isBluetoothReady: Bool {
        self == .discovering
    }

    var displayText: String {
        switch self {
        case .idle:
            "Bluetooth idle"
        case let .unauthorized(status):
            status.displayText
        case .unsupported:
            "Bluetooth unsupported"
        case .poweredOff:
            "Bluetooth powered off"
        case .resetting:
            "Bluetooth resetting"
        case .discovering:
            "Discovering Bluetooth devices"
        case let .error(message):
            message
        }
    }
}

final class WatchScanner: NSObject, ObservableObject, WatchScanning {
    @Published private(set) var candidates: [WatchCandidate] = []
    @Published private(set) var state: WatchScannerState = .idle

    var onSignalEvent: ((WatchSignalEvent) -> Void)?

    private var centralManager: CBCentralManager?
    private var candidatesByID: [UUID: WatchCandidate] = [:]
    private var wantsScanning = false
    private var selectedPeripheralID: UUID?
    private let candidatePublishInterval: TimeInterval = 1
    private var lastCandidatePublishAt: Date?
    private var pendingCandidatePublishTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startDiscovery() {
        wantsScanning = true
        startScanningIfPossible()
    }

    func stopDiscovery() {
        wantsScanning = false
        centralManager?.stopScan()
        pendingCandidatePublishTimer?.invalidate()
        pendingCandidatePublishTimer = nil
        state = .idle
    }

    func selectPeripheral(id: UUID) {
        selectedPeripheralID = id
    }

    private func startScanningIfPossible() {
        guard wantsScanning, let centralManager else { return }

        let authorization = BluetoothAuthorization.current
        guard authorization == .allowed else {
            state = .unauthorized(authorization)
            return
        }

        switch centralManager.state {
        case .poweredOn:
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            state = .discovering
        case .poweredOff:
            centralManager.stopScan()
            state = .poweredOff
        case .unsupported:
            state = .unsupported
        case .resetting:
            state = .resetting
        case .unauthorized:
            state = .unauthorized(authorization)
        case .unknown:
            state = .idle
        @unknown default:
            state = .error("Unknown Bluetooth state")
        }
    }

    private func publishCandidates() {
        candidates = candidatesByID.values.sorted { left, right in
            if left.rssi == right.rssi {
                return left.lastSeen > right.lastSeen
            }
            return left.rssi > right.rssi
        }
        lastCandidatePublishAt = Date()
        pendingCandidatePublishTimer?.invalidate()
        pendingCandidatePublishTimer = nil
    }

    private func requestCandidatePublish(at now: Date) {
        guard let lastCandidatePublishAt else {
            publishCandidates()
            return
        }

        let elapsed = now.timeIntervalSince(lastCandidatePublishAt)
        guard elapsed < candidatePublishInterval else {
            publishCandidates()
            return
        }

        guard pendingCandidatePublishTimer == nil else { return }
        pendingCandidatePublishTimer = Timer.scheduledTimer(
            timeInterval: candidatePublishInterval - elapsed,
            target: self,
            selector: #selector(publishPendingCandidates),
            userInfo: nil,
            repeats: false
        )
    }

    private func isValidRSSI(_ rssi: Int) -> Bool {
        rssi < 0 && rssi != 127
    }

    private func normalizedDisplayName(_ displayName: String?) -> String? {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedName, !trimmedName.isEmpty else { return nil }
        return trimmedName
    }

    @objc private func publishPendingCandidates() {
        publishCandidates()
    }
}

extension WatchScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_: CBCentralManager) {
        startScanningIfPossible()
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue
        guard isValidRSSI(rssi) else { return }

        let now = Date()
        let id = peripheral.identifier
        let summary = AdvertisementSummary(advertisementData: advertisementData)
        guard let displayName = normalizedDisplayName(peripheral.name ?? summary.localName) else {
            candidatesByID[id] = nil
            requestCandidatePublish(at: now)
            return
        }

        let candidate = WatchCandidate(
            id: id,
            displayName: displayName,
            rssi: rssi,
            lastSeen: now,
            advertisementSummary: summary
        )
        candidatesByID[id] = candidate
        requestCandidatePublish(at: now)

        if selectedPeripheralID == id {
            onSignalEvent?(
                WatchSignalEvent(
                    peripheralID: id,
                    rssi: rssi,
                    timestamp: candidate.lastSeen
                )
            )
        }
    }
}
