import Combine
import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case russian = "ru"
    case english = "en"
    case spanish = "es"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    public var localeIdentifier: String {
        switch self {
        case .system:
            Locale.preferredLanguages.first ?? "en"
        case .russian:
            "ru_RU"
        case .english:
            "en_US"
        case .spanish:
            "es_ES"
        case .chinese:
            "zh_Hans_CN"
        }
    }

    public var menuTitle: String {
        switch self {
        case .system:
            return L10n.text("Как в системе", "System", es: "Sistema", zh: "跟随系统")
        case .russian:
            return "Русский"
        case .english:
            return "English"
        case .spanish:
            return "Español"
        case .chinese:
            return "中文"
        }
    }
}

@MainActor
public final class AppLanguageStore: ObservableObject {
    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: L10n.languageDefaultsKey)
            NotificationCenter.default.post(name: L10n.languageDidChangeNotification, object: nil)
        }
    }

    public init() {
        if let raw = UserDefaults.standard.string(forKey: L10n.languageDefaultsKey),
           let language = AppLanguage(rawValue: raw) {
            self.language = language
        } else {
            self.language = .system
        }
    }
}

public enum L10n {
    public static let languageDefaultsKey = "app.languageCode"
    public static let languageDidChangeNotification = Notification.Name("VPSMonitorLanguageDidChange")

    /// Force a specific language for screenshots/testing by setting
    /// `VPSMONITOR_LANG=ru`, `en`, `es` or `zh` in the launch environment.
    /// Otherwise falls back to the system preferred language.
    public static var currentLanguage: AppLanguage {
        if let forced = ProcessInfo.processInfo.environment["VPSMONITOR_LANG"]?.lowercased() {
            if forced.hasPrefix("ru") { return .russian }
            if forced.hasPrefix("es") { return .spanish }
            if forced.hasPrefix("zh") { return .chinese }
            return .english
        }
        if let raw = UserDefaults.standard.string(forKey: languageDefaultsKey),
           let stored = AppLanguage(rawValue: raw),
           stored != .system {
            return stored
        }
        let preferred = AppLanguage.system.localeIdentifier
        let languageCode = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        if languageCode == "ru" { return .russian }
        if languageCode == "es" { return .spanish }
        if languageCode == "zh" { return .chinese }
        return .english
    }

    public static var isRussian: Bool {
        currentLanguage == .russian
    }

    public static var locale: Locale {
        Locale(identifier: currentLanguage.localeIdentifier)
    }

    public static func text(_ russian: String, _ english: String, es spanish: String? = nil, zh chinese: String? = nil) -> String {
        switch currentLanguage {
        case .russian:
            return russian
        case .english, .system:
            return english
        case .spanish:
            return spanish ?? fallbackSpanish[english] ?? english
        case .chinese:
            return chinese ?? fallbackChinese[english] ?? english
        }
    }

    private static let fallbackSpanish: [String: String] = [
        "Add VPS": "Añadir VPS",
        "About": "Acerca de",
        "About VPSMonitor": "Acerca de VPSMonitor",
        "Settings": "Ajustes",
        "Open monitor": "Abrir monitor",
        "Add Server...": "Añadir servidor...",
        "Check now": "Comprobar ahora",
        "Check for updates": "Buscar actualizaciones",
        "Update available": "Actualización disponible",
        "Quit": "Salir",
        "Servers": "Servidores",
        "Name": "Nombre",
        "VPS address": "Dirección VPS",
        "SSH user": "Usuario SSH",
        "Country": "País",
        "Connection": "Conexión",
        "SSH key (recommended)": "Clave SSH (recomendada)",
        "Username and password": "Usuario y contraseña",
        "Password": "Contraseña",
        "Enter password": "Introduce la contraseña",
        "Add server": "Añadir servidor",
        "Edit": "Editar",
        "Delete": "Eliminar",
        "Save": "Guardar",
        "Cancel": "Cancelar",
        "Done": "Listo",
        "History": "Historial",
        "Server now": "Servidor ahora",
        "CPU": "CPU",
        "Memory": "Memoria",
        "Disk": "Disco",
        "VPS response": "Respuesta VPS",
        "Uptime": "Sin reinicio",
        "Last check": "Última comprobación",
        "Detected projects": "Proyectos detectados",
        "Configure": "Configurar",
        "Everything works": "Todo funciona",
        "Needs attention": "Requiere atención",
        "Error": "Error",
        "No servers": "Sin servidores",
        "Open Settings": "Abrir ajustes",
        "Metric history": "Historial de métricas",
        "Copy report": "Copiar informe",
        "Copied": "Copiado",
        "Manual check commands": "Comandos de comprobación manual",
        "Auto": "Auto",
        "Help": "Ayuda",
        "VPSMonitor Help": "Ayuda de VPSMonitor"
    ]

    private static let fallbackChinese: [String: String] = [
        "Add VPS": "添加 VPS",
        "About": "关于",
        "About VPSMonitor": "关于 VPSMonitor",
        "Settings": "设置",
        "Open monitor": "打开监控",
        "Add Server...": "添加服务器...",
        "Check now": "立即检查",
        "Check for updates": "检查更新",
        "Update available": "有可用更新",
        "Quit": "退出",
        "Servers": "服务器",
        "Name": "名称",
        "VPS address": "VPS 地址",
        "SSH user": "SSH 用户",
        "Country": "国家/地区",
        "Connection": "连接",
        "SSH key (recommended)": "SSH 密钥（推荐）",
        "Username and password": "用户名和密码",
        "Password": "密码",
        "Enter password": "输入密码",
        "Add server": "添加服务器",
        "Edit": "编辑",
        "Delete": "删除",
        "Save": "保存",
        "Cancel": "取消",
        "Done": "完成",
        "History": "历史",
        "Server now": "服务器当前状态",
        "CPU": "CPU",
        "Memory": "内存",
        "Disk": "磁盘",
        "VPS response": "VPS 响应",
        "Uptime": "运行时间",
        "Last check": "上次检查",
        "Detected projects": "检测到的项目",
        "Configure": "配置",
        "Everything works": "一切正常",
        "Needs attention": "需要关注",
        "Error": "错误",
        "No servers": "没有服务器",
        "Open Settings": "打开设置",
        "Metric history": "指标历史",
        "Copy report": "复制报告",
        "Copied": "已复制",
        "Manual check commands": "手动检查命令",
        "Auto": "自动",
        "Help": "帮助",
        "VPSMonitor Help": "VPSMonitor 帮助"
    ]
}

public extension String {
    var localizedByVPSMonitorLanguage: String {
        L10n.text(self, self)
    }
}
