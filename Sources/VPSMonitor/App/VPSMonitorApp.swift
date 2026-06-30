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

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.2"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "VPSMonitor" as NSString,
            .applicationVersion: appVersion as NSString,
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
        Button(L10n.text("О программе VPSMonitor", "About VPSMonitor", es: "Acerca de VPSMonitor", zh: "关于 VPSMonitor")) {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct AddServerMenuCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.text("Добавить сервер...", "Add Server...", es: "Añadir servidor...", zh: "添加服务器...")) {
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
        mainMenu.delegate = AppMenuLocalizationDelegate.shared
        relabelTopLevelMenuItems(in: mainMenu)
        relabelMenuItems(in: mainMenu)
    }

    @MainActor
    private static func relabelTopLevelMenuItems(in menu: NSMenu) {
        for item in menu.items {
            item.title = translatedTitle(for: item.title) ?? item.title
        }
    }

    @MainActor
    private static func relabelMenuItems(in menu: NSMenu) {
        menu.delegate = AppMenuLocalizationDelegate.shared
        for item in menu.items {
            if let searchField = item.view as? NSSearchField {
                searchField.placeholderString = L10n.text("Поиск", "Search", es: "Buscar", zh: "搜索")
            }
            if let submenu = item.submenu {
                relabelMenuItems(in: submenu)
            }
            if let translated = translatedTitle(for: item.title) {
                item.title = translated
                continue
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

    private static func translatedTitle(for title: String) -> String? {
        let normalized = title.replacingOccurrences(of: "…", with: "...")
        let groups: [(Set<String>, String)] = [
            (["File", "Файл", "Archivo", "文件"], L10n.text("Файл", "File", es: "Archivo", zh: "文件")),
            (["Edit", "Правка", "Edición", "编辑"], L10n.text("Правка", "Edit", es: "Edición", zh: "编辑")),
            (["View", "Вид", "Vista", "视图"], L10n.text("Вид", "View", es: "Vista", zh: "视图")),
            (["Window", "Окно", "Ventana", "窗口"], L10n.text("Окно", "Window", es: "Ventana", zh: "窗口")),
            (["Help", "Справка", "Ayuda", "帮助"], L10n.text("Справка", "Help", es: "Ayuda", zh: "帮助")),
            (["About VPSMonitor", "О программе VPSMonitor", "Acerca de VPSMonitor", "关于 VPSMonitor"], L10n.text("О программе VPSMonitor", "About VPSMonitor", es: "Acerca de VPSMonitor", zh: "关于 VPSMonitor")),
            (["Settings...", "Настройки...", "Ajustes...", "设置..."], L10n.text("Настройки...", "Settings...", es: "Ajustes...", zh: "设置...")),
            (["Services", "Службы", "Servicios", "服务"], L10n.text("Службы", "Services", es: "Servicios", zh: "服务")),
            (["Hide VPSMonitor", "Скрыть VPSMonitor", "Ocultar VPSMonitor", "隐藏 VPSMonitor"], L10n.text("Скрыть VPSMonitor", "Hide VPSMonitor", es: "Ocultar VPSMonitor", zh: "隐藏 VPSMonitor")),
            (["Hide Others", "Скрыть остальные", "Ocultar otras", "隐藏其他"], L10n.text("Скрыть остальные", "Hide Others", es: "Ocultar otras", zh: "隐藏其他")),
            (["Show All", "Показать все", "Mostrar todo", "显示全部"], L10n.text("Показать все", "Show All", es: "Mostrar todo", zh: "显示全部")),
            (["Quit VPSMonitor", "Завершить VPSMonitor", "Salir de VPSMonitor", "退出 VPSMonitor"], L10n.text("Завершить VPSMonitor", "Quit VPSMonitor", es: "Salir de VPSMonitor", zh: "退出 VPSMonitor")),
            (["Add Server...", "Добавить сервер...", "Añadir servidor...", "添加服务器..."], L10n.text("Добавить сервер...", "Add Server...", es: "Añadir servidor...", zh: "添加服务器...")),
            (["Edit VPS...", "Редактировать VPS...", "Editar VPS...", "编辑 VPS..."], L10n.text("Редактировать VPS...", "Edit VPS...", es: "Editar VPS...", zh: "编辑 VPS...")),
            (["VPSMonitor Help", "Справка VPSMonitor", "Ayuda de VPSMonitor", "VPSMonitor 帮助"], L10n.text("Справка VPSMonitor", "VPSMonitor Help", es: "Ayuda de VPSMonitor", zh: "VPSMonitor 帮助")),
            (["Undo", "Отменить", "Deshacer", "撤销"], L10n.text("Отменить", "Undo", es: "Deshacer", zh: "撤销")),
            (["Redo", "Повторить", "Rehacer", "重做"], L10n.text("Повторить", "Redo", es: "Rehacer", zh: "重做")),
            (["Cut", "Вырезать", "Cortar", "剪切"], L10n.text("Вырезать", "Cut", es: "Cortar", zh: "剪切")),
            (["Copy", "Копировать", "Copiar", "复制"], L10n.text("Копировать", "Copy", es: "Copiar", zh: "复制")),
            (["Paste", "Вставить", "Pegar", "粘贴"], L10n.text("Вставить", "Paste", es: "Pegar", zh: "粘贴")),
            (["Delete", "Удалить", "Eliminar", "删除"], L10n.text("Удалить", "Delete", es: "Eliminar", zh: "删除")),
            (["Select All", "Выбрать всё", "Seleccionar todo", "全选"], L10n.text("Выбрать всё", "Select All", es: "Seleccionar todo", zh: "全选")),
            (["Start Dictation...", "Начать диктовку...", "Iniciar dictado...", "开始听写..."], L10n.text("Начать диктовку...", "Start Dictation...", es: "Iniciar dictado...", zh: "开始听写...")),
            (["Emoji & Symbols", "Эмодзи и символы", "Emoji y símbolos", "表情与符号"], L10n.text("Эмодзи и символы", "Emoji & Symbols", es: "Emoji y símbolos", zh: "表情与符号")),
            (["Enter Full Screen", "На весь экран", "Pantalla completa", "进入全屏幕"], L10n.text("На весь экран", "Enter Full Screen", es: "Pantalla completa", zh: "进入全屏幕")),
            (["Minimize", "Свернуть", "Minimizar", "最小化"], L10n.text("Свернуть", "Minimize", es: "Minimizar", zh: "最小化")),
            (["Zoom", "Масштабировать", "Zoom", "缩放"], L10n.text("Масштабировать", "Zoom", es: "Zoom", zh: "缩放")),
            (["Bring All to Front", "Все окна на передний план", "Traer todo al frente", "全部置于前台"], L10n.text("Все окна на передний план", "Bring All to Front", es: "Traer todo al frente", zh: "全部置于前台"))
        ]
        return groups.first { $0.0.contains(normalized) }?.1
    }
}

@MainActor
private final class AppMenuLocalizationDelegate: NSObject, NSMenuDelegate {
    static let shared = AppMenuLocalizationDelegate()

    func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            AppMenuLocalizer.apply()
        }
    }
}
