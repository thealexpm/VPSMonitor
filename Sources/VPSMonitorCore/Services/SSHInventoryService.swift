import Foundation

public struct SSHInventoryService: Sendable {
    public init() {}

    public func fetch(configuration: MonitorConfiguration) async throws -> ServerSnapshot {
        let startedAt = Date()
        let output = try await runSSH(configuration: configuration)
        let responseTime = Date().timeIntervalSince(startedAt)
        let inventory = RemoteInventoryParser.parse(output)
        let projects = ProjectInventoryBuilder.build(from: inventory)

        return ServerSnapshot(
            hostName: inventory.hostName.isEmpty ? configuration.host : inventory.hostName,
            checkedAt: Date(),
            responseTime: responseTime,
            cpuUsagePercent: inventory.cpuUsagePercent,
            memoryUsedBytes: inventory.memoryUsedBytes,
            memoryTotalBytes: inventory.memoryTotalBytes,
            diskFreeBytes: inventory.diskFreeBytes,
            diskTotalBytes: inventory.diskTotalBytes,
            uptimeSeconds: inventory.uptimeSeconds,
            projects: projects,
            systemServiceCount: ProjectInventoryBuilder.hiddenSystemServiceCount(
                in: inventory,
                projects: projects
            )
        )
    }

    private func runSSH(configuration: MonitorConfiguration) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()
                let standardInput = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "\(configuration.user)@\(configuration.host)",
                    "bash -s"
                ]
                process.standardOutput = standardOutput
                process.standardError = standardError
                process.standardInput = standardInput

                do {
                    try process.run()
                    standardInput.fileHandleForWriting.write(Data(Self.remoteScript.utf8))
                    try standardInput.fileHandleForWriting.close()

                    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8) ?? "SSH connection failed"
                        throw SSHInventoryError.connectionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    continuation.resume(returning: String(data: outputData, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let remoteScript = #"""
set -u
b64() { printf '%s' "$1" | base64 -w0; }
emit() {
  kind="$1"
  shift
  printf '%s' "$kind"
  for value in "$@"; do printf '|%s' "$value"; done
  printf '\n'
}

emit HOST "$(b64 "$(hostname)")"

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle1=$((idle + iowait))
sleep 0.2
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle2=$((idle + iowait))
delta=$((total2 - total1))
idle_delta=$((idle2 - idle1))
if [ "$delta" -gt 0 ]; then cpu=$((100 * (delta - idle_delta) / delta)); else cpu=0; fi

memory_total_kb="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
memory_available_kb="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
disk_total="$(df -B1 --output=size / | tail -1 | tr -d ' ')"
disk_free="$(df -B1 --output=avail / | tail -1 | tr -d ' ')"
read -r uptime _ < /proc/uptime

emit METRIC cpu_percent "$cpu"
emit METRIC memory_used_bytes "$(( (memory_total_kb - memory_available_kb) * 1024 ))"
emit METRIC memory_total_bytes "$(( memory_total_kb * 1024 ))"
emit METRIC disk_free_bytes "$disk_free"
emit METRIC disk_total_bytes "$disk_total"
emit METRIC uptime_seconds "${uptime%%.*}"

if [ -d /opt ]; then
  find /opt -mindepth 1 -maxdepth 1 -type d -print0 |
    while IFS= read -r -d '' directory; do
      emit DIRECTORY "$(b64 "$directory")"
    done
fi

{
  find /etc/systemd/system -maxdepth 1 -type f -name '*.service' -printf '%f\n'
  systemctl list-units --type=service --state=running --no-legend --no-pager |
    awk '{ print $1 }'
} |
  sort -u |
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    properties="$(systemctl show "$unit" --no-pager \
      -p Id -p Description -p ActiveState -p SubState -p WorkingDirectory -p FragmentPath -p NRestarts)"
    id="$(printf '%s\n' "$properties" | sed -n 's/^Id=//p')"
    description="$(printf '%s\n' "$properties" | sed -n 's/^Description=//p')"
    active="$(printf '%s\n' "$properties" | sed -n 's/^ActiveState=//p')"
    sub="$(printf '%s\n' "$properties" | sed -n 's/^SubState=//p')"
    directory="$(printf '%s\n' "$properties" | sed -n 's/^WorkingDirectory=//p')"
    fragment="$(printf '%s\n' "$properties" | sed -n 's/^FragmentPath=//p')"
    restarts="$(printf '%s\n' "$properties" | sed -n 's/^NRestarts=//p')"
    emit SERVICE "$(b64 "$id")" "$(b64 "$description")" "$(b64 "$active")" \
      "$(b64 "$sub")" "$(b64 "$directory")" "$(b64 "$fragment")" "${restarts:-0}"
  done
"""#
}

public enum SSHInventoryError: LocalizedError {
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            message.isEmpty ? "Не удалось подключиться к VPS по SSH." : message
        }
    }
}
