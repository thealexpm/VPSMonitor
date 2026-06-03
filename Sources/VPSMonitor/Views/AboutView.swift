import AppKit
import SwiftUI
import VPSMonitorCore

struct AboutView: View {
    private let telegramURL = URL(string: "https://t.me/thealexpm")!
    private let githubURL   = URL(string: "https://github.com/thealexpm/VPSMonitor")!

    private let strings = AboutStrings.current

    var body: some View {
        VStack(spacing: 0) {

            // ── Icon + name ──────────────────────────────────────────────
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 80, height: 80)
                Text("VPSMonitor")
                    .font(.system(size: 22, weight: .bold))
                Text(strings.versionLabel)
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
    let versionLabel: String
    let whatItDoesTitle: String
    let whatItDoesBody: String
    let howItWorksTitle: String
    let howItWorksBullets: [String]
    let trackedTitle: String
    let trackedBullets: [String]
    let telegramButton: String
    let copyright: String

    /// Returns the Russian variant only when the user's preferred language is Russian.
    /// Any other locale (English, Spanish, German, …) falls back to English.
    static var current: AboutStrings {
        L10n.isRussian ? .russian : .english
    }

    static let russian = AboutStrings(
        versionLabel: "Версия 1.0",
        whatItDoesTitle: "Что делает",
        whatItDoesBody:
            "VPSMonitor — нативное macOS-приложение, которое живёт в menu bar " +
            "и показывает состояние ваших Linux-серверов в реальном времени. " +
            "Никаких облаков, никакого агента — только SSH и ваши ключи.",
        howItWorksTitle: "Как это работает",
        howItWorksBullets: [
            "Приложение подключается по SSH, используя ключи или пароль.",
            "Отправляет на сервер небольшой bash-скрипт через stdin и сразу получает метрики.",
            "Скрипт читает /proc, df и systemctl — он полностью read-only.",
            "Данные разбираются на стороне Mac и отображаются в дашборде.",
            "Всё работает без облака — только прямое SSH-соединение с вашим VPS."
        ],
        trackedTitle: "Что отслеживается",
        trackedBullets: [
            "CPU, оперативная память, свободное место, аптайм",
            "Время полного SSH-опроса (отклик сервера)",
            "Проекты в /opt, /var/www, /srv, /app, /home/* и связанные службы",
            "CPU и RAM по каждой запущенной службе",
            "Push-уведомления о падении сервера и остановке служб",
            "История метрик в виде спарклайн-графиков"
        ],
        telegramButton: "Поддержка в Telegram",
        copyright: "© 2025 thealexpm · MIT License"
    )

    static let english = AboutStrings(
        versionLabel: "Version 1.0",
        whatItDoesTitle: "What it does",
        whatItDoesBody:
            "VPSMonitor is a native macOS app that lives in your menu bar " +
            "and shows the live state of your Linux servers. " +
            "No cloud, no agent — just SSH and your own credentials.",
        howItWorksTitle: "How it works",
        howItWorksBullets: [
            "Connects to your server over SSH using a key or password.",
            "Pipes a small bash script via stdin and immediately receives metrics.",
            "The script reads /proc, df and systemctl — it is fully read-only.",
            "Parsing happens on your Mac; results are shown in the dashboard.",
            "Runs without the cloud — just a direct SSH connection to your VPS."
        ],
        trackedTitle: "What's tracked",
        trackedBullets: [
            "CPU, RAM, free disk space, uptime",
            "SSH round-trip time (server responsiveness)",
            "Projects in /opt, /var/www, /srv, /app, /home/* and linked services",
            "Per-service CPU and RAM usage",
            "Push notifications when a server goes down or a service stops",
            "Metric history as sparkline charts"
        ],
        telegramButton: "Telegram support",
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
