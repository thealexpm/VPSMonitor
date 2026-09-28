import Combine
import Foundation

@MainActor
public final class MonitorStore: ObservableObject {
    public enum LoadState: Sendable {
        case waiting
        case refreshing
        case loaded(ServerSnapshot)
        case failed(String)
    }

    public struct PasswordRequest: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let serverName: String
        public let host: String
        public let user: String
        public let message: String
    }

    @Published public var configurations: [MonitorConfiguration] {
        didSet {
            saveConfigurations()
            normalizeSelection()
            reconcilePollingTasks()
        }
    }
    @Published public var selectedServerID: UUID? {
        didSet { saveSelectedServerID() }
    }
    @Published public private(set) var loadStates: [UUID: LoadState] = [:]
    @Published public private(set) var snapshots: [UUID: ServerSnapshot] = [:]
    @Published public private(set) var lastHealthySnapshots: [UUID: ServerSnapshot] = [:]
    @Published public private(set) var metricHistory: [UUID: [MetricSample]] = [:]
    @Published public private(set) var passwordRequest: PasswordRequest?
    /// Project IDs the user chose to hide, per server. Persisted.
    @Published public private(set) var hiddenProjectIDs: [UUID: Set<String>] = [:]
    /// Project IDs that appeared since the previous poll, per server. Session-only.
    @Published public private(set) var newProjectIDs: [UUID: Set<String>] = [:]
    /// Individual actionable problems acknowledged by the user, per server.
    /// Problems are pruned when they disappear, so a reappearing issue requests
    /// attention again.
    @Published public private(set) var acknowledgedAttention: [UUID: Set<String>] = [:]

    private let inventoryService: SSHInventoryService
    private let domainRoutingService: DomainRoutingService
    private let geolocationService: IPGeolocationService
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var pollingStarted = false
    private static let maxStoredSamplesPerServer = 20_160

    public init(
        inventoryService: SSHInventoryService = SSHInventoryService(),
        domainRoutingService: DomainRoutingService = DomainRoutingService(),
        geolocationService: IPGeolocationService = IPGeolocationService()
    ) {
        self.inventoryService = inventoryService
        self.domainRoutingService = domainRoutingService
        self.geolocationService = geolocationService
        let defaults = UserDefaults.standard
        if DemoData.isEnabled {
            // Demo mode: fictional servers, no SSH calls — used for screenshots
            self.configurations = DemoData.configurations
            self.selectedServerID = DemoData.productionServerID
            self.hiddenProjectIDs = [:]
            for cfg in DemoData.configurations {
                let snap = DemoData.snapshot(for: cfg.id)
                self.snapshots[cfg.id] = snap
                self.lastHealthySnapshots[cfg.id] = snap
                self.loadStates[cfg.id] = .loaded(snap)
                self.metricHistory[cfg.id] = Self.demoHistory(for: snap)
            }
        } else {
            let loadedConfigurations = Self.loadConfigurations(from: defaults).map(Self.configurationWithLocalCountry)
            let shouldMigratePollingInterval = !defaults.bool(forKey: "monitor.didMigratePollingIntervalTo60")
            self.configurations = loadedConfigurations.map { configuration in
                guard shouldMigratePollingInterval, configuration.refreshInterval < 60 else {
                    return configuration
                }
                var migrated = configuration
                migrated.refreshInterval = 60
                return migrated
            }
            if shouldMigratePollingInterval {
                if let data = try? JSONEncoder().encode(self.configurations) {
                    defaults.set(data, forKey: "monitor.configurations")
                }
                defaults.set(true, forKey: "monitor.didMigratePollingIntervalTo60")
            }
            self.selectedServerID = defaults.string(forKey: "monitor.selectedServerID").flatMap(UUID.init)
            self.hiddenProjectIDs = Self.loadHiddenProjectIDs(from: defaults)
            self.acknowledgedAttention = Self.loadAcknowledgedAttention(from: defaults)
            self.metricHistory = Self.loadMetricHistory()
            normalizeSelection()
            if defaults.data(forKey: "monitor.configurations") == nil, !configurations.isEmpty {
                saveConfigurations()
                saveSelectedServerID()
            }
            for configuration in configurations where configuration.countryCodeOverride == nil {
                scheduleCountryResolution(for: configuration.id)
            }
        }
    }

    private static func demoHistory(for snapshot: ServerSnapshot) -> [MetricSample] {
        // Build a 25-point history that ends at the current snapshot
        let base = Double(snapshot.cpuUsagePercent)
        let memBase = snapshot.memoryTotalBytes > 0
            ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100 : 0
        let diskBase = snapshot.diskTotalBytes > 0
            ? (1.0 - Double(snapshot.diskFreeBytes) / Double(snapshot.diskTotalBytes)) * 100 : 0
        return (0..<25).map { i -> MetricSample in
            let jitter = Double((i * 7) % 11 - 5) * 0.6
            return MetricSample(
                timestamp: Date().addingTimeInterval(Double(-30 * (25 - i))),
                cpuPercent: max(0, base + jitter * 1.5),
                memoryPercent: max(0, memBase + jitter * 0.4),
                diskUsedPercent: max(0, diskBase + jitter * 0.05),
                responseMilliseconds: max(50, 180 + jitter * 10)
            )
        }
    }

    public var selectedConfiguration: MonitorConfiguration? {
        configurations.first { $0.id == selectedServerID } ?? configurations.first
    }

    public var selectedLoadState: LoadState {
        guard let id = selectedConfiguration?.id else { return .waiting }
        return loadStates[id] ?? .waiting
    }

    public var selectedSnapshot: ServerSnapshot? {
        guard let id = selectedConfiguration?.id else { return nil }
        return snapshots[id]
    }

    public var selectedMetricHistory: [MetricSample] {
        guard let id = selectedConfiguration?.id else { return [] }
        return metricHistory[id] ?? []
    }

    public var selectedLastHealthySnapshot: ServerSnapshot? {
        guard let id = selectedConfiguration?.id else { return nil }
        return lastHealthySnapshots[id]
    }

    public func metricHistory(for serverID: UUID) -> [MetricSample] {
        metricHistory[serverID] ?? []
    }

    // MARK: - Project filtering

    /// All projects discovered on a server (including hidden ones).
    public func allProjects(for serverID: UUID) -> [DetectedProject] {
        snapshots[serverID]?.projects ?? []
    }

    /// Projects the user has chosen to display (hidden ones excluded).
    public func visibleProjects(for serverID: UUID) -> [DetectedProject] {
        let hidden = hiddenProjectIDs[serverID] ?? []
        return allProjects(for: serverID).filter { !hidden.contains($0.id) }
    }

    public func hasVisibleStoppedProjects(serverID: UUID) -> Bool {
        visibleProjects(for: serverID).contains { $0.state == .stopped }
    }

    public func isHidden(_ projectID: String, serverID: UUID) -> Bool {
        hiddenProjectIDs[serverID]?.contains(projectID) ?? false
    }

    public func isNew(_ projectID: String, serverID: UUID) -> Bool {
        newProjectIDs[serverID]?.contains(projectID) ?? false
    }

    public func hiddenCount(for serverID: UUID) -> Int {
        hiddenProjectIDs[serverID]?.count ?? 0
    }

    public func setProjectHidden(_ hidden: Bool, projectID: String, serverID: UUID) {
        var ids = hiddenProjectIDs[serverID] ?? []
        if hidden { ids.insert(projectID) } else { ids.remove(projectID) }
        hiddenProjectIDs[serverID] = ids
        saveHiddenProjectIDs()
    }

    /// Clear the "new" badges for a server (called when the user opens the filter view).
    public func clearNewProjects(serverID: UUID) {
        newProjectIDs[serverID] = []
    }

    public func isAttentionAcknowledged(serverID: UUID, key: String) -> Bool {
        acknowledgedAttention[serverID]?.contains(key) == true
    }

    public func acknowledgeAttention(serverID: UUID, key: String) {
        acknowledgeAttention(serverID: serverID, keys: [key])
    }

    public func acknowledgeAttention(serverID: UUID, keys: Set<String>) {
        guard !keys.isEmpty else { return }
        acknowledgedAttention[serverID, default: []].formUnion(keys)
        saveAcknowledgedAttention()
    }

    public func clearAttentionAcknowledgement(serverID: UUID) {
        guard acknowledgedAttention.removeValue(forKey: serverID) != nil else { return }
        saveAcknowledgedAttention()
    }

    public func clearAttentionAcknowledgement(serverID: UUID, keys: Set<String>) {
        guard var acknowledged = acknowledgedAttention[serverID] else { return }
        acknowledged.subtract(keys)
        if acknowledged.isEmpty {
            acknowledgedAttention[serverID] = nil
        } else {
            acknowledgedAttention[serverID] = acknowledged
        }
        saveAcknowledgedAttention()
    }

    public func areAttentionKeysAcknowledged(serverID: UUID, keys: Set<String>) -> Bool {
        !keys.isEmpty && keys.isSubset(of: acknowledgedAttention[serverID] ?? [])
    }

    public func hasUnacknowledgedAttention(serverID: UUID, keys: Set<String>) -> Bool {
        !keys.subtracting(acknowledgedAttention[serverID] ?? []).isEmpty
    }

    public var menuTitle: String {
        guard !configurations.isEmpty else {
            return L10n.text("VPS: не настроены", "VPS: not configured")
        }
        let healthyCount = configurations.filter { isHealthy(serverID: $0.id) }.count
        return L10n.text(
            "VPS: \(healthyCount)/\(configurations.count) доступно",
            "VPS: \(healthyCount)/\(configurations.count) available"
        )
    }

    public var menuSystemImage: String {
        guard !configurations.isEmpty else { return "server.rack" }
        if configurations.contains(where: { isFailed(serverID: $0.id) }) {
            return "xmark.circle.fill"
        }
        if configurations.allSatisfy({ isHealthy(serverID: $0.id) }) {
            return "checkmark.circle.fill"
        }
        return "arrow.triangle.2.circlepath"
    }

    public func start() {
        guard !pollingStarted else { return }
        guard !DemoData.isEnabled else { return }  // demo mode: no polling
        pollingStarted = true
        reconcilePollingTasks()
    }

    public func refresh(serverID: UUID) async {
        guard let configuration = configurations.first(where: { $0.id == serverID }) else { return }
        let previousState = loadStates[serverID]
        let previousSnapshot = snapshots[serverID]
        loadStates[serverID] = .refreshing
        do {
            let snapshot = try await inventoryService.fetch(configuration: configuration)
            snapshots[serverID] = snapshot
            loadStates[serverID] = .loaded(snapshot)
            if Self.snapshotIsHealthy(snapshot) {
                lastHealthySnapshots[serverID] = snapshot
            }

            // Notify when server comes back after being down
            switch previousState {
            case .failed: NotificationService.sendServerRestored(serverName: configuration.name)
            default: break
            }

            // Notify about newly stopped services
            if let prev = previousSnapshot {
                let prevRunning = Set(prev.projects.filter { $0.state == .running }.map(\.name))
                for project in snapshot.projects where project.state == .stopped && prevRunning.contains(project.name) {
                    NotificationService.sendServiceStopped(serviceName: project.name, serverName: configuration.name)
                }
            }

            // Detect newly appeared projects (only when a previous snapshot exists)
            if let prev = previousSnapshot {
                let prevIDs = Set(prev.projects.map(\.id))
                let appearedIDs = Set(snapshot.projects.map(\.id)).subtracting(prevIDs)
                if !appearedIDs.isEmpty {
                    newProjectIDs[serverID] = (newProjectIDs[serverID] ?? []).union(appearedIDs)
                }
            }

            // Record metric sample (keep last 30)
            let memPercent = snapshot.memoryTotalBytes > 0
                ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100 : 0
            let diskUsedPercent = snapshot.diskTotalBytes > 0
                ? (1.0 - Double(snapshot.diskFreeBytes) / Double(snapshot.diskTotalBytes)) * 100 : 0
            let sample = MetricSample(
                timestamp: snapshot.checkedAt,
                cpuPercent: Double(snapshot.cpuUsagePercent),
                memoryPercent: memPercent,
                diskUsedPercent: diskUsedPercent,
                responseMilliseconds: snapshot.responseTime * 1_000
            )
            var history = metricHistory[serverID] ?? []
            history.append(sample)
            if history.count > Self.maxStoredSamplesPerServer {
                history.removeFirst(history.count - Self.maxStoredSamplesPerServer)
            }
            metricHistory[serverID] = history
            saveMetricHistory()

            // Once an incident has actually disappeared, allow the same
            // incident to notify again if it returns later.
            let currentReport = InvestigationService.makeReport(
                snapshot: snapshot,
                history: history,
                lastHealthySnapshot: lastHealthySnapshots[serverID],
                host: configuration.host,
                user: configuration.user
            )
            reconcileAcknowledgedAttention(
                serverID: serverID,
                currentKeys: currentReport.attentionKeys
            )

        } catch {
            let errorMessage = error.localizedDescription

            if configuration.authMethod == .password,
               let sshError = error as? SSHInventoryError,
               case .noPasswordStored = sshError {
                if passwordRequest == nil || passwordRequest?.id == configuration.id {
                    passwordRequest = PasswordRequest(
                        id: configuration.id,
                        serverName: configuration.name,
                        host: configuration.host,
                        user: configuration.user,
                        message: L10n.text(
                            "Пароль для этого сервера не найден в Связке ключей. Введите SSH-пароль ещё раз.",
                            "The password for this server was not found in Keychain. Enter the SSH password again."
                        )
                    )
                }
                loadStates[serverID] = .failed(L10n.text(
                    "Для подключения нужен пароль SSH.",
                    "An SSH password is required to connect."
                ))
                return
            }

            if configuration.authMethod == .sshKey,
               let sshError = error as? SSHInventoryError,
               sshError.requiresPassword {
                if passwordRequest == nil || passwordRequest?.id == configuration.id {
                    passwordRequest = PasswordRequest(
                        id: configuration.id,
                        serverName: configuration.name,
                        host: configuration.host,
                        user: configuration.user,
                        message: L10n.text(
                            "SSH-ключ не подошёл. Введите пароль SSH для этого сервера.",
                            "The SSH key was rejected. Enter the SSH password for this server."
                        )
                    )
                }
                loadStates[serverID] = .failed(L10n.text(
                    "Для подключения нужен пароль SSH.",
                    "An SSH password is required to connect."
                ))
                return
            }

            // Notify only when server was previously reachable
            switch previousState {
            case .loaded: NotificationService.sendServerDown(serverName: configuration.name, errorMessage: errorMessage)
            default: break
            }
            loadStates[serverID] = .failed(errorMessage)
        }
    }

    public func refreshSelectedServer() async {
        guard let id = selectedConfiguration?.id else { return }
        await refresh(serverID: id)
    }

    public func refreshAll() {
        for configuration in configurations {
            Task { await refresh(serverID: configuration.id) }
        }
    }

    public func addServer(_ configuration: MonitorConfiguration) {
        let enriched = Self.configurationWithLocalCountry(configuration)
        configurations.append(enriched)
        selectedServerID = enriched.id
        scheduleCountryResolution(for: enriched.id)
    }

    public func removeServers(at offsets: IndexSet) {
        let removedIDs = offsets.map { configurations[$0].id }
        for offset in offsets.sorted(by: >) {
            configurations.remove(at: offset)
        }
        for id in removedIDs {
            loadStates[id] = nil
            snapshots[id] = nil
            lastHealthySnapshots[id] = nil
            metricHistory[id] = nil
            hiddenProjectIDs[id] = nil
            newProjectIDs[id] = nil
            acknowledgedAttention[id] = nil
            try? KeychainService.deletePassword(for: id)   // best-effort cleanup
        }
        saveHiddenProjectIDs()
        saveMetricHistory()
    }

    public func removeServer(id: UUID) {
        guard let index = configurations.firstIndex(where: { $0.id == id }) else { return }
        removeServers(at: IndexSet(integer: index))
    }

    public func updateConfiguration(_ configuration: MonitorConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        let previous = configurations[index]
        var updated = configuration
        if updated.countryCodeOverride == nil && previous.host != updated.host {
            updated.countryCode = nil
        }
        updated = Self.configurationWithLocalCountry(updated)
        configurations[index] = updated
        scheduleCountryResolution(for: updated.id)
    }

    public func dismissPasswordRequest() {
        passwordRequest = nil
    }

    public func savePasswordAndRetry(serverID: UUID, password: String) throws {
        guard let index = configurations.firstIndex(where: { $0.id == serverID }) else { return }
        var configuration = configurations[index]
        try KeychainService.savePassword(password, for: configuration.id)
        configuration.authMethod = .password
        configurations[index] = configuration
        passwordRequest = nil
        Task { await refresh(serverID: serverID) }
    }

    public func applyDomainWhitelist(serverID: UUID, domains: [String]) async throws {
        guard let configuration = configurations.first(where: { $0.id == serverID }) else { return }
        try await domainRoutingService.applyWhitelist(configuration: configuration, domains: domains)
        await refresh(serverID: serverID)
    }

    public func state(for serverID: UUID) -> LoadState {
        loadStates[serverID] ?? .waiting
    }

    public func snapshot(for serverID: UUID) -> ServerSnapshot? {
        snapshots[serverID]
    }

    public func isHealthy(serverID: UUID) -> Bool {
        guard case .loaded = state(for: serverID) else { return false }
        guard let configuration = configurations.first(where: { $0.id == serverID }),
              let snapshot = snapshots[serverID] else { return false }
        let report = InvestigationService.makeReport(
            snapshot: snapshot,
            history: metricHistory[serverID] ?? [],
            lastHealthySnapshot: lastHealthySnapshots[serverID],
            host: configuration.host,
            user: configuration.user
        )
        return !hasUnacknowledgedAttention(serverID: serverID, keys: report.attentionKeys)
    }

    private func isFailed(serverID: UUID) -> Bool {
        if case .failed = state(for: serverID) { return true }
        return false
    }

    private static func snapshotIsHealthy(_ snapshot: ServerSnapshot) -> Bool {
        !snapshot.projects.contains { $0.state == .stopped }
    }

    private static func configurationWithLocalCountry(_ configuration: MonitorConfiguration) -> MonitorConfiguration {
        var updated = configuration
        updated.countryCode = ServerPresentation.normalizedCountryCode(updated.countryCode)
        updated.countryCodeOverride = ServerPresentation.normalizedCountryCode(updated.countryCodeOverride)

        if updated.countryCodeOverride == nil && updated.countryCode == nil {
            updated.countryCode = ServerPresentation.inferredCountryCode(name: updated.name, host: updated.host)
        }
        return updated
    }

    private func scheduleCountryResolution(for serverID: UUID) {
        guard !DemoData.isEnabled else { return }
        guard let configuration = configurations.first(where: { $0.id == serverID }),
              configuration.countryCodeOverride == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            let code = await geolocationService.countryCode(for: configuration.host)
            guard let code else { return }
            applyResolvedCountryCode(code, serverID: serverID, host: configuration.host)
        }
    }

    private func applyResolvedCountryCode(_ code: String, serverID: UUID, host: String) {
        guard let index = configurations.firstIndex(where: { $0.id == serverID }) else { return }
        guard configurations[index].host == host,
              configurations[index].countryCodeOverride == nil,
              configurations[index].countryCode != code else { return }
        configurations[index].countryCode = code
    }

    private func reconcilePollingTasks() {
        guard pollingStarted else { return }
        let configuredIDs = Set(configurations.map(\.id))
        let removedIDs = pollingTasks.keys.filter { !configuredIDs.contains($0) }

        for id in removedIDs {
            pollingTasks.removeValue(forKey: id)?.cancel()
        }

        for configuration in configurations where pollingTasks[configuration.id] == nil {
            let id = configuration.id
            pollingTasks[id] = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.refresh(serverID: id)
                    guard let interval = self.configurations.first(where: { $0.id == id })?.refreshInterval else {
                        return
                    }
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
        }
    }

    private func normalizeSelection() {
        guard !configurations.isEmpty else {
            selectedServerID = nil
            return
        }
        if !configurations.contains(where: { $0.id == selectedServerID }) {
            selectedServerID = configurations.first?.id
        }
    }

    private func saveConfigurations() {
        guard !DemoData.isEnabled else { return }  // don't overwrite real settings
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: "monitor.configurations")
    }

    private func saveSelectedServerID() {
        guard !DemoData.isEnabled else { return }  // don't overwrite real selection
        UserDefaults.standard.set(selectedServerID?.uuidString, forKey: "monitor.selectedServerID")
    }

    private func saveHiddenProjectIDs() {
        let defaults = UserDefaults.standard
        let dict = hiddenProjectIDs.reduce(into: [String: [String]]()) { out, pair in
            out[pair.key.uuidString] = Array(pair.value)
        }
        defaults.set(dict, forKey: "monitor.hiddenProjectIDs")
    }

    private func saveAcknowledgedAttention() {
        guard !DemoData.isEnabled else { return }
        let defaults = UserDefaults.standard
        let dict = acknowledgedAttention.reduce(into: [String: [String]]()) { out, pair in
            out[pair.key.uuidString] = pair.value.sorted()
        }
        defaults.set(dict, forKey: "monitor.acknowledgedAttention")
    }

    private func reconcileAcknowledgedAttention(serverID: UUID, currentKeys: Set<String>) {
        guard let acknowledged = acknowledgedAttention[serverID] else { return }
        let remaining = acknowledged.intersection(currentKeys)
        guard remaining != acknowledged else { return }
        if remaining.isEmpty {
            acknowledgedAttention[serverID] = nil
        } else {
            acknowledgedAttention[serverID] = remaining
        }
        saveAcknowledgedAttention()
    }

    private static func loadHiddenProjectIDs(from defaults: UserDefaults) -> [UUID: Set<String>] {
        guard let dict = defaults.dictionary(forKey: "monitor.hiddenProjectIDs")
                as? [String: [String]] else { return [:] }
        return dict.reduce(into: [:]) { out, pair in
            if let uuid = UUID(uuidString: pair.key) {
                out[uuid] = Set(pair.value)
            }
        }
    }

    private static func loadAcknowledgedAttention(from defaults: UserDefaults) -> [UUID: Set<String>] {
        if let dict = defaults.dictionary(forKey: "monitor.acknowledgedAttention")
            as? [String: [String]] {
            return dict.reduce(into: [:]) { out, pair in
                if let id = UUID(uuidString: pair.key) {
                    out[id] = Set(pair.value)
                }
            }
        }

        // Migrate the first implementation, which stored one aggregate key
        // such as "metric:response|project:api" per server.
        guard let legacy = defaults.dictionary(forKey: "monitor.acknowledgedAttention")
                as? [String: String] else { return [:] }
        return legacy.reduce(into: [:]) { out, pair in
            if let id = UUID(uuidString: pair.key) {
                out[id] = Set(pair.value.split(separator: "|").map(String.init))
            }
        }
    }

    private static func loadConfigurations(from defaults: UserDefaults) -> [MonitorConfiguration] {
        if let data = defaults.data(forKey: "monitor.configurations"),
           let configurations = try? JSONDecoder().decode([MonitorConfiguration].self, from: data) {
            return configurations
        }

        // Migrate from single-server legacy keys (pre-multi-server versions)
        let legacyHost = defaults.string(forKey: "monitor.host")
        let legacyUser = defaults.string(forKey: "monitor.user")
        let legacyInterval = defaults.double(forKey: "monitor.refreshInterval")
        guard let host = legacyHost, !host.isEmpty else {
            return LocalSSHServerImporter().importConfigurations()
        }
        return [
            MonitorConfiguration(
                name: "My VPS",
                host: host,
                user: legacyUser ?? "root",
                refreshInterval: legacyInterval > 0 ? legacyInterval : 60
            )
        ]
    }

    private func saveMetricHistory() {
        guard !DemoData.isEnabled else { return }
        let snapshot = metricHistory.reduce(into: [String: [MetricSample]]()) { out, pair in
            out[pair.key.uuidString] = Array(pair.value.suffix(Self.maxStoredSamplesPerServer))
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = Self.metricHistoryURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func loadMetricHistory() -> [UUID: [MetricSample]] {
        guard let data = try? Data(contentsOf: metricHistoryURL()),
              let snapshot = try? JSONDecoder().decode([String: [MetricSample]].self, from: data) else {
            return [:]
        }
        return snapshot.reduce(into: [:]) { out, pair in
            if let id = UUID(uuidString: pair.key) {
                out[id] = Array(pair.value.suffix(maxStoredSamplesPerServer))
            }
        }
    }

    private static func metricHistoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("VPSMonitor", isDirectory: true)
            .appendingPathComponent("metric-history-v1.json")
    }
}
