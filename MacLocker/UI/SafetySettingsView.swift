import SwiftUI

struct SafetySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Safety")
                .font(.title2)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Immediate lock")
                        .foregroundStyle(.secondary)
                    Text(model.lockCapability.accessibilityTrusted ? "Accessibility granted" : "Accessibility not granted")
                }
                GridRow {
                    Text("Fallback")
                        .foregroundStyle(.secondary)
                    Text(fallbackText)
                }
                GridRow {
                    Text("Auto-lock")
                        .foregroundStyle(.secondary)
                    Text(model.settingsStore.settings.isAutoLockEnabled ? "Enabled" : "Disabled")
                }
                GridRow {
                    Text("Grace")
                        .foregroundStyle(.secondary)
                    Text("\(Int(model.settingsStore.settings.graceAfterUnlockSeconds))s")
                        .monospacedDigit()
                }
            }

            if let warning = model.lockCapability.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if let lastLockError = model.lastLockError {
                Label(lastLockError, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            if let lastLaunchAtLoginError = model.lastLaunchAtLoginError {
                Label(lastLaunchAtLoginError, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            if let lastPersistenceError = model.settingsStore.lastPersistenceError {
                Label(lastPersistenceError, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Timing Thresholds")
                    .font(.headline)

                timingStepper(
                    "Away hold",
                    value: awayHoldBinding,
                    range: 5 ... 120,
                    help: "Weak or missing signal must persist this long before locking."
                )

                timingStepper(
                    "Missing signal",
                    value: missingSignalBinding,
                    range: 2 ... 60,
                    help: "No selected-watch sample for this long counts as away evidence."
                )

                timingStepper(
                    "Near reset",
                    value: nearHoldBinding,
                    range: 2 ... 60,
                    help: "Near evidence must persist this long before the away session resets."
                )

                timingStepper(
                    "Grace after unlock",
                    value: graceBinding,
                    range: 0 ... 300,
                    help: "Auto-lock is suppressed for this long after launch, wake, unlock, or resume."
                )
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    model.openAccessibilityPrompt()
                } label: {
                    Label("Accessibility", systemImage: "figure.wave")
                }

                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { model.settingsStore.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    "Auto-Lock",
                    isOn: Binding(
                        get: { model.settingsStore.settings.isAutoLockEnabled },
                        set: { _ in model.toggleAutoLock() }
                    )
                )
                .toggleStyle(.switch)
                .disabled(model.settingsStore.settings.selectedPeripheralID == nil || model.settingsStore.settings.rssiThreshold == nil)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .onAppear {
            model.refreshLockCapability()
        }
    }

    private var awayHoldBinding: Binding<Double> {
        Binding(
            get: { model.settingsStore.settings.awayHoldSeconds },
            set: { model.setAwayHoldSeconds($0) }
        )
    }

    private var missingSignalBinding: Binding<Double> {
        Binding(
            get: { model.settingsStore.settings.missingSignalSeconds },
            set: { model.setMissingSignalSeconds($0) }
        )
    }

    private var nearHoldBinding: Binding<Double> {
        Binding(
            get: { model.settingsStore.settings.nearHoldSeconds },
            set: { model.setNearHoldSeconds($0) }
        )
    }

    private var graceBinding: Binding<Double> {
        Binding(
            get: { model.settingsStore.settings.graceAfterUnlockSeconds },
            set: { model.setGraceAfterUnlockSeconds($0) }
        )
    }

    private func timingStepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        help: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 280, alignment: .leading)

            Stepper(
                "\(Int(value.wrappedValue.rounded()))s",
                value: value,
                in: range,
                step: 1
            )
            .monospacedDigit()
            .frame(width: 120, alignment: .leading)
        }
    }

    private var fallbackText: String {
        guard let delay = model.lockCapability.passwordDelay else {
            return "Display sleep"
        }

        if delay <= 0 {
            return "Display sleep, password required immediately"
        }
        return "Display sleep, password delay \(Int(delay))s"
    }
}
