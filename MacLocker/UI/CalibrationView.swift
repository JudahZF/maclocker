import SwiftUI

struct CalibrationView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Calibration")
                .font(.title2)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Selected")
                        .foregroundStyle(.secondary)
                    Text(selectedDeviceText)
                        .monospaced()
                }
                GridRow {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Text(model.calibrationPhase.displayText)
                }
                GridRow {
                    Text("Threshold")
                        .foregroundStyle(.secondary)
                    Text(thresholdText)
                        .monospacedDigit()
                }
                GridRow {
                    Text("Smoothed RSSI")
                        .foregroundStyle(.secondary)
                    Text(smoothedRSSIText)
                        .monospacedDigit()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Manual Threshold")
                    .font(.headline)

                HStack(spacing: 14) {
                    Slider(value: manualThresholdBinding, in: -90 ... -45, step: 1)
                        .frame(maxWidth: 360)
                        .disabled(model.settingsStore.settings.selectedPeripheralID == nil)

                    Stepper(
                        "\(manualThresholdValue) dBm",
                        value: manualThresholdBinding,
                        in: -90 ... -45,
                        step: 1
                    )
                    .frame(width: 150, alignment: .leading)
                    .monospacedDigit()
                    .disabled(model.settingsStore.settings.selectedPeripheralID == nil)
                }

                HStack(spacing: 12) {
                    Button {
                        if let smoothedRSSI = model.smoothedRSSI {
                            model.setManualRSSIThreshold(Int(smoothedRSSI.rounded()))
                        }
                    } label: {
                        Label("Use Current RSSI", systemImage: "waveform.path.ecg")
                    }
                    .disabled(model.settingsStore.settings.selectedPeripheralID == nil || model.smoothedRSSI == nil)

                    Button {
                        model.clearManualRSSIThreshold()
                    } label: {
                        Label("Clear Threshold", systemImage: "xmark.circle")
                    }
                    .disabled(model.settingsStore.settings.rssiThreshold == nil)
                }

                Text("Lower values tolerate weaker signal before locking. Near evidence must be at least 6 dB stronger than the threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    model.startNearCalibration()
                } label: {
                    Label("Record Near", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(model.calibrationPhase.isRecording || model.settingsStore.settings.selectedPeripheralID == nil)

                Button {
                    model.startAwayCalibration()
                } label: {
                    Label("Record Away", systemImage: "figure.walk.motion")
                }
                .disabled(model.calibrationPhase != .nearComplete)
            }

            if let result = model.calibrationResult {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Calibration accepted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Near median \(Int(result.nearMedian.rounded())) dBm, away median \(Int(result.awayMedian.rounded())) dBm")
                        .foregroundStyle(.secondary)
                }
            }

            if let calibrationError = model.calibrationError {
                Label(calibrationError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
    }

    private var manualThresholdValue: Int {
        model.settingsStore.settings.rssiThreshold ?? -65
    }

    private var manualThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(manualThresholdValue) },
            set: { model.setManualRSSIThreshold(Int($0.rounded())) }
        )
    }

    private var selectedDeviceText: String {
        guard let id = model.settingsStore.settings.selectedPeripheralID else {
            return "None"
        }
        return String(id.uuidString.suffix(12))
    }

    private var thresholdText: String {
        guard let threshold = model.settingsStore.settings.rssiThreshold else {
            return "Not calibrated"
        }
        return "\(threshold) dBm"
    }

    private var smoothedRSSIText: String {
        guard let smoothedRSSI = model.smoothedRSSI else {
            return "No sample"
        }
        return "\(Int(smoothedRSSI.rounded())) dBm"
    }
}
