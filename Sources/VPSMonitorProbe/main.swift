import Foundation
import VPSMonitorCore

@main
struct VPSMonitorProbe {
    static func main() async {
        do {
            let args = CommandLine.arguments
            let configuration: MonitorConfiguration
            if args.count >= 2 {
                configuration = MonitorConfiguration(
                    name: args[1],
                    host: args[1],
                    user: args.count >= 3 ? args[2] : "root",
                    refreshInterval: 60
                )
            } else {
                configuration = .placeholder
            }
            let snapshot = try await SSHInventoryService().fetch(configuration: configuration)
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
            if let vpn = snapshot.vpn {
                print("vpn-stacks=\(vpn.stacks.count) clients=\(vpn.totalActiveConnections)")
                for stack in vpn.stacks {
                    let ports = stack.listeningPorts.joined(separator: ",")
                    print("- vpn \(stack.stack) service=\(stack.serviceName) state=\(stack.activeState)/\(stack.subState) ports=\(ports) clients=\(stack.clients.count)")
                    for client in stack.clients {
                        let country = client.countryCode ?? "??"
                        print("  client \(client.identity) \(client.publicIP) \(country) vpn=\(client.virtualIP) connected=\(client.connectedFor) rx=\(client.bytesIn) tx=\(client.bytesOut) protocol=\(client.protocolName)")
                    }
                }
            }
            if let domainRouting = snapshot.domainRouting {
                print("domain-routing dns=\(domainRouting.dnsServiceState) route=\(domainRouting.routeServiceState) whitelist=\(domainRouting.whitelistDomains.count) candidates=\(domainRouting.candidateDomains.count) routed-ips=\(domainRouting.routedIPCount)")
                for domain in domainRouting.whitelistDomains {
                    print("- whitelist \(domain)")
                }
                for candidate in domainRouting.candidateDomains.prefix(10) {
                    print("- candidate \(candidate.domain) queries=\(candidate.queryCount) last=\(candidate.lastSeen)")
                }
            }
            print("hidden-system-services=\(snapshot.systemServiceCount)")
        } catch {
            fputs("probe failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
