import AppKit
import SwiftUI
import VPSMonitorCore

struct AboutView: View {
    private let telegramURL = URL(string: "https://t.me/thealexpm")!
    private let githubURL   = URL(string: "https://github.com/thealexpm/VPSMonitor")!

    private let strings = AboutStrings.current
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.2"
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Icon + name ──────────────────────────────────────────────
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 80, height: 80)
                Text("VPSMonitor")
                    .font(.system(size: 22, weight: .bold))
                Text(strings.versionLabel(appVersion))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 32).padding(.bottom, 24)

            Divider()

            // ── Description ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 16) {
                AboutSection(title: strings.whatItDoesTitle) {
                    Text(strings.whatItDoesBody)
                }
                AboutSection(title: strings.howItWorksTitle) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(strings.howItWorksBullets, id: \.self) { BulletRow($0) }
                    }
                }
                AboutSection(title: strings.trackedTitle) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(strings.trackedBullets, id: \.self) { BulletRow($0) }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20)

            Divider()

            // ── Support links ────────────────────────────────────────────
            HStack(spacing: 12) {
                LinkButton(label: strings.telegramButton,
                           systemImage: "paperplane.fill",
                           color: .blue,
                           url: telegramURL)
                LinkButton(label: "GitHub",
                           systemImage: "chevron.left.slash.chevron.right",
                           color: .primary,
                           url: githubURL)
            }
            .padding(.horizontal, 28).padding(.vertical, 18)

            Text(strings.copyright)
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(width: 480)
        .fixedSize()
    }
}

// MARK: - Localized strings

private struct AboutStrings {
    let versionPrefix: String
    let whatItDoesTitle: String
    let whatItDoesBody: String
    let howItWorksTitle: String
    let howItWorksBullets: [String]
    let trackedTitle: String
    let trackedBullets: [String]
    let telegramButton: String
    let copyright: String

    func versionLabel(_ version: String) -> String {
        "\(versionPrefix) \(version)"
    }

    static var current: AboutStrings {
        switch L10n.currentLanguage {
        case .russian:
            .russian
        case .spanish:
            .spanish
        case .chinese:
            .chinese
        case .english, .system:
            .english
        }
    }

    static let russian = AboutStrings(
        versionPrefix: "Версия",
        whatItDoesTitle: "Что делает",
        whatItDoesBody:
            "VPSMonitor — нативное macOS-приложение, которое живёт в menu bar " +
            "и показывает состояние Linux-серверов, проектов и служб в реальном времени. " +
            "Никаких облаков, никакого агента — только SSH, ваши ключи или пароль в Keychain.",
        howItWorksTitle: "Как это работает",
        howItWorksBullets: [
            "Приложение подключается по SSH, используя ключи или пароль.",
            "Отправляет на сервер небольшой bash-скрипт через stdin и сразу получает метрики.",
            "Скрипт читает /proc, df, ps и systemctl — он полностью read-only.",
            "Данные разбираются на стороне Mac и отображаются в дашборде, истории и разборе инцидента.",
            "Страна VPS определяется по IP один раз и может быть переопределена вручную."
        ],
        trackedTitle: "Что отслеживается",
        trackedBullets: [
            "CPU, оперативная память, свободное место, аптайм",
            "Время полного SSH-опроса (отклик сервера)",
            "Проекты в /opt, /var/www, /srv, /app, /home/* и связанные службы",
            "Живые процессы, даже если они запущены без systemd",
            "CPU и RAM по каждой запущенной службе или процессу",
            "Push-уведомления о падении сервера и остановке служб",
            "История метрик, incident snapshot и команды ручной проверки"
        ],
        telegramButton: "Поддержка в Telegram",
        copyright: "© 2025 thealexpm · MIT License"
    )

    static let english = AboutStrings(
        versionPrefix: "Version",
        whatItDoesTitle: "What it does",
        whatItDoesBody:
            "VPSMonitor is a native macOS app that lives in your menu bar " +
            "and shows the live state of Linux servers, projects and services. " +
            "No cloud, no agent — just SSH, your keys or a Keychain-stored password.",
        howItWorksTitle: "How it works",
        howItWorksBullets: [
            "Connects to your server over SSH using a key or password.",
            "Pipes a small bash script via stdin and immediately receives metrics.",
            "The script reads /proc, df, ps and systemctl — it is fully read-only.",
            "Parsing happens on your Mac; results are shown in dashboard, history and incident analysis.",
            "VPS country is resolved by IP once and can be manually overridden."
        ],
        trackedTitle: "What's tracked",
        trackedBullets: [
            "CPU, RAM, free disk space, uptime",
            "SSH round-trip time (server responsiveness)",
            "Projects in /opt, /var/www, /srv, /app, /home/* and linked services",
            "Live processes even when they are not managed by systemd",
            "Per-service and per-process CPU and RAM usage",
            "Push notifications when a server goes down or a service stops",
            "Metric history, incident snapshot and manual check commands"
        ],
        telegramButton: "Telegram support",
        copyright: "© 2025 thealexpm · MIT License"
    )

    static let spanish = AboutStrings(
        versionPrefix: "Versión",
        whatItDoesTitle: "Qué hace",
        whatItDoesBody:
            "VPSMonitor es una app nativa para macOS que vive en la barra de menú " +
            "y muestra el estado de servidores Linux, proyectos y servicios en tiempo real. " +
            "Sin nube ni agente: solo SSH, sus claves o una contraseña guardada en Keychain.",
        howItWorksTitle: "Cómo funciona",
        howItWorksBullets: [
            "Se conecta por SSH usando una clave o contraseña.",
            "Envía un pequeño script bash por stdin y recibe métricas al instante.",
            "El script lee /proc, df, ps y systemctl; es completamente de solo lectura.",
            "El Mac procesa los datos y muestra panel, historial y análisis de incidentes.",
            "El país del VPS se detecta por IP una vez y puede cambiarse manualmente."
        ],
        trackedTitle: "Qué monitoriza",
        trackedBullets: [
            "CPU, RAM, espacio libre, uptime",
            "Tiempo completo de consulta SSH",
            "Proyectos en /opt, /var/www, /srv, /app, /home/* y servicios vinculados",
            "Procesos activos aunque no estén gestionados por systemd",
            "CPU y RAM por servicio o proceso",
            "Notificaciones, historial, snapshot de incidente y comandos de diagnóstico"
        ],
        telegramButton: "Soporte en Telegram",
        copyright: "© 2025 thealexpm · MIT License"
    )

    static let chinese = AboutStrings(
        versionPrefix: "版本",
        whatItDoesTitle: "功能",
        whatItDoesBody:
            "VPSMonitor 是原生 macOS 菜单栏应用，实时显示 Linux 服务器、项目和服务状态。" +
            "无需云端、无需代理，只使用 SSH、您的密钥或存储在 Keychain 中的密码。",
        howItWorksTitle: "工作方式",
        howItWorksBullets: [
            "通过 SSH 使用密钥或密码连接服务器。",
            "通过 stdin 发送小型 bash 脚本，并立即接收指标。",
            "脚本只读地读取 /proc、df、ps 和 systemctl。",
            "数据在 Mac 上解析，并显示在仪表盘、历史和事件分析中。",
            "VPS 国家/地区会通过 IP 解析一次，也可以手动覆盖。"
        ],
        trackedTitle: "监控内容",
        trackedBullets: [
            "CPU、内存、可用磁盘空间、运行时间",
            "完整 SSH 查询耗时",
            "/opt、/var/www、/srv、/app、/home/* 中的项目和关联服务",
            "即使未由 systemd 管理的运行进程",
            "每个服务或进程的 CPU 与内存",
            "通知、指标历史、事件快照和手动检查命令"
        ],
        telegramButton: "Telegram 支持",
        copyright: "© 2025 thealexpm · MIT License"
    )
}

// MARK: - Sub-views

private struct AboutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.tertiary)
            Text(text)
        }
    }
}

private struct LinkButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .tint(color)
    }
}
