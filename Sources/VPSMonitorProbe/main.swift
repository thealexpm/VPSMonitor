import Foundation
import VPSMonitorCore

@main
struct VPSMonitorProbe {
    static func main() async {
        do {
            let snapshot = try await SSHInventoryService().fetch(configuration: .placeholder)
            print("host=\(snapshot.hostName)")
            print("cpu=\(snapshot.cpuUsagePercent)%")
            print("memory=\(MonitorFormatters.bytes(snapshot.memoryUsedBytes))/\(MonitorFormatters.bytes(snapshot.memoryTotalBytes))")
            print("disk-free=\(MonitorFormatters.bytes(snapshot.diskFreeBytes))")
            print("response=\(MonitorFormatters.milliseconds(snapshot.responseTime))")
            print("projects=\(snapshot.projects.count)")
            for project in snapshot.projects {
                let services = project.services.map(\.name).joined(separator: ",")
                print("- \(project.name) [\(project.state.rawValue)] services=\(services)")
            }
            print("hidden-system-services=\(snapshot.systemServiceCount)")
        } catch {
            fputs("probe failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
