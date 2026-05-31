import Foundation

public enum ProjectInventoryBuilder {
    public static func build(from inventory: RemoteInventory) -> [DetectedProject] {
        var linkedServiceNames = Set<String>()
        var projects = inventory.directories
            .filter { $0.split(separator: "/").count == 2 }
            .map { directory -> DetectedProject in
                let linkedServices = inventory.services.filter {
                    $0.workingDirectory == directory || $0.workingDirectory.hasPrefix(directory + "/")
                }
                linkedServiceNames.formUnion(linkedServices.map(\.name))
                return makeProject(id: directory, path: directory, services: linkedServices)
            }

        let standaloneServices = inventory.services.filter {
            !linkedServiceNames.contains($0.name) && isLikelyApplicationService($0)
        }
        projects += standaloneServices.map {
            makeProject(id: "service:\($0.name)", path: nil, services: [$0])
        }

        return projects.sorted {
            if $0.state != $1.state {
                return stateRank($0.state) < stateRank($1.state)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func hiddenSystemServiceCount(in inventory: RemoteInventory, projects: [DetectedProject]) -> Int {
        let displayed = Set(projects.flatMap(\.services).map(\.name))
        return inventory.services.filter { !displayed.contains($0.name) }.count
    }

    private static func makeProject(id: String, path: String?, services: [RemoteService]) -> DetectedProject {
        let state: DetectedProject.State
        if services.contains(where: \.isRunning) {
            state = .running
        } else if services.isEmpty {
            state = .folderOnly
        } else {
            state = .stopped
        }

        let name = path?.split(separator: "/").last.map(String.init)
            ?? services.first?.name.replacingOccurrences(of: ".service", with: "")
            ?? id
        return DetectedProject(id: id, name: name, path: path, services: services, state: state)
    }

    private static func isLikelyApplicationService(_ service: RemoteService) -> Bool {
        let name = service.name.lowercased()
        return service.fragmentPath.hasPrefix("/etc/systemd/system/")
            || name.contains("bot")
    }

    private static func stateRank(_ state: DetectedProject.State) -> Int {
        switch state {
        case .stopped: 0
        case .running: 1
        case .folderOnly: 2
        }
    }
}
