import AppKit
import SwiftUI
import VPSMonitorCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationService.requestAuthorization()
        localizeMenus()
        languageObserver = NotificationCenter.default.addObserver(
            forName: L10n.languageDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppMenuLocalizer.applyRepeatedly()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        localizeMenus()
    }

    private func localizeMenus() {
        Task { @MainActor in
            AppMenuLocalizer.applyRepeatedly()
        }
    }
}

@main
struct VPSMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore()
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var languageStore = AppLanguageStore()

    var body: some Scene {
        WindowGroup("VPSMonitor", id: "dashboard") {
            ContentView(store: store, updateChecker: updateChecker)
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
                .frame(minWidth: 760, minHeight: 620)
                .task {
                    store.start()
                    updateChecker.checkInBackground()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                AddServerMenuCommand()
            }
            CommandGroup(after: .pasteboard) {
                EditServersMenuCommand()
            }
            CommandGroup(replacing: .appInfo) {
                AboutMenuCommand()
            }
            CommandGroup(replacing: .help) {
                HelpMenuCommand()
            }
        }

        WindowGroup(L10n.text("Добавить VPS", "Add VPS"), id: "addServer") {
            AddServerWindow(store: store)
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
        }
        .windowResizability(.contentSize)

        WindowGroup(L10n.text("Редактировать VPS", "Edit VPS", es: "Editar VPS", zh: "编辑 VPS"), id: "editServers") {
            EditServersWindow(store: store)
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
        }
        .windowResizability(.contentSize)

        WindowGroup(L10n.text("О программе", "About"), id: "about") {
            AboutView()
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
        }
        .windowResizability(.contentSize)

        WindowGroup(L10n.text("Справка VPSMonitor", "VPSMonitor Help", es: "Ayuda de VPSMonitor", zh: "VPSMonitor 帮助"), id: "help") {
            HelpView()
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MonitorMenuView(store: store, updateChecker: updateChecker)
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
        } label: {
            Label(store.menuTitle, systemImage: store.menuSystemImage)
        }

        Settings {
            SettingsView(store: store)
                .environmentObject(languageStore)
                .id(languageStore.language.rawValue)
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

private struct AddServerMenuCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.text("Добавить сервер...", "Add Server...")) {
            openWindow(id: "addServer")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

private struct EditServersMenuCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.text("Редактировать VPS...", "Edit VPS...", es: "Editar VPS...", zh: "编辑 VPS...")) {
            openWindow(id: "editServers")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
    }
}

private struct HelpMenuCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.text("Справка VPSMonitor", "VPSMonitor Help", es: "Ayuda de VPSMonitor", zh: "VPSMonitor 帮助")) {
            openWindow(id: "help")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("/", modifiers: .command)
    }
}

private struct AddServerWindow: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MonitorStore

    var body: some View {
        AddServerView(store: store) {
            dismiss()
        }
    }
}

private struct EditServersWindow: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        EditServersView(store: store)
    }
}

enum SettingsWindowPresenter {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

enum AppMenuLocalizer {
    @MainActor
    static func applyRepeatedly() {
        apply()
        for delay in [0.05, 0.2, 0.75, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    apply()
                }
            }
        }
    }

    @MainActor
    static func apply() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let menuTitles = [
            L10n.text("VPSMonitor", "VPSMonitor", es: "VPSMonitor", zh: "VPSMonitor"),
            L10n.text("Файл", "File", es: "Archivo", zh: "文件"),
            L10n.text("Правка", "Edit", es: "Edición", zh: "编辑"),
            L10n.text("Вид", "View", es: "Vista", zh: "视图"),
            L10n.text("Окно", "Window", es: "Ventana", zh: "窗口"),
            L10n.text("Справка", "Help", es: "Ayuda", zh: "帮助")
        ]
        for (index, title) in menuTitles.enumerated() where index < mainMenu.items.count {
            mainMenu.items[index].title = title
        }
        relabelTopLevelMenuItems(in: mainMenu)

        relabelMenuItems(in: mainMenu)
    }

    @MainActor
    private static func relabelTopLevelMenuItems(in menu: NSMenu) {
        let groups: [(Set<String>, String)] = [
            (["File", "Файл", "Archivo", "文件"], L10n.text("Файл", "File", es: "Archivo", zh: "文件")),
            (["Edit", "Правка", "Edición", "编辑"], L10n.text("Правка", "Edit", es: "Edición", zh: "编辑")),
            (["View", "Вид", "Vista", "视图"], L10n.text("Вид", "View", es: "Vista", zh: "视图")),
            (["Window", "Окно", "Ventana", "窗口"], L10n.text("Окно", "Window", es: "Ventana", zh: "窗口")),
            (["Help", "Справка", "Ayuda", "帮助"], L10n.text("Справка", "Help", es: "Ayuda", zh: "帮助"))
        ]
        for item in menu.items {
            if let match = groups.first(where: { $0.0.contains(item.title) }) {
                item.title = match.1
            }
        }
    }

    @MainActor
    private static func relabelMenuItems(in menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                relabelMenuItems(in: submenu)
            }
            guard let action = item.action else { continue }
            switch NSStringFromSelector(action) {
            case "showSettingsWindow:":
                item.title = L10n.text("Настройки...", "Settings...", es: "Ajustes...", zh: "设置...")
            case "terminate:":
                item.title = L10n.text("Завершить VPSMonitor", "Quit VPSMonitor", es: "Salir de VPSMonitor", zh: "退出 VPSMonitor")
            case "hide:":
                item.title = L10n.text("Скрыть VPSMonitor", "Hide VPSMonitor", es: "Ocultar VPSMonitor", zh: "隐藏 VPSMonitor")
            case "hideOtherApplications:":
                item.title = L10n.text("Скрыть остальные", "Hide Others", es: "Ocultar otras", zh: "隐藏其他")
            case "unhideAllApplications:":
                item.title = L10n.text("Показать все", "Show All", es: "Mostrar todo", zh: "显示全部")
            default:
                continue
            }
        }
    }
}
