import AppKit
import SwiftUI

struct AboutView: View {
    // MARK: - Contact links (edit to match your accounts)
    private let telegramURL  = URL(string: "https://t.me/thealexpm")!
    private let githubURL    = URL(string: "https://github.com/thealexpm/VPSMonitor")!

    var body: some View {
        VStack(spacing: 0) {
            // ── Icon + name ──────────────────────────────────────────────
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 80, height: 80)

                Text("VPSMonitor")
                    .font(.system(size: 22, weight: .bold))

                Text("Версия 1.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // ── Description ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 16) {
                AboutSection(title: "Что делает") {
                    Text(
                        "VPSMonitor — нативное macOS-приложение, которое живёт в menu bar " +
                        "и показывает состояние ваших Linux-серверов в реальном времени. " +
                        "Никаких облаков, никакого агента — только SSH и ваши ключи."
                    )
                }

                AboutSection(title: "Как это работает") {
                    VStack(alignment: .leading, spacing: 6) {
                        BulletRow("Приложение подключается по SSH, используя ключи, уже настроенные на Mac.")
                        BulletRow("Отправляет на сервер небольшой bash-скрипт через stdin и сразу же получает метрики.")
                        BulletRow("Скрипт читает /proc, df и systemctl — он полностью read-only, ничего не меняет.")
                        BulletRow("Данные разбираются на стороне Mac и отображаются в дашборде и menu bar.")
                        BulletRow("Всё работает без Интернета — только прямое SSH-соединение с вашим VPS.")
                    }
                }

                AboutSection(title: "Что отслеживается") {
                    VStack(alignment: .leading, spacing: 6) {
                        BulletRow("CPU, оперативная память, свободное место на диске, аптайм")
                        BulletRow("Время полного SSH-опроса (отклик сервера)")
                        BulletRow("Проекты в /opt и связанные с ними systemd-службы")
                        BulletRow("Push-уведомления о падении сервера и остановке служб")
                        BulletRow("История метрик в виде спарклайн-графиков")
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            // ── Support links ────────────────────────────────────────────
            HStack(spacing: 12) {
                LinkButton(
                    label: "Поддержка в Telegram",
                    systemImage: "paperplane.fill",
                    color: .blue,
                    url: telegramURL
                )
                LinkButton(
                    label: "GitHub",
                    systemImage: "chevron.left.slash.chevron.right",
                    color: .primary,
                    url: githubURL
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            // ── Copyright ────────────────────────────────────────────────
            Text("© 2025 thealexpm · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(width: 460)
    }
}

// MARK: - Sub-views

private struct AboutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
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
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .tint(color)
    }
}
