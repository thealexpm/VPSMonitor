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
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup("VPSMonitor", id: "dashboard") {
            ContentView(store: store, updateChecker: updateChecker)
                .frame(minWidth: 760, minHeight: 620)
                .task {
                    store.start()
                    updateChecker.checkInBackground()
                }
        }
        .commands {
            // Use a View struct so @Environment(\.openWindow) is available
            CommandGroup(replacing: .appInfo) {
                AboutMenuCommand()
            }
        }

        WindowGroup(L10n.text("О программе", "About"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MonitorMenuView(store: store, updateChecker: updateChecker)
        } label: {
            Label(store.menuTitle, systemImage: store.menuSystemImage)
        }

        Settings {
            SettingsView(store: store)
        }
    }

    // MARK: - About panel (fallback, used if openWindow not available)

    private func showAboutPanel() {
        let body = L10n.text(
            """
            Нативный macOS-монитор для Linux VPS-серверов через SSH.
            Без агентов, без облака — только SSH и ваши ключи.

            Подключается по SSH, запускает read-only bash-скрипт \
            и показывает CPU, RAM, диск, аптайм и список проектов \
            прямо в menu bar.
            """,
            """
            A native macOS monitor for Linux VPS servers over SSH.
            No agents, no cloud — just SSH and your credentials.

            Connects over SSH, runs a read-only bash script, \
            and shows CPU, RAM, disk, uptime and projects \
            directly in the menu bar.
            """
        )

        let credits = NSMutableAttributedString(
            string: body,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        let linksStr = L10n.text(
            "\n\nПоддержка: @thealexpm  ·  GitHub: thealexpm/VPSMonitor",
            "\n\nSupport: @thealexpm  ·  GitHub: thealexpm/VPSMonitor"
        )
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

// MARK: - About menu command
// Needs to be a View so it can use @Environment(\.openWindow)
private struct AboutMenuCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.text("О программе VPSMonitor", "About VPSMonitor")) {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
