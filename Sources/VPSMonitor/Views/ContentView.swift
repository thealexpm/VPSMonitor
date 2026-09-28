import AppKit
import SwiftUI
import VPSMonitorCore

struct ContentView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showingHistory = false
    @State private var showingVPNDetails = false
    @State private var showingDomainRouting = false
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
        .sheet(isPresented: $showingVPNDetails) {
            if let configuration = store.selectedConfiguration,
               let vpn = store.selectedSnapshot?.vpn {
                VPNDetailsSheet(configuration: configuration, vpn: vpn)
            }
        }
        .sheet(isPresented: $showingDomainRouting) {
            if let configuration = store.selectedConfiguration,
               let domainRouting = store.selectedSnapshot?.domainRouting {
                DomainRoutingSheet(
                    configuration: configuration,
                    snapshot: domainRouting
                ) { domains in
                    try await store.applyDomainWhitelist(serverID: configuration.id, domains: domains)
                }
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
                    loadingState
                case .failed(let message) where store.selectedSnapshot == nil:
                    connectionErrorState(message: message)
                default:
                    if let snapshot = store.selectedSnapshot,
                       let serverID = store.selectedConfiguration?.id {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ResourceGrid(snapshot: snapshot, history: store.selectedMetricHistory)
                                if let vpn = snapshot.vpn {
                                    VPNStatusView(vpn: vpn) {
                                        showingVPNDetails = true
                                    }
                                }
                                if let domainRouting = snapshot.domainRouting {
                                    DomainRoutingStatusView(snapshot: domainRouting) {
                                        showingDomainRouting = true
                                    }
                                }
                                if let investigationReport = selectedInvestigationReport {
                                    InvestigationView(
                                        report: investigationReport,
                                        isAttentionAcknowledged: store.areAttentionKeysAcknowledged(
                                            serverID: serverID,
                                            keys: investigationReport.attentionKeys
                                        ),
                                        onAcknowledge: {
                                            let keys = investigationReport.attentionKeys
                                            guard !keys.isEmpty else { return }
                                            if store.areAttentionKeysAcknowledged(serverID: serverID, keys: keys) {
                                                store.clearAttentionAcknowledgement(serverID: serverID, keys: keys)
                                            } else {
                                                store.acknowledgeAttention(serverID: serverID, keys: keys)
                                            }
                                        }
                                    )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        HStack(alignment: .center, spacing: 16) {
            if let configuration = store.selectedConfiguration {
                Text(ServerPresentation.countryMarker(for: configuration))
                    .font(.system(size: 34))

                VStack(alignment: .leading, spacing: 3) {
                    Text(configuration.name)
                        .font(.title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(configuration.host)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(L10n.text("VPS не настроены", "VPS not configured"))
                    .font(.title.bold())
            }

            Spacer()

            StatusBadge(
                state: store.selectedLoadState,
                needsAttention: selectedInvestigationReport?.attentionKeys.isEmpty == false,
                isAcknowledged: selectedAttentionAcknowledged
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    ProgressView()
                        .controlSize(.regular)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Проверяю VPS", "Checking VPS"))
                        .font(.title2.bold())
                    Text(L10n.text(
                        "Получаю список проектов и показатели сервера по SSH.",
                        "Fetching projects and server metrics over SSH."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }

            Divider()

            Label(
                L10n.text("Первый ответ может занять несколько секунд.", "The first response may take a few seconds."),
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func connectionErrorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                L10n.text("Не удалось подключиться", "Could not connect"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
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

    private var selectedAttentionAcknowledged: Bool {
        guard let serverID = store.selectedConfiguration?.id,
              let keys = selectedInvestigationReport?.attentionKeys else { return false }
        return store.areAttentionKeysAcknowledged(serverID: serverID, keys: keys)
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
    let needsAttention: Bool
    let isAcknowledged: Bool

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
            if isAcknowledged {
                L10n.text("Изучено", "Reviewed")
            } else {
                needsAttention
                    ? L10n.text("Нужно внимание", "Needs attention")
                    : L10n.text("Всё работает", "Everything works")
            }
        }
    }

    private var icon: String {
        switch state {
        case .waiting, .refreshing: "arrow.triangle.2.circlepath"
        case .failed: "xmark.circle.fill"
        case .loaded:
            isAcknowledged || !needsAttention
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .waiting, .refreshing: .secondary
        case .failed: .red
        case .loaded:
            isAcknowledged ? .secondary : (needsAttention ? .orange : .green)
        }
    }
}

private struct DomainRoutingStatusView: View {
    let snapshot: DomainRoutingSnapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(L10n.text("Маршрутизация доменов", "Domain routing"), systemImage: "arrow.triangle.branch")
                        .font(.title2.bold())
                    Spacer()
                    Label(statusTitle, systemImage: snapshot.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(snapshot.isHealthy ? .green : .orange)
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 18) {
                    metric(L10n.text("Whitelist", "Whitelist"), "\(snapshot.whitelistDomains.count)")
                    metric(L10n.text("Кандидаты", "Candidates"), "\(snapshot.candidateDomains.count)")
                    metric(L10n.text("IP в маршруте", "Routed IPs"), "\(snapshot.routedIPCount)")
                    metric(L10n.text("DNS", "DNS"), snapshot.dnsServiceState)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke((snapshot.isHealthy ? Color.green : Color.orange).opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusTitle: String {
        snapshot.isHealthy
            ? L10n.text("Готово", "Ready")
            : L10n.text("Нужно внимание", "Needs attention")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
    }
}

private struct DomainRoutingSheet: View {
    let configuration: MonitorConfiguration
    let snapshot: DomainRoutingSnapshot
    let onApply: ([String]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var whitelistText: String
    @State private var ignoredCandidateDomains: Set<String>
    @State private var isApplying = false
    @State private var errorMessage: String?

    init(
        configuration: MonitorConfiguration,
        snapshot: DomainRoutingSnapshot,
        onApply: @escaping ([String]) async throws -> Void
    ) {
        self.configuration = configuration
        self.snapshot = snapshot
        self.onApply = onApply
        _whitelistText = State(initialValue: snapshot.whitelistDomains.joined(separator: "\n"))
        _ignoredCandidateDomains = State(initialValue: Self.loadIgnoredCandidateDomains())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.text("Маршрутизация доменов", "Domain routing"), systemImage: "arrow.triangle.branch")
                    .font(.title2.bold())
                Spacer()
                Text(configuration.host)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help(L10n.text("Закрыть", "Close"))
                .accessibilityLabel(L10n.text("Закрыть", "Close"))
            }

            HStack(spacing: 18) {
                detailMetric(L10n.text("DNS-служба", "DNS service"), snapshot.dnsServiceState)
                detailMetric(L10n.text("Маршрут", "Route"), snapshot.routeServiceState)
                detailMetric(L10n.text("IP в ipset", "IPs in ipset"), "\(snapshot.routedIPCount)")
                detailMetric(L10n.text("Файл", "File"), snapshot.configPath)
            }

            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Whitelist", "Whitelist"))
                        .font(.headline)
                    TextEditor(text: $whitelistText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 320, idealWidth: 380, minHeight: 320)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        }
                    HStack {
                        Button {
                            compactWhitelist()
                        } label: {
                            Label(L10n.text("Укрупнить", "Compact"), systemImage: "arrow.triangle.merge")
                        }
                        .buttonStyle(.bordered)
                        .help(L10n.text(
                            "Свернуть поддомены до основного домена сервиса",
                            "Collapse subdomains to the service root domain"
                        ))
                        Spacer()
                        Text(L10n.text(
                            "\(currentDomains().count) доменов",
                            "\(currentDomains().count) domains"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text(L10n.text(
                        "Один домен на строку, без https:// и путей. Пример: yandex.ru",
                        "One domain per line, without https:// or paths. Example: yandex.ru"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.text("Кандидаты из DNS-истории", "Candidates from DNS history"))
                            .font(.headline)
                        Spacer()
                        Text("\(visibleCandidates.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if visibleCandidates.isEmpty {
                        ContentUnavailableView(
                            L10n.text("Кандидатов пока нет", "No candidates yet"),
                            systemImage: "list.bullet.rectangle",
                            description: Text(L10n.text(
                                "Когда VPN-клиенты начнут открывать сайты через DNS этого сервера, здесь появятся домены для ручного отбора.",
                                "When VPN clients start resolving sites through this server DNS, domains will appear here for manual review."
                            ))
                        )
                        .frame(minWidth: 360, minHeight: 320)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(visibleCandidates) { candidate in
                                    DomainCandidateRow(candidate: candidate) {
                                        addCandidate(candidate.domain)
                                    } onIgnore: {
                                        ignoreCandidate(candidate.domain)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: 360, idealWidth: 460, minHeight: 320)
                    }

                    if !ignoredCandidateDomains.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L10n.text(
                                    "Не предлагать: \(ignoredCandidateDomains.count)",
                                    "Do not suggest: \(ignoredCandidateDomains.count)"
                                ))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                Spacer()
                                Button(L10n.text("Очистить", "Clear")) {
                                    clearIgnoredCandidates()
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                            }

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(ignoredCandidateDomains).sorted(), id: \.self) { domain in
                                        IgnoredDomainRow(domain: domain) {
                                            restoreCandidate(domain)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 110)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.leading, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Text(L10n.text(
                    "Автосписок показывает домены, которые запрашивали VPN-клиенты. Решение добавить в whitelist остаётся ручным.",
                    "The auto list shows domains requested by VPN clients. Adding them to the whitelist remains manual."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Применить", "Apply")) {
                    apply()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 980, minHeight: 620, idealHeight: 700)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var visibleCandidates: [DomainRouteCandidate] {
        let whitelisted = Set(currentDomains())
        let grouped = Dictionary(grouping: snapshot.candidateDomains) { candidate in
            Self.compactDomain(candidate.domain)
        }
        return grouped.values.compactMap { candidates in
            guard let first = candidates.first else { return nil }
            let domain = Self.compactDomain(first.domain)
            guard !whitelisted.contains(domain) else { return nil }
            guard !ignoredCandidateDomains.contains(domain) else { return nil }
            let queryCount = candidates.reduce(0) { $0 + $1.queryCount }
            let lastSeen = candidates.max {
                Self.lastSeenSortKey($0.lastSeen) < Self.lastSeenSortKey($1.lastSeen)
            }?.lastSeen ?? first.lastSeen
            return DomainRouteCandidate(domain: domain, queryCount: queryCount, lastSeen: lastSeen)
        }
        .sorted {
            let leftDate = Self.lastSeenSortKey($0.lastSeen)
            let rightDate = Self.lastSeenSortKey($1.lastSeen)
            if leftDate != rightDate { return leftDate > rightDate }
            if $0.queryCount == $1.queryCount { return $0.domain < $1.domain }
            return $0.queryCount > $1.queryCount
        }
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addCandidate(_ domain: String) {
        var domains = currentDomains()
        let compacted = Self.compactDomain(domain)
        guard !domains.contains(compacted) else { return }
        domains.append(compacted)
        whitelistText = domains.sorted().joined(separator: "\n")
    }

    private func ignoreCandidate(_ domain: String) {
        let compacted = Self.compactDomain(domain)
        ignoredCandidateDomains.insert(compacted)
        Self.saveIgnoredCandidateDomains(ignoredCandidateDomains)
    }

    private func restoreCandidate(_ domain: String) {
        ignoredCandidateDomains.remove(Self.compactDomain(domain))
        Self.saveIgnoredCandidateDomains(ignoredCandidateDomains)
    }

    private func clearIgnoredCandidates() {
        ignoredCandidateDomains.removeAll()
        Self.saveIgnoredCandidateDomains(ignoredCandidateDomains)
    }

    private func compactWhitelist() {
        whitelistText = Self.compactDomains(currentDomains()).joined(separator: "\n")
    }

    private func currentDomains() -> [String] {
        whitelistText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func compactDomains(_ domains: [String]) -> [String] {
        Array(Set(domains.map(compactDomain))).sorted()
    }

    private static func compactDomain(_ domain: String) -> String {
        let normalized = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = normalized.split(separator: ".").map(String.init)
        guard labels.count >= 3 else { return normalized }

        let publicSuffixesWithTwoLabels: Set<String> = [
            "com.au", "com.br", "com.cn", "com.tr", "co.jp", "co.kr",
            "co.uk", "com.ua", "net.ua", "org.ua"
        ]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if publicSuffixesWithTwoLabels.contains(lastTwo), labels.count >= 3 {
            return labels.suffix(3).joined(separator: ".")
        }

        return labels.suffix(2).joined(separator: ".")
    }

    private static func lastSeenSortKey(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy"
        let year = Calendar.current.component(.year, from: Date())
        return formatter.date(from: "\(value) \(year)") ?? .distantPast
    }

    private static let ignoredCandidateDomainsKey = "domainRouting.ignoredCandidateDomains"

    private static func loadIgnoredCandidateDomains() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ignoredCandidateDomainsKey) ?? [])
    }

    private static func saveIgnoredCandidateDomains(_ domains: Set<String>) {
        UserDefaults.standard.set(Array(domains).sorted(), forKey: ignoredCandidateDomainsKey)
    }

    private func apply() {
        isApplying = true
        errorMessage = nil
        let domains = currentDomains()
        Task {
            do {
                try await onApply(domains)
                await MainActor.run {
                    isApplying = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isApplying = false
                }
            }
        }
    }
}

private struct DomainCandidateRow: View {
    let candidate: DomainRouteCandidate
    let onAdd: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.domain)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(metadata.title, systemImage: metadata.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(L10n.text(
                    "\(candidate.queryCount) DNS-запросов • последнее: \(candidate.lastSeen)",
                    "\(candidate.queryCount) DNS queries • last: \(candidate.lastSeen)"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onIgnore()
            } label: {
                Image(systemName: "eye.slash")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.text("Больше не предлагать", "Do not suggest again"))
            .accessibilityLabel(L10n.text("Больше не предлагать", "Do not suggest again"))
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(L10n.text("Добавить в whitelist", "Add to whitelist"))
            .accessibilityLabel(L10n.text("Добавить в whitelist", "Add to whitelist"))
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metadata: DomainRouteMetadata {
        DomainRouteClassifier.metadata(for: candidate.domain)
    }
}

private struct IgnoredDomainRow: View {
    let domain: String
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(domain)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(DomainRouteClassifier.metadata(for: domain).title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button {
                onRestore()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help(L10n.text("Вернуть в кандидаты", "Restore to candidates"))
            .accessibilityLabel(L10n.text("Вернуть в кандидаты", "Restore to candidates"))
        }
        .padding(.vertical, 2)
    }
}

private struct DomainRouteMetadata {
    let title: String
    let systemImage: String
}

private enum DomainRouteClassifier {
    static func metadata(for domain: String) -> DomainRouteMetadata {
        let value = domain.lowercased()
        let rules: [(suffix: String, title: String, image: String)] = [
            ("avito.ru", "Avito / объявления", "bag"),
            ("avito.st", "Avito / изображения и CDN", "photo"),
            ("avito.cdnvideo.ru", "Avito / видео CDN", "play.rectangle"),
            ("vk.com", "VK / соцсеть, сообщения, API", "message"),
            ("vk.ru", "VK / соцсеть, сообщения, API", "message"),
            ("vk-portal.net", "VK / служебный CDN", "network"),
            ("oneme.ru", "VK OneMe / мессенджер", "message"),
            ("wildberries.ru", "Wildberries / маркетплейс", "cart"),
            ("wb.ru", "Wildberries / короткий домен", "cart"),
            ("wbcontent.net", "Wildberries / контент CDN", "photo"),
            ("paywb.com", "Wildberries / платежи", "creditcard"),
            ("t-bank-app.ru", "T-Bank / мобильное приложение", "creditcard"),
            ("tinkoff.ru", "T-Bank / банк и инвестиции", "creditcard"),
            ("tinkoffinsurance.ru", "T-Bank / страхование", "cross.case"),
            ("ozon.ru", "Ozon / маркетплейс", "cart"),
            ("ok.ru", "Одноклассники / соцсеть", "person.2"),
            ("okcdn.ru", "Одноклассники / CDN", "network"),
            ("yandex.ru", "Яндекс / сервисы", "magnifyingglass"),
            ("yandex.net", "Яндекс / API, CDN, AppMetrica", "network"),
            ("ya.ru", "Яндекс / поиск", "magnifyingglass"),
            ("mail.ru", "VK / Mail.ru сервисы и реклама", "envelope"),
            ("targethunter.ru", "TargetHunter / VK-инструменты", "scope"),
            ("google.com", "Google / аккаунты и сервисы", "g.circle"),
            ("googleapis.com", "Google / API", "network"),
            ("gstatic.com", "Google / статические ресурсы", "photo"),
            ("gvt2.com", "Google / служебная доставка", "network"),
            ("apple.com", "Apple / сервисы", "apple.logo"),
            ("apple-dns.net", "Apple / DNS и iCloud", "network"),
            ("icloud.com", "Apple / iCloud", "icloud"),
            ("anthropic.com", "Anthropic / Claude", "sparkles"),
            ("claude.ai", "Anthropic / Claude", "sparkles"),
            ("claudemcpcontent.com", "Anthropic / Claude MCP content", "sparkles"),
            ("chatgpt.com", "OpenAI / ChatGPT", "sparkles"),
            ("openai.com", "OpenAI / API и ChatGPT", "sparkles"),
            ("github.com", "GitHub / разработка", "chevron.left.forwardslash.chevron.right"),
            ("akamai.net", "Akamai / CDN", "network"),
            ("cloudflare.com", "Cloudflare / CDN", "network"),
            ("cloudfront.net", "AWS CloudFront / CDN", "network")
        ]

        if let match = rules.first(where: { value == $0.suffix || value.hasSuffix("." + $0.suffix) }) {
            return DomainRouteMetadata(title: match.title, systemImage: match.image)
        }
        return DomainRouteMetadata(
            title: L10n.text("Неизвестный сервис / проверь вручную", "Unknown service / review manually"),
            systemImage: "questionmark.circle"
        )
    }
}

private struct VPNStatusView: View {
    let vpn: VPNSnapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(L10n.text("VPN", "VPN"), systemImage: "lock.shield")
                        .font(.title2.bold())
                    Spacer()
                    Label(summaryTitle, systemImage: vpn.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(vpn.isHealthy ? .green : .orange)
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(vpn.stacks) { status in
                    VPNStackRow(status: status)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke((vpn.isHealthy ? Color.green : Color.orange).opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryTitle: String {
        if vpn.totalActiveConnections > 0 {
            return L10n.text(
                "\(vpn.totalActiveConnections) активных подключений",
                "\(vpn.totalActiveConnections) active connections"
            )
        }
        return vpn.isHealthy
            ? L10n.text("Службы работают", "Services running")
            : L10n.text("Нужно внимание", "Needs attention")
    }
}

private struct VPNStackRow: View {
    let status: VPNStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.isHealthy ? "lock.circle.fill" : "lock.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(status.isHealthy ? .green : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(status.stack)
                        .font(.headline)
                    Text(status.serviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 14) {
                    metric(
                        title: L10n.text("Статус", "Status"),
                        value: status.isHealthy
                            ? L10n.text("Работает", "Running")
                            : L10n.text("Нужно внимание", "Needs attention")
                    )
                    metric(
                        title: L10n.text("Клиенты", "Clients"),
                        value: "\(status.activeConnections)"
                    )
                    metric(
                        title: L10n.text("UDP-порты", "UDP ports"),
                        value: status.listeningPorts.isEmpty ? "n/a" : status.listeningPorts.joined(separator: ", ")
                    )
                }

                if !status.details.isEmpty {
                    Text(status.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
    }
}

private struct VPNDetailsSheet: View {
    let configuration: MonitorConfiguration
    let vpn: VPNSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var showingProvisioning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(L10n.text("VPN-подключения", "VPN connections"), systemImage: "lock.shield")
                    .font(.title2.bold())
                Spacer()
                Text(summary)
                    .font(.headline)
                    .foregroundStyle(vpn.isHealthy ? .green : .orange)
                Button {
                    showingProvisioning = true
                } label: {
                    Label(L10n.text("Apple-профиль", "Apple profile"), systemImage: "person.badge.key")
                }
                .buttonStyle(.bordered)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help(L10n.text("Закрыть", "Close"))
                .accessibilityLabel(L10n.text("Закрыть", "Close"))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(vpn.stacks) { status in
                        VPNStackDetails(status: status)
                    }

                    explanation
                }
                .padding(.bottom, 4)
            }
        }
        .padding(24)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showingProvisioning) {
            VPNProvisioningSheet(configuration: configuration)
        }
    }

    private var summary: String {
        L10n.text(
            "\(vpn.totalActiveConnections) активных",
            "\(vpn.totalActiveConnections) active"
        )
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Расшифровка", "Legend"))
                .font(.headline)
            Text(L10n.text(
                "Входящий и исходящий трафик показан с точки зрения VPN-сервера за текущую сессию. Мгновенная скорость требует сравнения двух соседних проверок; сейчас поле активности показывает, сколько секунд назад был последний пакет. Название устройства strongSwan обычно не передаёт, поэтому здесь отображается EAP identity и внутренний VPN-IP.",
                "Inbound and outbound traffic is shown from the VPN server perspective for the current session. Live speed requires comparing two adjacent checks; for now activity shows how many seconds ago the last packet was seen. strongSwan usually does not receive a device name, so the sheet shows EAP identity and internal VPN IP."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct VPNProvisioningSheet: View {
    let configuration: MonitorConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = VPNProvisioningService.generatedPassword()
    @State private var profileName = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?

    private let service = VPNProvisioningService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(L10n.text("Создать Apple VPN-профиль", "Create Apple VPN profile"), systemImage: "person.badge.key")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                provisioningField(
                    L10n.text("Пользователь", "Username"),
                    text: $username,
                    placeholder: "alex-macbook"
                )
                provisioningField(
                    L10n.text("Название профиля", "Profile name"),
                    text: $profileName,
                    placeholder: "\(configuration.name) VPN"
                )

                HStack {
                    Text(L10n.text("Пароль", "Password"))
                        .frame(width: 150, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Group {
                        if showsPassword {
                            TextField(L10n.text("Пароль VPN", "VPN password"), text: $password)
                        } else {
                            SecureField(L10n.text("Пароль VPN", "VPN password"), text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button {
                        copyPassword()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("Скопировать пароль", "Copy password"))
                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showsPassword ? L10n.text("Скрыть пароль", "Hide password") : L10n.text("Показать пароль", "Show password"))
                    Button {
                        password = VPNProvisioningService.generatedPassword()
                        message = L10n.text("Пароль сгенерирован.", "Password generated.")
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("Сгенерировать новый пароль", "Generate a new password"))
                }

                Text(L10n.text(
                    "Профиль добавит пользователя на strongSwan-сервер и сохранит .mobileconfig для установки на iPhone, iPad или Mac. В списке подключений сервер будет видеть имя пользователя из этого профиля, поэтому называйте его по устройству.",
                    "The profile adds a user to the strongSwan server and saves a .mobileconfig for iPhone, iPad, or Mac. The server will show the username from this profile in the connections list, so name it after the device."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 158)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(L10n.text("Отменить", "Cancel")) {
                    dismiss()
                }
                .disabled(isWorking)
                Spacer()
                Button {
                    createProfile()
                } label: {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.text("Создать и сохранить", "Create and save"), systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isWorking)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            if username.isEmpty {
                username = "\(configuration.name)-mac"
                    .lowercased()
                    .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
            }
            if profileName.isEmpty {
                profileName = "\(configuration.name) VPN"
            }
        }
    }

    private var canCreate: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12
    }

    private func createProfile() {
        errorMessage = nil
        message = nil
        isWorking = true

        Task {
            do {
                let result = try await service.createAppleProfile(
                    configuration: configuration,
                    username: username,
                    password: password,
                    profileName: profileName
                )
                let savedURL = try await MainActor.run {
                    try save(profile: result.profileData, username: result.username)
                }
                await MainActor.run {
                    message = L10n.text(
                        "Профиль сохранён: \(savedURL.lastPathComponent)",
                        "Profile saved: \(savedURL.lastPathComponent)"
                    )
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }

    private func copyPassword() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(password, forType: .string)
        message = L10n.text("Пароль скопирован.", "Password copied.")
    }

    @MainActor
    private func save(profile data: Data, username: String) throws -> URL {
        let panel = NSSavePanel()
        panel.title = L10n.text("Сохранить Apple VPN-профиль", "Save Apple VPN profile")
        panel.nameFieldStringValue = "\(safeFileComponent(username)).mobileconfig"
        panel.allowedContentTypes = [.init(filenameExtension: "mobileconfig")!]
        panel.canCreateDirectories = true
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func provisioningField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 150, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func safeFileComponent(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        return cleaned.isEmpty ? "vpn-profile" : cleaned
    }
}

private struct VPNStackDetails: View {
    let status: VPNStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.stack)
                        .font(.headline)
                    Text(status.serviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(status.isHealthy ? L10n.text("Работает", "Running") : L10n.text("Нужно внимание", "Needs attention"),
                      systemImage: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.isHealthy ? .green : .orange)
            }

            HStack(spacing: 18) {
                detailMetric(L10n.text("Клиенты", "Clients"), "\(status.activeConnections)")
                detailMetric(L10n.text("UDP-порты", "UDP ports"), status.listeningPorts.isEmpty ? "n/a" : status.listeningPorts.joined(separator: ", "))
                detailMetric(L10n.text("Systemd", "Systemd"), "\(status.activeState)/\(status.subState)")
            }

            if status.clients.isEmpty {
                Text(L10n.text("Активных клиентов сейчас нет.", "No active clients right now."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(status.clients) { client in
                        VPNClientRow(client: client)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
    }
}

private struct VPNClientRow: View {
    let client: VPNClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(client.identity.isEmpty ? L10n.text("Неизвестный клиент", "Unknown client") : client.identity)
                    .font(.headline)
                Text(client.connectionID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(client.protocolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], alignment: .leading, spacing: 10) {
                item(L10n.text("Публичный IP", "Public IP"), publicIPTitle)
                item(L10n.text("VPN-IP", "VPN IP"), client.virtualIP.isEmpty ? "n/a" : client.virtualIP)
                item(L10n.text("Подключён", "Connected"), client.connectedFor.isEmpty ? "n/a" : client.connectedFor)
                item(L10n.text("Активность", "Activity"), activityTitle)
                item(L10n.text("Получено", "Received"), MonitorFormatters.bytes(client.bytesIn))
                item(L10n.text("Отправлено", "Sent"), MonitorFormatters.bytes(client.bytesOut))
                item(L10n.text("Пакеты in/out", "Packets in/out"), "\(client.packetsIn)/\(client.packetsOut)")
            }

            if !client.proposal.isEmpty {
                Text(client.proposal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var publicIPTitle: String {
        let flag = client.countryCode.flatMap(ServerPresentation.flagEmoji(for:)) ?? "🌐"
        return client.publicIP.isEmpty ? "n/a" : "\(flag) \(client.publicIP)"
    }

    private var activityTitle: String {
        guard let seconds = client.lastActivitySeconds else { return "n/a" }
        return L10n.text("\(seconds) сек. назад", "\(seconds)s ago")
    }

    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
