import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let rootView = SettingsRootView(model: model)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MacLocker Settings"
        window.setContentSize(NSSize(width: 820, height: 600))
        window.minSize = NSSize(width: 700, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsRootView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case device = "Device"
        case calibration = "Calibration"
        case safety = "Safety"

        var id: String {
            rawValue
        }
    }

    @ObservedObject var model: AppModel
    @State private var selectedSection: SettingsSection = .device

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Settings Section", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                selectedView
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selectedSection {
        case .device:
            DeviceSelectionView(model: model)
        case .calibration:
            CalibrationView(model: model)
        case .safety:
            SafetySettingsView(model: model)
        }
    }
}
