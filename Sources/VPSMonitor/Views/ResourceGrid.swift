import Charts
import SwiftUI
import VPSMonitorCore

struct ResourceGrid: View {
    let snapshot: ServerSnapshot
    var history: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Сервер сейчас", "Server now"))
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ResourceCard(
                    title: L10n.text("Процессор", "CPU"),
                    value: L10n.text("занято \(snapshot.cpuUsagePercent)%", "\(snapshot.cpuUsagePercent)% used"),
                    detail: snapshot.cpuUsagePercent < 80
                        ? L10n.text("обычная загрузка", "normal load")
                        : L10n.text("высокая загрузка", "high load"),
                    icon: "cpu",
                    color: snapshot.cpuUsagePercent < 80 ? .green : .orange,
                    chartValues: history.map(\.cpuPercent)
                )
                ResourceCard(
                    title: L10n.text("Память", "Memory"),
                    value: L10n.text(
                        "занято \(MonitorFormatters.bytes(snapshot.memoryUsedBytes))",
                        "\(MonitorFormatters.bytes(snapshot.memoryUsedBytes)) used"
                    ),
                    detail: L10n.text(
                        "из \(MonitorFormatters.bytes(snapshot.memoryTotalBytes))",
                        "of \(MonitorFormatters.bytes(snapshot.memoryTotalBytes))"
                    ),
                    icon: "memorychip",
                    color: memoryColor,
                    chartValues: history.map(\.memoryPercent)
                )
                ResourceCard(
                    title: L10n.text("Диск", "Disk"),
                    value: L10n.text(
                        "свободно \(MonitorFormatters.bytes(snapshot.diskFreeBytes))",
                        "\(MonitorFormatters.bytes(snapshot.diskFreeBytes)) free"
                    ),
                    detail: L10n.text(
                        "из \(MonitorFormatters.bytes(snapshot.diskTotalBytes))",
                        "of \(MonitorFormatters.bytes(snapshot.diskTotalBytes))"
                    ),
                    icon: "internaldrive",
                    color: diskColor,
                    chartValues: history.map(\.diskUsedPercent)
                )
                ResourceCard(
                    title: L10n.text("Ответ VPS", "VPS response"),
                    value: MonitorFormatters.milliseconds(snapshot.responseTime),
                    detail: L10n.text("полная SSH-проверка", "full SSH check"),
                    icon: "network",
                    color: .blue
                )
                ResourceCard(
                    title: L10n.text("Без перезагрузки", "Uptime"),
                    value: MonitorFormatters.duration(snapshot.uptimeSeconds),
                    detail: snapshot.hostName,
                    icon: "clock",
                    color: .blue
                )
                ResourceCard(
                    title: L10n.text("Последняя проверка", "Last check"),
                    value: snapshot.checkedAt.formatted(date: .omitted, time: .standard),
                    detail: L10n.text("обновляется автоматически", "updates automatically"),
                    icon: "checkmark.circle",
                    color: .green
                )
            }
        }
    }

    private var memoryColor: Color {
        guard snapshot.memoryTotalBytes > 0 else { return .secondary }
        return Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) < 0.8 ? .green : .orange
    }

    private var diskColor: Color {
        guard snapshot.diskTotalBytes > 0 else { return .secondary }
        return Double(snapshot.diskFreeBytes) / Double(snapshot.diskTotalBytes) > 0.2 ? .green : .orange
    }
}

private struct ResourceCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color
    var chartValues: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(color)

            if chartValues.count > 1 {
                Chart {
                    ForEach(Array(chartValues.enumerated()), id: \.offset) { index, val in
                        AreaMark(
                            x: .value("i", index),
                            y: .value("v", val)
                        )
                        .foregroundStyle(color.opacity(0.15))
                        LineMark(
                            x: .value("i", index),
                            y: .value("v", val)
                        )
                        .foregroundStyle(color.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 28)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
