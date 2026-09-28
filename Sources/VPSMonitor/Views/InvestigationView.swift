import AppKit
import SwiftUI
import VPSMonitorCore

struct InvestigationView: View {
    let report: InvestigationReport
    let isAttentionAcknowledged: Bool
    let onAcknowledge: () -> Void

    @State private var didCopy = false
    private let metricColumns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("Разбор инцидента", "Investigate", es: "Investigar", zh: "诊断"))
                        .font(.title2.bold())
                    Text(report.headline)
                        .font(.headline)
                    Text(report.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !report.attentionKeys.isEmpty {
                    Button {
                        onAcknowledge()
                    } label: {
                        Label(
                            isAttentionAcknowledged
                                ? L10n.text("Снова показать", "Show again")
                                : L10n.text("Отметить как изученное", "Mark as reviewed"),
                            systemImage: isAttentionAcknowledged ? "arrow.uturn.backward" : "checkmark"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    copySnapshot()
                } label: {
                    Label(
                        didCopy
                            ? L10n.text("Скопировано", "Copied")
                            : L10n.text("Скопировать отчёт", "Copy report"),
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(headerBackground, in: RoundedRectangle(cornerRadius: 16))

            LazyVGrid(columns: metricColumns, spacing: 12) {
                ForEach(report.metrics) { metric in
                    InvestigationMetricCard(metric: metric)
                }
            }

            if !report.stoppedProjects.isEmpty || !report.newProjects.isEmpty || !report.recoveredProjects.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Что изменилось", "What changed"))
                        .font(.headline)

                    if !report.stoppedProjects.isEmpty {
                        InvestigationRow(
                            title: L10n.text("Остановленные проекты", "Stopped projects"),
                            value: report.stoppedProjects.map(\.name).joined(separator: ", "),
                            color: .orange
                        )
                    }
                    if !report.newProjects.isEmpty {
                        InvestigationRow(
                            title: L10n.text("Новые после стабильного состояния", "New since the stable state"),
                            value: report.newProjects.map(\.name).joined(separator: ", "),
                            color: .blue
                        )
                    }
                    if !report.recoveredProjects.isEmpty {
                        InvestigationRow(
                            title: L10n.text("Восстановились", "Recovered"),
                            value: report.recoveredProjects.map(\.name).joined(separator: ", "),
                            color: .green
                        )
                    }
                }
                .padding(16)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }

            if report.needsManualCheck {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Команды для ручной проверки", "Manual check commands"))
                        .font(.headline)

                    ForEach(report.suggestedCommands, id: \.self) { command in
                        CommandCopyRow(command: command)
                    }
                }
                .padding(16)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var headerBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.orange.opacity(0.18),
                Color.blue.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func copySnapshot() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.shareText, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

private struct CommandCopyRow: View {
    let command: String
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L10n.text("Скопировать команду", "Copy command"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InvestigationMetricCard: View {
    let metric: InvestigationMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(metric.deltaText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: Capsule())
            }

            Text(metric.currentValueText)
                .font(.title3.bold())
                .lineLimit(1)
            Text(L10n.text("Обычно: \(metric.baselineValueText)", "Usual: \(metric.baselineValueText)", es: "Habitual: \(metric.baselineValueText)", zh: "通常：\(metric.baselineValueText)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(metric.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, maxHeight: 128, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.28), lineWidth: 1)
        }
    }

    private var color: Color {
        switch metric.severity {
        case .normal: .green
        case .elevated: .orange
        case .high: .red
        }
    }
}

private struct InvestigationRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.callout)
        }
    }
}
