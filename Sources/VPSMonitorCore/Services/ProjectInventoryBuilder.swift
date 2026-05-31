import Foundation

public enum ProjectInventoryBuilder {

    public static func build(from inventory: RemoteInventory) -> [DetectedProject] {
        var linkedServiceNames = Set<String>()

        // Show every directory the remote script found.
        // The script already applies maxdepth 1, so each path is a meaningful entry.
        let dirProjects: [DetectedProject] = inventory.directories.map { directory in
            let linked = inventory.services.filter {
                $0.workingDirectory == directory ||
                $0.workingDirectory.hasPrefix(directory + "/")
            }
            linkedServiceNames.formUnion(linked.map(\.name))
            return makeProject(id: directory, path: directory, services: linked)
        }

        // Show ALL services that are NOT already linked to a directory.
        // Filter out pure OS internals that are never interesting to the user.
        let serviceProjects: [DetectedProject] = inventory.services
            .filter { !linkedServiceNames.contains($0.name) }
            .filter { !isKernelInternal($0) }
            .map { makeProject(id: "service:\($0.name)", path: nil, services: [$0]) }

        let all = dirProjects + serviceProjects
        return all.sorted {
            if $0.state != $1.state { return stateRank($0.state) < stateRank($1.state) }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func hiddenSystemServiceCount(
        in inventory: RemoteInventory,
        projects: [DetectedProject]
    ) -> Int {
        // No longer filtering system services out of the count —
        // we show everything, so this is always 0.
        return 0
    }

    // MARK: - Private

    private static func makeProject(
        id: String,
        path: String?,
        services: [RemoteService]
    ) -> DetectedProject {
        let state: DetectedProject.State
        if services.contains(where: \.isRunning)  { state = .running    }
        else if services.isEmpty                  { state = .folderOnly  }
        else                                      { state = .stopped     }

        let name: String
        if let path {
            name = path.split(separator: "/").last.map(String.init) ?? path
        } else {
            name = services.first?.name
                .replacingOccurrences(of: ".service", with: "") ?? id
        }
        return DetectedProject(id: id, name: name, path: path, services: services, state: state)
    }

    /// Returns true for low-level kernel/init services that are never useful
    /// to show to the user, even in "show everything" mode.
    private static func isKernelInternal(_ service: RemoteService) -> Bool {
        let name = service.name.lowercased()
        // systemd's own housekeeping units
        if name.hasPrefix("systemd-") { return true }
        // Kernel socket/device/mount units
        if name.hasSuffix(".socket") || name.hasSuffix(".device") ||
           name.hasSuffix(".mount")  || name.hasSuffix(".swap")   ||
           name.hasSuffix(".target") || name.hasSuffix(".path")   ||
           name.hasSuffix(".timer")  { return true }
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
