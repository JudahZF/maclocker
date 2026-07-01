import SwiftUI

@main
struct MacLockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsOpenerView {
                appDelegate.openSettings()
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

private struct SettingsOpenerView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("MacLocker Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                openSettings()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 320, height: 160)
        .onAppear(perform: openSettings)
    }
}
