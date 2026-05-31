import AppKit
import SwiftUI
import VPSMonitorCore

struct MonitorMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: MonitorStore

    var body: some View {
        Text(store.menuTitle)
            .foregroundStyle(.secondary)

        Divider()

        ForEach(store.configurations) { configuration in
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(configuration.name)
                    if let snapshot = store.snapshot(for: configuration.id) {
                        Text("\(configuration.host) · \(MonitorFormatters.milliseconds(snapshot.responseTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(configuration.host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: statusIcon(for: configuration.id))
                    .foregroundStyle(statusColor(for: configuration.id))
            }
        }

        Divider()

        Button("Открыть монитор") {
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Проверить сейчас") {
            store.refreshAll()
        }

        Divider()

        SettingsLink {
            Text("Настройки")
        }
        Button("О программе") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Завершить работу") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func statusIcon(for id: UUID) -> String {
        switch store.state(for: id) {
        case .waiting, .refreshing: return "arrow.triangle.2.circlepath"
        case .failed: return "xmark.circle.fill"
        case .loaded: return store.isHealthy(serverID: id) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for id: UUID) -> Color {
        switch store.state(for: id) {
        case .waiting, .refreshing: return .secondary
        case .failed: return .red
        case .loaded: return store.isHealthy(serverID: id) ? .green : .orange
        }
    }
}
