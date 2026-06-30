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
        "VPSMonitor Help": "Ayuda de VPSMonitor",
        "Checking VPS": "Comprobando VPS",
        "Fetching projects and server metrics over SSH.": "Obteniendo proyectos y métricas del servidor por SSH.",
        "VPS not configured": "VPS sin configurar",
        "Add a server in Settings": "Añada un servidor en Ajustes",
        "Open Settings and add your first VPS.": "Abra Ajustes y añada su primer VPS.",
        "How the list is built": "Cómo se construye la lista",
        "The app scans /opt, /var/www, /srv, /app, /home/* and other directories, then links them to systemd services and live processes by working directory. Sites behind a shared nginx can appear as code without a dedicated service.": "La app escanea /opt, /var/www, /srv, /app, /home/* y otros directorios, y los vincula con servicios systemd y procesos activos por directorio de trabajo. Los sitios detrás de un nginx compartido pueden aparecer como código sin servicio dedicado.",
        "SSH password required": "Se requiere contraseña SSH",
        "SSH password": "Contraseña SSH",
        "Save and check": "Guardar y comprobar",
        "Waiting for check": "Esperando comprobación",
        "Checking": "Comprobando",
        "NEW": "NUEVO",
        "No application projects found.": "No se encontraron proyectos de aplicación.",
        "All projects are hidden. Click “Configure”.": "Todos los proyectos están ocultos. Pulse “Configurar”.",
        "Server": "Servidor",
        "Running": "En ejecución",
        "Needs attention: service is not running": "Requiere atención: el servicio no se está ejecutando",
        "Code found, no dedicated service or process is linked": "Código encontrado, sin servicio o proceso dedicado vinculado",
        "not running": "no se está ejecutando",
        "process": "proceso",
        "Investigate": "Investigar",
        "What changed": "Qué cambió",
        "Stopped projects": "Proyectos detenidos",
        "New since the stable state": "Nuevos desde el estado estable",
        "Recovered": "Recuperados",
        "Copy command": "Copiar comando",
        "Usual": "Habitual",
        "Edit server": "Editar servidor",
        "New password": "Nueva contraseña",
        "Leave blank to keep unchanged": "Déjelo vacío para no cambiarla",
        "Could not save password": "No se pudo guardar la contraseña",
        "key": "clave",
        "password": "contraseña",
        "Check automatically": "Comprobar automáticamente",
        "every 15 seconds": "cada 15 segundos",
        "every 30 seconds": "cada 30 segundos",
        "once a minute": "una vez por minuto",
        "The password is stored in macOS Keychain.": "La contraseña se guarda en macOS Keychain.",
        "My server": "Mi servidor"
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
        "VPSMonitor Help": "VPSMonitor 帮助",
        "Checking VPS": "正在检查 VPS",
        "Fetching projects and server metrics over SSH.": "正在通过 SSH 获取项目和服务器指标。",
        "VPS not configured": "未配置 VPS",
        "Add a server in Settings": "请在设置中添加服务器",
        "Open Settings and add your first VPS.": "打开设置并添加第一个 VPS。",
        "How the list is built": "列表如何生成",
        "The app scans /opt, /var/www, /srv, /app, /home/* and other directories, then links them to systemd services and live processes by working directory. Sites behind a shared nginx can appear as code without a dedicated service.": "应用会扫描 /opt、/var/www、/srv、/app、/home/* 和其他目录，并按工作目录关联 systemd 服务和运行进程。共享 nginx 后面的站点可能显示为没有专用服务的代码。",
        "SSH password required": "需要 SSH 密码",
        "SSH password": "SSH 密码",
        "Save and check": "保存并检查",
        "Waiting for check": "等待检查",
        "Checking": "正在检查",
        "NEW": "新",
        "No application projects found.": "未找到应用项目。",
        "All projects are hidden. Click “Configure”.": "所有项目都已隐藏。点击“配置”。",
        "Server": "服务器",
        "Running": "运行中",
        "Needs attention: service is not running": "需要关注：服务未运行",
        "Code found, no dedicated service or process is linked": "发现代码，但未关联专用服务或进程",
        "not running": "未运行",
        "process": "进程",
        "Investigate": "诊断",
        "What changed": "变化内容",
        "Stopped projects": "停止的项目",
        "New since the stable state": "稳定状态后新增",
        "Recovered": "已恢复",
        "Copy command": "复制命令",
        "Usual": "通常",
        "Edit server": "编辑服务器",
        "New password": "新密码",
        "Leave blank to keep unchanged": "留空则不更改",
        "Could not save password": "无法保存密码",
        "key": "密钥",
        "password": "密码",
        "Check automatically": "自动检查",
        "every 15 seconds": "每 15 秒",
        "every 30 seconds": "每 30 秒",
        "once a minute": "每分钟一次",
        "The password is stored in macOS Keychain.": "密码存储在 macOS Keychain 中。",
        "My server": "我的服务器"
    ]
}

public extension String {
    var localizedByVPSMonitorLanguage: String {
        L10n.text(self, self)
    }
}
