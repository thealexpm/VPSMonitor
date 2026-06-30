import AppKit
import SwiftUI
import VPSMonitorCore

struct ContentView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showingHistory = false
    private let sidebarWidth: CGFloat = 160

    var body: some View {
        HStack(spacing: 0) {
            ServerSidebarView(store: store)
                .frame(width: sidebarWidth)

            Divider()

            VStack(spacing: 0) {
                if let update = updateChecker.availableUpdate {
                    UpdateBanner(update: update) { updateChecker.dismiss() }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                serverDetail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            AppMenuLocalizer.applyRepeatedly()
        }
        .sheet(item: passwordRequestBinding) { request in
            PasswordRequiredSheet(request: request) { password in
                try store.savePasswordAndRetry(serverID: request.id, password: password)
            } onCancel: {
                store.dismissPasswordRequest()
            }
        }
        .sheet(isPresented: $showingHistory) {
            if let configuration = store.selectedConfiguration {
                ServerHistoryView(configuration: configuration, history: store.selectedMetricHistory)
            }
        }
    }

    private var passwordRequestBinding: Binding<MonitorStore.PasswordRequest?> {
        Binding {
            store.passwordRequest
        } set: { request in
            if request == nil {
                store.dismissPasswordRequest()
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
                        L10n.text("Проверяю VPS", "Checking VPS"),
                        systemImage: "server.rack",
                        description: Text(L10n.text(
                            "Получаю список проектов и показатели сервера по SSH.",
                            "Fetching projects and server metrics over SSH."
                        ))
                    )
                case .failed(let message) where store.selectedSnapshot == nil:
                    ContentUnavailableView(
                        L10n.text("Ошибка", "Error"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                default:
                    if let snapshot = store.selectedSnapshot,
                       let serverID = store.selectedConfiguration?.id {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ResourceGrid(snapshot: snapshot, history: store.selectedMetricHistory)
                                if let investigationReport = selectedInvestigationReport {
                                    InvestigationView(report: investigationReport)
                                }
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
                    NSApp.activate(ignoringOtherApps: true)
                    showingHistory = true
                } label: {
                    Label(L10n.text("История", "History"), systemImage: "chart.xyaxis.line")
                }
                .disabled(store.selectedConfiguration == nil)
            }
            ToolbarItem {
                Button {
                    Task { await store.refreshSelectedServer() }
                } label: {
                    Label(L10n.text("Проверить сейчас", "Check now"), systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    if let configuration = store.selectedConfiguration {
                        Text(ServerPresentation.countryMarker(for: configuration))
                            .font(.largeTitle)
                    }
                    Text(store.selectedConfiguration?.name ?? L10n.text("VPS не настроены", "VPS not configured"))
                        .font(.largeTitle.bold())
                }
                Text(store.selectedConfiguration?.host ?? L10n.text(
                    "Добавьте сервер в настройках",
                    "Add a server in Settings"
                ))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(
                state: store.selectedLoadState,
                hasVisibleStoppedProjects: store.selectedConfiguration.map {
                    store.hasVisibleStoppedProjects(serverID: $0.id)
                } ?? false
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.text("Нет серверов", "No servers"), systemImage: "server.rack")
        } description: {
            Text(L10n.text("Откройте Настройки и добавьте первый VPS.", "Open Settings and add your first VPS."))
        } actions: {
            SettingsLink {
                Label(L10n.text("Открыть настройки", "Open Settings"), systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var isRefreshing: Bool {
        if case .refreshing = store.selectedLoadState { return true }
        return false
    }

    private var selectedInvestigationReport: InvestigationReport? {
        guard let snapshot = store.selectedSnapshot,
              let configuration = store.selectedConfiguration else { return nil }
        return InvestigationService.makeReport(
            snapshot: snapshot,
            history: store.selectedMetricHistory,
            lastHealthySnapshot: store.selectedLastHealthySnapshot,
            host: configuration.host,
            user: configuration.user
        )
    }

    private func discoveryNote(snapshot: ServerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.text("Как формируется список", "How the list is built"), systemImage: "magnifyingglass")
                .font(.headline)
            Text(L10n.text(
                "Приложение сканирует /opt, /var/www, /srv, /app, /home/* и другие директории, связывает их с systemd-службами и живыми процессами по рабочей директории. Сайты под общим nginx могут отображаться как найденный код без отдельной службы.",
                "The app scans /opt, /var/www, /srv, /app, /home/* and other directories, then links them to systemd services and live processes by working directory. Sites behind a shared nginx can appear as code without a dedicated service."
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PasswordRequiredSheet: View {
    let request: MonitorStore.PasswordRequest
    let onSave: (String) throws -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Требуется пароль SSH", "SSH password required"))
                        .font(.title3.bold())
                    Text("\(request.user)@\(request.host)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text(request.message)
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField(L10n.text("Пароль SSH", "SSH password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(L10n.text("Отмена", "Cancel"), role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button(L10n.text("Сохранить и проверить", "Save and check")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func save() {
        do {
            try onSave(password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ServerSidebarView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.configurations) { configuration in
                    Button {
                        store.selectedServerID = configuration.id
                    } label: {
                        ServerSidebarRow(
                            configuration: configuration,
                            statusColor: color(for: configuration.id),
                            isSelected: store.selectedServerID == configuration.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }

    private func color(for id: UUID) -> Color {
        switch store.state(for: id) {
        case .waiting, .refreshing: .secondary
        case .failed: .red
        case .loaded: store.isHealthy(serverID: id) ? .green : .orange
        }
    }
}

private struct ServerSidebarRow: View {
    let configuration: MonitorConfiguration
    let statusColor: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Text(ServerPresentation.countryMarker(for: configuration))
                    .font(.title3)
                    .lineLimit(1)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(configuration.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(configuration.host)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor)
            }
        }
    }
}

private struct StatusBadge: View {
    let state: MonitorStore.LoadState
    let hasVisibleStoppedProjects: Bool

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
        case .waiting: L10n.text("Ожидание проверки", "Waiting for check")
        case .refreshing: L10n.text("Проверяю", "Checking")
        case .failed: L10n.text("Ошибка", "Error")
        case .loaded:
            hasVisibleStoppedProjects
                ? L10n.text("Нужно внимание", "Needs attention")
                : L10n.text("Всё работает", "Everything works")
        }
    }

    private var icon: String {
        switch state {
        case .waiting, .refreshing: "arrow.triangle.2.circlepath"
        case .failed: "xmark.circle.fill"
        case .loaded:
            hasVisibleStoppedProjects
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .waiting, .refreshing: .secondary
        case .failed: .red
        case .loaded:
            hasVisibleStoppedProjects ? .orange : .green
        }
    }
}
