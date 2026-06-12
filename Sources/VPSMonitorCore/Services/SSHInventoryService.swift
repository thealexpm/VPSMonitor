import Foundation

public struct SSHInventoryService: Sendable {
    public init() {}
    private static let commandTimeout: TimeInterval = 30

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
        try await runSSH(
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                "\(configuration.user)@\(configuration.host)",
                "bash -s"
            ],
            environment: nil,
            defaultErrorMessage: L10n.text(
                "Не удалось подключиться к VPS по SSH.",
                "Could not connect to the VPS over SSH."
            )
        )
    }

    // MARK: - Password-based auth via SSH_ASKPASS

    private func runSSHWithPassword(configuration: MonitorConfiguration) async throws -> String {
        guard let password = KeychainService.loadPassword(for: configuration.id), !password.isEmpty else {
            throw SSHInventoryError.noPasswordStored
        }

        // Encode UTF-8 bytes as \xNN so every password character survives shell printf.
        let hexPw = password.utf8
            .map { String(format: "\\x%02x", $0) }
            .joined()
        let askpassContent = "#!/bin/sh\nprintf '\(hexPw)'\n"

        let askpassURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpsm_\(UUID().uuidString.prefix(8)).sh")
        try askpassContent.write(to: askpassURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: askpassURL.path)
        defer { try? FileManager.default.removeItem(at: askpassURL) }

        return try await runSSH(
            arguments: [
                "-o", "BatchMode=no",
                "-o", "ConnectTimeout=10",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "NumberOfPasswordPrompts=1",
                "\(configuration.user)@\(configuration.host)",
                "bash -s"
            ],
            environment: [
                // SSH_ASKPASS_REQUIRE=force: use askpass even without a controlling terminal
                // Supported by OpenSSH 8.4+ (macOS 13+ ships >= 9.0)
                "SSH_ASKPASS":         askpassURL.path,
                "SSH_ASKPASS_REQUIRE": "force",
                "DISPLAY":            ":0",          // fallback for older SSH builds
                "HOME":               NSHomeDirectory(),
                "PATH":               "/usr/bin:/bin:/usr/sbin:/sbin"
            ],
            defaultErrorMessage: L10n.text(
                "Ошибка подключения. Проверьте логин и пароль.",
                "Connection failed. Check the username and password."
            )
        )
    }

    private func runSSH(
        arguments: [String],
        environment: [String: String]?,
        defaultErrorMessage: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let stdout = Pipe(); let stderr = Pipe(); let stdin = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin

                let outputGroup = DispatchGroup()
                let stdoutBuffer = PipeBuffer()
                let stderrBuffer = PipeBuffer()

                func read(_ pipe: Pipe, into buffer: PipeBuffer) {
                    outputGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        buffer.set(data)
                        outputGroup.leave()
                    }
                }

                do {
                    try process.run()
                    read(stdout, into: stdoutBuffer)
                    read(stderr, into: stderrBuffer)

                    stdin.fileHandleForWriting.write(Data(Self.remoteScript.utf8))
                    try stdin.fileHandleForWriting.close()

                    let timeoutWorkItem = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + Self.commandTimeout,
                        execute: timeoutWorkItem
                    )

                    process.waitUntilExit()
                    timeoutWorkItem.cancel()
                    outputGroup.wait()

                    guard process.terminationReason != .uncaughtSignal else {
                        continuation.resume(throwing: SSHInventoryError.connectionFailed(
                            L10n.text(
                                "SSH-проверка превысила лимит \(Int(Self.commandTimeout)) секунд.",
                                "SSH check exceeded the \(Int(Self.commandTimeout))-second timeout."
                            )
                        ))
                        return
                    }

                    guard process.terminationStatus == 0 else {
                        let msg = String(data: stderrBuffer.data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: SSHInventoryError.connectionFailed(msg.isEmpty ? defaultErrorMessage : msg))
                        return
                    }
                    continuation.resume(returning: String(data: stdoutBuffer.data, encoding: .utf8) ?? "")
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

# Scan all common locations where projects, sites, bots, VPNs live
for scandir in \
    /opt /var/www /srv /app /apps \
    /web /www /websites /sites /projects \
    /data /storage /docker /containers; do
  [ -d "$scandir" ] || continue
  find "$scandir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null |
    while IFS= read -r -d '' d; do emit DIRECTORY "$(b64 "$d")"; done
done

# One level inside every user home directory (catches /home/ubuntu/myproject etc.)
for homedir in /root /home/*/; do
  [ -d "$homedir" ] || continue
  find "$homedir" -mindepth 1 -maxdepth 1 -type d \
       ! -name '.*' -print0 2>/dev/null |
    while IFS= read -r -d '' d; do emit DIRECTORY "$(b64 "$d")"; done
done

{
  find /etc/systemd/system -maxdepth 1 -type f -name '*.service' -printf '%f\n'
  systemctl list-units --type=service --state=running --no-legend --no-pager |
    awk '{ print $1 }'
} |
  sort -u |
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    properties="$(systemctl show "$unit" --no-pager \
      -p Id -p Description -p ActiveState -p SubState \
      -p WorkingDirectory -p FragmentPath -p NRestarts -p MainPID)"
    id="$(printf '%s\n' "$properties"        | sed -n 's/^Id=//p')"
    description="$(printf '%s\n' "$properties" | sed -n 's/^Description=//p')"
    active="$(printf '%s\n' "$properties"    | sed -n 's/^ActiveState=//p')"
    sub="$(printf '%s\n' "$properties"       | sed -n 's/^SubState=//p')"
    directory="$(printf '%s\n' "$properties" | sed -n 's/^WorkingDirectory=//p')"
    fragment="$(printf '%s\n' "$properties"  | sed -n 's/^FragmentPath=//p')"
    restarts="$(printf '%s\n' "$properties"  | sed -n 's/^NRestarts=//p')"
    pid="$(printf '%s\n' "$properties"       | sed -n 's/^MainPID=//p')"
    cpu_x100=0; mem_kb=0
    if [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
      _ps="$(ps -p "$pid" -o %cpu= -o rss= 2>/dev/null)"
      if [ -n "$_ps" ]; then
        cpu_x100="$(printf '%s\n' "$_ps" | awk '{printf "%d", $1 * 100 + 0.5}')"
        mem_kb="$(printf '%s\n' "$_ps"   | awk '{print int($2)}')"
      fi
    fi
    emit SERVICE "$(b64 "$id")" "$(b64 "$description")" "$(b64 "$active")" \
      "$(b64 "$sub")" "$(b64 "$directory")" "$(b64 "$fragment")" \
      "${restarts:-0}" "${cpu_x100:-0}" "${mem_kb:-0}"
  done
"""#
}

public enum SSHInventoryError: LocalizedError {
    case connectionFailed(String)
    case noPasswordStored

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            msg.isEmpty
                ? L10n.text(
                    "Не удалось подключиться к VPS по SSH.",
                    "Could not connect to the VPS over SSH."
                )
                : msg
        case .noPasswordStored:
            L10n.text(
                "Пароль не сохранён. Откройте Настройки и введите пароль для этого сервера.",
                "No password is saved. Open Settings and enter the password for this server."
            )
        }
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }

    func set(_ data: Data) {
        lock.lock()
        storedData = data
        lock.unlock()
    }
}
