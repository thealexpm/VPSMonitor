import AppKit
import Charts
import SwiftUI
import VPSMonitorCore

struct ServerHistoryView: View {
    let configuration: MonitorConfiguration
    let history: [MetricSample]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("История метрик", "Metric history"))
                        .font(.title2.bold())
                    Text("\(ServerPresentation.countryMarker(for: configuration)) \(configuration.name) · \(configuration.host)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("Готово", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.return)
            }

            if history.count < 2 {
                ContentUnavailableView(
                    L10n.text("История пока пустая", "No history yet"),
                    systemImage: "chart.xyaxis.line",
                    description: Text(L10n.text(
                        "После нескольких проверок здесь появятся графики CPU, RAM, диска и ответа VPS.",
                        "After a few checks, charts for CPU, RAM, disk and VPS response will appear here."
                    ))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        HistoryChart(
                            title: "CPU",
                            color: .green,
                            values: history.map { HistoryPoint(timestamp: $0.timestamp, value: $0.cpuPercent) },
                            unit: "%"
                        )
                        HistoryChart(
                            title: "RAM",
                            color: .blue,
                            values: history.map { HistoryPoint(timestamp: $0.timestamp, value: $0.memoryPercent) },
                            unit: "%"
                        )
                        HistoryChart(
                            title: L10n.text("Диск", "Disk"),
                            color: .orange,
                            values: history.map { HistoryPoint(timestamp: $0.timestamp, value: $0.diskUsedPercent) },
                            unit: "%"
                        )
                        HistoryChart(
                            title: L10n.text("Ответ VPS", "VPS response"),
                            color: .teal,
                            values: history.map { HistoryPoint(timestamp: $0.timestamp, value: $0.responseMilliseconds) },
                            unit: "ms"
                        )
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct HistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

private struct HistoryChart: View {
    let title: String
    let color: Color
    let values: [HistoryPoint]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let last = values.last {
                    Text(formatted(last.value))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Chart(values) { point in
                AreaMark(
                    x: .value("time", point.timestamp),
                    y: .value(title, point.value)
                )
                .foregroundStyle(color.opacity(0.12))
                LineMark(
                    x: .value("time", point.timestamp),
                    y: .value(title, point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatted(_ value: Double) -> String {
        unit == "%" ? "\(Int(value.rounded()))%" : "\(Int(value.rounded())) \(unit)"
    }
}
