import Foundation

public struct SSHInventoryService: Sendable {
    public init() {}

    public func fetch(configuration: MonitorConfiguration) async throws -> ServerSnapshot {
        let startedAt = Date()
        let output: String
        switch configuration.authMethod {
        case .sshKey:     output = try await runSSHWithKey(configuration: configuration)
        case .password:   output = try await runSSHWithPassword(configuration: configuration)
        }
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

    // MARK: - Key-based auth (existing behaviour, unchanged)

    private func runSSHWithKey(configuration: MonitorConfiguration) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let stdout = Pipe(); let stderr = Pipe(); let stdin = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "\(configuration.user)@\(configuration.host)",
                    "bash -s"
                ]
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                do {
                    try process.run()
                    stdin.fileHandleForWriting.write(Data(Self.remoteScript.utf8))
                    try stdin.fileHandleForWriting.close()
                    let out = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let err = stderr.fileHandleForReading.readDataToEndOfFile()
                    guard process.terminationStatus == 0 else {
                        let msg = String(data: err, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: SSHInventoryError.connectionFailed(msg))
                        return
                    }
                    continuation.resume(returning: String(data: out, encoding: .utf8) ?? "")
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Password-based auth via SSH_ASKPASS

    private func runSSHWithPassword(configuration: MonitorConfiguration) async throws -> String {
        guard let password = KeychainService.loadPassword(for: configuration.id), !password.isEmpty else {
            throw SSHInventoryError.noPasswordStored
        }

        // Encode each byte as \xNN so any character is safely embedded in a printf format string
        let hexPw = password.unicodeScalars
            .map { String(format: "\\x%02x", $0.value) }
            .joined()
        let askpassContent = "#!/bin/sh\nprintf '\(hexPw)'\n"

        let askpassURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpsm_\(UUID().uuidString.prefix(8)).sh")
        try askpassContent.write(to: askpassURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: askpassURL.path)
        defer { try? FileManager.default.removeItem(at: askpassURL) }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let stdout = Pipe(); let stderr = Pipe(); let stdin = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-o", "BatchMode=no",
                    "-o", "ConnectTimeout=10",
                    "-o", "PreferredAuthentications=password",
                    "-o", "PubkeyAuthentication=no",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "NumberOfPasswordPrompts=1",
                    "\(configuration.user)@\(configuration.host)",
                    "bash -s"
                ]
                process.environment = [
                    // SSH_ASKPASS_REQUIRE=force: use askpass even without a controlling terminal
                    // Supported by OpenSSH 8.4+ (macOS 13+ ships ≥ 9.0)
                    "SSH_ASKPASS":         askpassURL.path,
                    "SSH_ASKPASS_REQUIRE": "force",
                    "DISPLAY":            ":0",          // fallback for older SSH builds
                    "HOME":               NSHomeDirectory(),
                    "PATH":               "/usr/bin:/bin:/usr/sbin:/sbin"
                ]
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                do {
                    try process.run()
                    stdin.fileHandleForWriting.write(Data(Self.remoteScript.utf8))
                    try stdin.fileHandleForWriting.close()
                    let out = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let err = stderr.fileHandleForReading.readDataToEndOfFile()
                    guard process.terminationStatus == 0 else {
                        let msg = String(data: err, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: SSHInventoryError.connectionFailed(
                            msg.isEmpty ? "Ошибка подключения. Проверьте логин и пароль." : msg
                        ))
                        return
                    }
                    continuation.resume(returning: String(data: out, encoding: .utf8) ?? "")
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Remote script (read-only, exits cleanly)

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
    case noPasswordStored

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            msg.isEmpty ? "Не удалось подключиться к VPS по SSH." : msg
        case .noPasswordStored:
            "Пароль не сохранён. Откройте Настройки и введите пароль для этого сервера."
        }
    }
}
