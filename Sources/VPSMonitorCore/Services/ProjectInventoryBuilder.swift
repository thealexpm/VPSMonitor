import Foundation

public enum ProjectInventoryBuilder {

    // Directories scanned on the remote server (must match remote script)
    private static let scanRoots = ["/opt", "/var/www", "/srv", "/app"]

    public static func build(from inventory: RemoteInventory) -> [DetectedProject] {
        var linkedServiceNames = Set<String>()

        // Only include directories that are exactly one level below a scan root
        var projects = inventory.directories
            .filter(isDirectlyUnderScanRoot)
            .map { directory -> DetectedProject in
                let linked = inventory.services.filter {
                    $0.workingDirectory == directory ||
                    $0.workingDirectory.hasPrefix(directory + "/")
                }
                linkedServiceNames.formUnion(linked.map(\.name))
                return makeProject(id: directory, path: directory, services: linked)
            }

        // Standalone services that look like user apps (not linked to a directory)
        let standalone = inventory.services.filter {
            !linkedServiceNames.contains($0.name) && isLikelyApplicationService($0)
        }
        projects += standalone.map {
            makeProject(id: "service:\($0.name)", path: nil, services: [$0])
        }

        return projects.sorted {
            if $0.state != $1.state { return stateRank($0.state) < stateRank($1.state) }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func hiddenSystemServiceCount(
        in inventory: RemoteInventory,
        projects: [DetectedProject]
    ) -> Int {
        let displayed = Set(projects.flatMap(\.services).map(\.name))
        return inventory.services.filter { !displayed.contains($0.name) }.count
    }

    // MARK: - Private helpers

    /// Returns true when `path` is exactly one directory level below one of the scan roots.
    /// e.g. /opt/mybot ✓, /var/www/mysite ✓, /opt/mybot/config ✗
    private static func isDirectlyUnderScanRoot(_ path: String) -> Bool {
        scanRoots.contains { root in
            path.hasPrefix(root + "/") &&
            !path.dropFirst(root.count + 1).contains("/")
        }
    }

    private static func makeProject(
        id: String,
        path: String?,
        services: [RemoteService]
    ) -> DetectedProject {
        let state: DetectedProject.State
        if services.contains(where: \.isRunning) {
            state = .running
        } else if services.isEmpty {
            state = .folderOnly
        } else {
            state = .stopped
        }

        let name = path.flatMap { $0.split(separator: "/").last.map(String.init) }
            ?? services.first?.name.replacingOccurrences(of: ".service", with: "")
            ?? id

        return DetectedProject(id: id, name: name, path: path, services: services, state: state)
    }

    /// Decides whether a service that is NOT linked to any discovered directory
    /// should be shown as a standalone project entry.
    private static func isLikelyApplicationService(_ service: RemoteService) -> Bool {
        // Always show services with a unit file in /etc/systemd/system (user-created)
        if service.fragmentPath.hasPrefix("/etc/systemd/system/") { return true }
        // Show services whose working directory is inside a scan root
        if scanRoots.contains(where: { service.workingDirectory.hasPrefix($0 + "/") }) { return true }
        return false
    }

    private static func stateRank(_ state: DetectedProject.State) -> Int {
        switch state {
        case .stopped:    0
        case .running:    1
        case .folderOnly: 2
        }
    }
}
