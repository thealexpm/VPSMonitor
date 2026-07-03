import Foundation

public struct DomainRoutingService: Sendable {
    public init() {}

    private static let commandTimeout: TimeInterval = 25

    public func applyWhitelist(configuration: MonitorConfiguration, domains: [String]) async throws {
        let normalized = try Self.normalizedDomains(domains)
        let script = Self.applyScript(domains: normalized)

        switch configuration.authMethod {
        case .sshKey:
            _ = try await runSSH(
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "\(configuration.user)@\(configuration.host)",
                    "bash -s"
                ],
                environment: nil,
                stdin: script
            )
        case .password:
            guard let password = KeychainService.loadPassword(for: configuration.id), !password.isEmpty else {
                throw SSHInventoryError.noPasswordStored
            }
            _ = try await runSSHWithPassword(configuration: configuration, password: password, stdin: script)
        }
    }

    public static func normalizedDomains(_ domains: [String]) throws -> [String] {
        let values = domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var result: [String] = []
        for domain in values where !seen.contains(domain) {
            guard isValidDomain(domain) else {
                throw DomainRoutingError.invalidDomain(domain)
            }
            seen.insert(domain)
            result.append(domain)
        }
        return result.sorted()
    }

    private static func isValidDomain(_ domain: String) -> Bool {
        guard domain.count <= 253,
              !domain.hasPrefix("."),
              !domain.hasSuffix("."),
              domain.contains(".") else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.count),
                  !label.hasPrefix("-"),
                  !label.hasSuffix("-") else { return false }
            return label.allSatisfy { char in
                char.isASCII && (char.isLetter || char.isNumber || char == "-")
            }
        }
    }

    private static func applyScript(domains: [String]) -> String {
        let domainLines = domains.joined(separator: "\n")
        return """
        set -euo pipefail
        config="/etc/vpsm-domain-router/domains.conf"
        dnsmasq_config="/etc/vpsm-domain-router/dnsmasq.conf"
        dir="$(dirname "$config")"
        test -d "$dir"

        tmp="$(mktemp)"
        raw="$(mktemp)"
        trap 'rm -f "$tmp" "$raw"' EXIT

        cat > "$raw" <<'VPSM_DOMAINS'
        \(domainLines)
        VPSM_DOMAINS

        {
          printf '%s\\n' '# Domain whitelist routed via configured exit.'
          awk 'NF {print "ipset=/" $0 "/vpsm_wgexit4"}' "$raw"
        } > "$tmp"

        cp -a "$config" "$config.vpsm-ui-$(date +%Y%m%d%H%M%S)"
        install -m 0644 "$tmp" "$config"

        if [ -f "$dnsmasq_config" ] && ! grep -q '^log-queries' "$dnsmasq_config"; then
          printf '\\nlog-queries\\n' >> "$dnsmasq_config"
        fi

        cat >/etc/logrotate.d/vpsm-domain-router-dns <<'VPSM_LOGROTATE'
        /var/log/vpsm-domain-router-dns.log {
          daily
          rotate 7
          missingok
          notifempty
          compress
          copytruncate
        }
        VPSM_LOGROTATE

        systemctl restart vpsm-domain-dns.service

        while IFS= read -r domain; do
          [ -n "$domain" ] || continue
          dig @127.0.0.1 "$domain" A +short >/dev/null 2>&1 || true
        done < "$raw"

        systemctl is-active vpsm-domain-dns.service
        """
    }

    private func runSSHWithPassword(configuration: MonitorConfiguration, password: String, stdin: String) async throws -> String {
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
                "SSH_ASKPASS": askpassURL.path,
                "SSH_ASKPASS_REQUIRE": "force",
                "DISPLAY": ":0",
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
            ],
            stdin: stdin
        )
    }

    private func runSSH(
        arguments: [String],
        environment: [String: String]?,
        stdin: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let stdout = Pipe(); let stderr = Pipe(); let input = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = input

                let outputGroup = DispatchGroup()
                let stdoutBuffer = DomainRoutingPipeBuffer()
                let stderrBuffer = DomainRoutingPipeBuffer()

                func read(_ pipe: Pipe, into buffer: DomainRoutingPipeBuffer) {
                    outputGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        buffer.set(pipe.fileHandleForReading.readDataToEndOfFile())
                        outputGroup.leave()
                    }
                }

                do {
                    try process.run()
                    read(stdout, into: stdoutBuffer)
                    read(stderr, into: stderrBuffer)
                    input.fileHandleForWriting.write(Data(stdin.utf8))
                    try input.fileHandleForWriting.close()

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
                                "SSH-команда превысила лимит \(Int(Self.commandTimeout)) секунд.",
                                "SSH command exceeded the \(Int(Self.commandTimeout))-second timeout."
                            )
                        ))
                        return
                    }

                    guard process.terminationStatus == 0 else {
                        let msg = String(data: stderrBuffer.data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: SSHInventoryError.connectionFailed(
                            msg.isEmpty
                                ? L10n.text("Не удалось применить whitelist.", "Could not apply the whitelist.")
                                : msg
                        ))
                        return
                    }

                    continuation.resume(returning: String(data: stdoutBuffer.data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public enum DomainRoutingError: LocalizedError {
    case invalidDomain(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let domain):
            L10n.text(
                "Некорректный домен: \(domain). Используйте формат example.com без https:// и путей.",
                "Invalid domain: \(domain). Use example.com without https:// or paths."
            )
        }
    }
}

private final class DomainRoutingPipeBuffer: @unchecked Sendable {
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
