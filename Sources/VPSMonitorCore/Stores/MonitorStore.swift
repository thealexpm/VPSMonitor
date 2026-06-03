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
    @Published public private(set) var metricHistory: [UUID: [MetricSample]] = [:]
    /// Project IDs the user chose to hide, per server. Persisted.
    @Published public private(set) var hiddenProjectIDs: [UUID: Set<String>] = [:]
    /// Project IDs that appeared since the previous poll, per server. Session-only.
    @Published public private(set) var newProjectIDs: [UUID: Set<String>] = [:]

    private let inventoryService: SSHInventoryService
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var pollingStarted = false

    public init(inventoryService: SSHInventoryService = SSHInventoryService()) {
        self.inventoryService = inventoryService
        let defaults = UserDefaults.standard
        if DemoData.isEnabled {
            // Demo mode: fictional servers, no SSH calls — used for screenshots
            self.configurations = DemoData.configurations
            self.selectedServerID = DemoData.productionServerID
            self.hiddenProjectIDs = [:]
            for cfg in DemoData.configurations {
                let snap = DemoData.snapshot(for: cfg.id)
                self.snapshots[cfg.id] = snap
                self.loadStates[cfg.id] = .loaded(snap)
                self.metricHistory[cfg.id] = Self.demoHistory(for: snap)
            }
        } else {
            self.configurations = Self.loadConfigurations(from: defaults)
            self.selectedServerID = defaults.string(forKey: "monitor.selectedServerID").flatMap(UUID.init)
            self.hiddenProjectIDs = Self.loadHiddenProjectIDs(from: defaults)
            normalizeSelection()
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
                diskUsedPercent: max(0, diskBase + jitter * 0.05)
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
                diskUsedPercent: diskUsedPercent
            )
            var history = metricHistory[serverID] ?? []
            history.append(sample)
            if history.count > 30 { history.removeFirst(history.count - 30) }
            metricHistory[serverID] = history

        } catch {
            // Notify only when server was previously reachable
            switch previousState {
            case .loaded: NotificationService.sendServerDown(serverName: configuration.name)
            default: break
            }
            loadStates[serverID] = .failed(error.localizedDescription)
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
        configurations.append(configuration)
        selectedServerID = configuration.id
    }

    public func removeServers(at offsets: IndexSet) {
        let removedIDs = offsets.map { configurations[$0].id }
        for offset in offsets.sorted(by: >) {
            configurations.remove(at: offset)
        }
        for id in removedIDs {
            loadStates[id] = nil
            snapshots[id] = nil
            metricHistory[id] = nil
            hiddenProjectIDs[id] = nil
            newProjectIDs[id] = nil
            KeychainService.deletePassword(for: id)   // clean up stored password if any
        }
        saveHiddenProjectIDs()
    }

    public func removeServer(id: UUID) {
        guard let index = configurations.firstIndex(where: { $0.id == id }) else { return }
        removeServers(at: IndexSet(integer: index))
    }

    public func updateConfiguration(_ configuration: MonitorConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index] = configuration
    }

    public func state(for serverID: UUID) -> LoadState {
        loadStates[serverID] ?? .waiting
    }

    public func snapshot(for serverID: UUID) -> ServerSnapshot? {
        snapshots[serverID]
    }

    public func isHealthy(serverID: UUID) -> Bool {
        guard case .loaded(let snapshot) = state(for: serverID) else { return false }
        return !snapshot.projects.contains(where: { $0.state == .stopped })
    }

    private func isFailed(serverID: UUID) -> Bool {
        if case .failed = state(for: serverID) { return true }
        return false
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

    private static func loadHiddenProjectIDs(from defaults: UserDefaults) -> [UUID: Set<String>] {
        guard let dict = defaults.dictionary(forKey: "monitor.hiddenProjectIDs")
                as? [String: [String]] else { return [:] }
        return dict.reduce(into: [:]) { out, pair in
            if let uuid = UUID(uuidString: pair.key) {
                out[uuid] = Set(pair.value)
            }
        }
    }

    private static func loadConfigurations(from defaults: UserDefaults) -> [MonitorConfiguration] {
        if let data = defaults.data(forKey: "monitor.configurations"),
           let configurations = try? JSONDecoder().decode([MonitorConfiguration].self, from: data),
           !configurations.isEmpty {
            return configurations
        }

        // Migrate from single-server legacy keys (pre-multi-server versions)
        let legacyHost = defaults.string(forKey: "monitor.host")
        let legacyUser = defaults.string(forKey: "monitor.user")
        let legacyInterval = defaults.double(forKey: "monitor.refreshInterval")
        guard let host = legacyHost, !host.isEmpty else {
            return []   // Fresh install: user adds their own server via Settings
        }
        return [
            MonitorConfiguration(
                name: "My VPS",
                host: host,
                user: legacyUser ?? "root",
                refreshInterval: legacyInterval > 0 ? legacyInterval : 30
            )
        ]
    }
}
