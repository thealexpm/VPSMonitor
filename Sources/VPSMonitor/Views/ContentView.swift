import SwiftUI
import VPSMonitorCore

struct ContentView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        NavigationSplitView {
            ServerSidebarView(store: store)
        } detail: {
            VStack(spacing: 0) {
                if let update = updateChecker.availableUpdate {
                    UpdateBanner(update: update) { updateChecker.dismiss() }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                serverDetail
            }
        }
    }

    @ViewBuilder
    private var serverDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            if store.configurations.isEmpty {
                emptyState
            } else {
                header

                switch store.selectedLoadState {
                case .waiting where store.selectedSnapshot == nil,
                     .refreshing where store.selectedSnapshot == nil:
                    ContentUnavailableView(
                        "Проверяю VPS",
                        systemImage: "server.rack",
                        description: Text("Получаю список проектов и показатели сервера по SSH.")
                    )
                case .failed(let message) where store.selectedSnapshot == nil:
                    ContentUnavailableView(
                        "VPS недоступен",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                default:
                    if let snapshot = store.selectedSnapshot,
                       let serverID = store.selectedConfiguration?.id {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ResourceGrid(snapshot: snapshot, history: store.selectedMetricHistory)
                                ProjectListView(serverID: serverID, store: store)
                                discoveryNote(snapshot: snapshot)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .padding(24)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.refreshSelectedServer() }
                } label: {
                    Label("Проверить сейчас", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.selectedConfiguration?.name ?? "VPS не настроены")
                    .font(.largeTitle.bold())
                Text(store.selectedConfiguration?.host ?? "Добавьте сервер в настройках")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(state: store.selectedLoadState)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет серверов", systemImage: "server.rack")
        } description: {
            Text("Откройте Настройки и добавьте первый VPS.")
        } actions: {
            SettingsLink {
                Label("Открыть настройки", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var isRefreshing: Bool {
        if case .refreshing = store.selectedLoadState { return true }
        return false
    }

    private func discoveryNote(snapshot: ServerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Как формируется список", systemImage: "magnifyingglass")
                .font(.headline)
            Text("Приложение сканирует /opt, /var/www, /srv, /app, /home/* и другие директории, а также все активные systemd-службы. Нажмите «Настроить» чтобы скрыть ненужные пункты.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ServerSidebarView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        List(store.configurations, selection: $store.selectedServerID) { configuration in
            HStack(spacing: 10) {
                Image(systemName: icon(for: configuration.id))
                    .foregroundStyle(color(for: configuration.id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name)
                    Text(configuration.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(configuration.id)
        }
        .listStyle(.sidebar)
        .navigationTitle("Серверы")
    }

    private func icon(for id: UUID) -> String {
        switch store.state(for: id) {
        case .waiting, .refreshing: "arrow.triangle.2.circlepath"
        case .failed: "xmark.circle.fill"
        case .loaded: store.isHealthy(serverID: id) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func color(for id: UUID) -> Color {
        switch store.state(for: id) {
        case .waiting, .refreshing: .secondary
        case .failed: .red
        case .loaded: store.isHealthy(serverID: id) ? .green : .orange
        }
    }
}

private struct StatusBadge: View {
    let state: MonitorStore.LoadState

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch state {
        case .waiting: "Ожидание проверки"
        case .refreshing: "Проверяю"
        case .failed: "Нет подключения"
        case .loaded(let snapshot):
            snapshot.projects.contains(where: { $0.state == .stopped })
                ? "Нужно внимание"
                : "Всё работает"
        }
    }

    private var icon: String {
        switch state {
        case .waiting, .refreshing: "arrow.triangle.2.circlepath"
        case .failed: "xmark.circle.fill"
        case .loaded(let snapshot):
            snapshot.projects.contains(where: { $0.state == .stopped })
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .waiting, .refreshing: .secondary
        case .failed: .red
        case .loaded(let snapshot):
            snapshot.projects.contains(where: { $0.state == .stopped }) ? .orange : .green
        }
    }
}
