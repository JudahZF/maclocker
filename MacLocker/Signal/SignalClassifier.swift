import Foundation

struct SignalPreconditions: Equatable {
    var isBluetoothReady: Bool
    var hasSelection: Bool
    var isCalibrated: Bool
    var isAutoLockEnabled: Bool
    var isPaused: Bool
}

enum SignalEvaluationState: Equatable {
    case disabled
    case unauthorized
    case unselected
    case uncalibrated
    case grace(until: Date)
    case monitoring
    case awayCountdown(TimeInterval)
    case locked
    case paused
}

struct SignalEvaluation: Equatable {
    var state: SignalEvaluationState
    var shouldLock: Bool
    var smoothedRSSI: Double?
}

struct SignalClassifier: Equatable {
    private(set) var smoothedRSSI: Double?
    private(set) var lastSampleAt: Date?

    private var awayEvidenceStartedAt: Date?
    private var nearEvidenceStartedAt: Date?
    private var monitoringStartedAt: Date?
    private var lockedThisAwaySession = false
    private var graceUntil: Date?

    private let alpha = 0.35
    private let nearHysteresisDB = 6.0

    mutating func observe(_ event: WatchSignalEvent, selectedPeripheralID: UUID?) {
        guard event.peripheralID == selectedPeripheralID else { return }

        if let smoothedRSSI {
            self.smoothedRSSI = alpha * Double(event.rssi) + (1 - alpha) * smoothedRSSI
        } else {
            smoothedRSSI = Double(event.rssi)
        }
        lastSampleAt = event.timestamp
    }

    mutating func reset() {
        smoothedRSSI = nil
        lastSampleAt = nil
        awayEvidenceStartedAt = nil
        nearEvidenceStartedAt = nil
        monitoringStartedAt = nil
        lockedThisAwaySession = false
        graceUntil = nil
    }

    mutating func suppressLocking(at now: Date, settings: LockSettings) {
        graceUntil = now.addingTimeInterval(settings.graceAfterUnlockSeconds)
        awayEvidenceStartedAt = nil
        nearEvidenceStartedAt = nil
        monitoringStartedAt = now
        lockedThisAwaySession = false
    }

    mutating func evaluate(
        at now: Date,
        settings: LockSettings,
        preconditions: SignalPreconditions
    ) -> SignalEvaluation {
        guard preconditions.isAutoLockEnabled else {
            clearSessionState()
            return SignalEvaluation(state: .disabled, shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        guard preconditions.isBluetoothReady else {
            clearSessionState(keepSamples: true)
            return SignalEvaluation(state: .unauthorized, shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        guard preconditions.hasSelection else {
            clearSessionState()
            return SignalEvaluation(state: .unselected, shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        guard preconditions.isCalibrated, let threshold = settings.rssiThreshold else {
            clearSessionState(keepSamples: true)
            return SignalEvaluation(state: .uncalibrated, shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        guard !preconditions.isPaused else {
            return SignalEvaluation(state: .paused, shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        if let graceUntil, now < graceUntil {
            return SignalEvaluation(state: .grace(until: graceUntil), shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        if monitoringStartedAt == nil {
            monitoringStartedAt = now
        }

        let missingDuration = signalMissingDuration(at: now)
        let missingSignal = missingDuration >= settings.missingSignalSeconds
        let weakSignal = smoothedRSSI.map { $0 < Double(threshold) } ?? false
        let awayEvidence = weakSignal || missingSignal
        let nearEvidence = !missingSignal && (smoothedRSSI.map { $0 >= Double(threshold) + nearHysteresisDB } ?? false)

        if nearEvidence {
            if nearEvidenceStartedAt == nil {
                nearEvidenceStartedAt = now
            }

            if let nearEvidenceStartedAt,
               now.timeIntervalSince(nearEvidenceStartedAt) >= settings.nearHoldSeconds
            {
                awayEvidenceStartedAt = nil
                lockedThisAwaySession = false
            }
        } else {
            nearEvidenceStartedAt = nil
        }

        // Once started, neutral-band RSSI keeps the countdown running until sustained near evidence resets it.
        if awayEvidence || awayEvidenceStartedAt != nil {
            if awayEvidenceStartedAt == nil {
                awayEvidenceStartedAt = now
            }

            let elapsed = now.timeIntervalSince(awayEvidenceStartedAt ?? now)
            let remaining = max(0, settings.awayHoldSeconds - elapsed)
            if remaining <= 0 {
                if !lockedThisAwaySession {
                    lockedThisAwaySession = true
                    return SignalEvaluation(state: .locked, shouldLock: true, smoothedRSSI: smoothedRSSI)
                }
                return SignalEvaluation(state: .locked, shouldLock: false, smoothedRSSI: smoothedRSSI)
            }
            return SignalEvaluation(state: .awayCountdown(remaining), shouldLock: false, smoothedRSSI: smoothedRSSI)
        }

        return SignalEvaluation(state: .monitoring, shouldLock: false, smoothedRSSI: smoothedRSSI)
    }

    private func signalMissingDuration(at now: Date) -> TimeInterval {
        if let lastSampleAt {
            return now.timeIntervalSince(lastSampleAt)
        }
        return now.timeIntervalSince(monitoringStartedAt ?? now)
    }

    private mutating func clearSessionState(keepSamples: Bool = false) {
        awayEvidenceStartedAt = nil
        nearEvidenceStartedAt = nil
        monitoringStartedAt = nil
        lockedThisAwaySession = false
        graceUntil = nil

        if !keepSamples {
            smoothedRSSI = nil
            lastSampleAt = nil
        }
    }
}
