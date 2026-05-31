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
        WindowGroup("Мой VPS", id: "dashboard") {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 620)
                .task { store.start() }
        }

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
