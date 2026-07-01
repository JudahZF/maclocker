import SwiftUI

struct DeviceSelectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(model.scannerState.displayText)
                        .foregroundStyle(model.scannerState.isBluetoothReady ? Color.secondary : Color.red)
                }
                Spacer()
                Button {
                    model.scanner.startDiscovery()
                } label: {
                    Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            if model.candidates.isEmpty {
                ContentUnavailableView(
                    "Watch not visible to macOS Bluetooth scan",
                    systemImage: "applewatch.slash",
                    description: Text("Nearby Bluetooth devices will appear here when macOS exposes them during discovery.")
                )
            } else {
                List(model.candidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        isSelected: model.settingsStore.settings.selectedPeripheralID == candidate.id
                    ) {
                        model.selectCandidate(candidate)
                    }
                }
                .listStyle(.inset)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
    }
}

private struct CandidateRow: View {
    let candidate: WatchCandidate
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.displayName ?? "Named device")
                        .font(.headline)
                    Text(candidate.id.uuidString.suffix(8))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                Text(candidate.advertisementSummary.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(candidate.rssi) dBm")
                    .font(.headline)
                    .monospacedDigit()
                Text("\(Int(Date().timeIntervalSince(candidate.lastSeen)))s ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(isSelected ? "Selected" : "Select") {
                select()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSelected)
        }
        .padding(.vertical, 6)
    }
}
