import AppKit
import SwiftUI
import VPSMonitorCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationService.requestAuthorization()
    }
}

@main
struct VPSMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore()

    var body: some Scene {
        WindowGroup("VPSMonitor", id: "dashboard") {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 620)
                .task { store.start() }
        }
        .commands {
            // Replace the default empty "About VPSMonitor" with our own
            CommandGroup(replacing: .appInfo) {
                Button("О программе VPSMonitor") {
                    showAboutPanel()
                }
            }
        }

        WindowGroup("О программе", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MonitorMenuView(store: store)
        } label: {
            Label(store.menuTitle, systemImage: store.menuSystemImage)
        }

        Settings {
            SettingsView(store: store)
        }
    }

    // MARK: - About panel

    private func showAboutPanel() {
        let body = """
            Нативный macOS-монитор для Linux VPS-серверов через SSH.
            Без агентов, без облака — только SSH и ваши ключи.

            Подключается по SSH, запускает read-only bash-скрипт \
            и показывает CPU, RAM, диск, аптайм и список проектов \
            прямо в menu bar.
            """

        let credits = NSMutableAttributedString(
            string: body,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        let linksStr = "\n\nПоддержка: @thealexpm  ·  GitHub: thealexpm/VPSMonitor"
        let links = NSMutableAttributedString(
            string: linksStr,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        if let r = linksStr.range(of: "@thealexpm") {
            links.addAttribute(.link,
                               value: URL(string: "https://t.me/thealexpm")!,
                               range: NSRange(r, in: linksStr))
        }
        if let r = linksStr.range(of: "thealexpm/VPSMonitor") {
            links.addAttribute(.link,
                               value: URL(string: "https://github.com/thealexpm/VPSMonitor")!,
                               range: NSRange(r, in: linksStr))
        }
        credits.append(links)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "VPSMonitor" as NSString,
            .applicationVersion: "1.0" as NSString,
            .version:            "" as NSString,
            .credits:            credits
        ])
    }
}
