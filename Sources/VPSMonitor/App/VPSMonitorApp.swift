import AppKit
import SwiftUI
import VPSMonitorCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationService.requestAuthorization()
    }

    /// Overrides the default "About VPSMonitor" menu item to show rich content
    /// instead of the empty default panel.
    @objc func orderFrontStandardAboutPanel(_ sender: Any?) {
        let credits = NSMutableAttributedString()

        let body = NSAttributedString(string: """
            Нативный macOS-монитор для Linux VPS-серверов через SSH.
            Без агентов, без облака — только SSH и ваши ключи.

            Подключается по SSH, запускает read-only bash-скрипт \
            и показывает CPU, RAM, диск, аптайм и список проектов \
            прямо в menu bar.
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        credits.append(body)

        let linksText = "\n\nПоддержка: @thealexpm  ·  GitHub: thealexpm/VPSMonitor"
        let links = NSMutableAttributedString(string: linksText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        // Make Telegram clickable
        if let tgRange = linksText.range(of: "@thealexpm") {
            let nsRange = NSRange(tgRange, in: linksText)
            links.addAttribute(.link, value: URL(string: "https://t.me/thealexpm")!, range: nsRange)
        }
        // Make GitHub clickable
        if let ghRange = linksText.range(of: "thealexpm/VPSMonitor") {
            let nsRange = NSRange(ghRange, in: linksText)
            links.addAttribute(.link, value: URL(string: "https://github.com/thealexpm/VPSMonitor")!, range: nsRange)
        }
        credits.append(links)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "VPSMonitor" as NSString,
            .applicationVersion: "1.0" as NSString,
            .version:            "" as NSString,  // hides build number row
            .credits:            credits
        ])
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
}
