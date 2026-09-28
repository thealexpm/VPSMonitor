import Foundation

public struct VPNProvisioningService: Sendable {
    public struct ProvisionedAppleProfile: Sendable {
        public let username: String
        public let password: String
        public let profileData: Data

        public init(username: String, password: String, profileData: Data) {
            self.username = username
            self.password = password
            self.profileData = profileData
        }
    }

    public init() {}

    private static let commandTimeout: TimeInterval = 25

    public func createAppleProfile(
        configuration: MonitorConfiguration,
        username rawUsername: String,
        password rawPassword: String,
        profileName rawProfileName: String?
    ) async throws -> ProvisionedAppleProfile {
        let username = try Self.normalizedUsername(rawUsername)
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password.count >= 12 else {
            throw VPNProvisioningError.weakPassword
        }

        let script = Self.provisionScript(username: username, password: password)
        let output: String
        switch configuration.authMethod {
        case .sshKey:
            output = try await runSSH(
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
            guard let sshPassword = KeychainService.loadPassword(for: configuration.id),
                  !sshPassword.isEmpty else {
                throw SSHInventoryError.noPasswordStored
            }
            output = try await runSSHWithPassword(configuration: configuration, password: sshPassword, stdin: script)
        }

        let caData = try Self.caCertificateData(from: output)
        let profileName = rawProfileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = profileName?.isEmpty == false ? profileName! : "\(configuration.name) VPN"
        let profile = try Self.mobileConfig(
            displayName: title,
            serverAddress: configuration.host,
            remoteIdentifier: configuration.host,
            username: username,
            password: password,
            caCertificateData: caData
        )
        return ProvisionedAppleProfile(username: username, password: password, profileData: profile)
    }

    public static func generatedPassword(length: Int = 20) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        var result = ""
        for _ in 0..<max(12, length) {
            result.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return result
    }

    public static func normalizedUsername(_ value: String) throws -> String {
        let username = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...48).contains(username.count),
              username.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
            throw VPNProvisioningError.invalidUsername
        }
        return username
    }

    private static func provisionScript(username: String, password: String) -> String {
        let username64 = Data(username.utf8).base64EncodedString()
        let password64 = Data(password.utf8).base64EncodedString()
        return """
        set -euo pipefail
        username="$(printf '%s' '\(username64)' | base64 -d)"
        password="$(printf '%s' '\(password64)' | base64 -d)"

        case "$username" in
          ""|*[!A-Za-z0-9._-]*)
            echo "Invalid username" >&2
            exit 2
            ;;
        esac

        secrets="/etc/ipsec.secrets"
        ca=""
        for candidate in /etc/ipsec.d/private-vpn/ca-cert.pem /etc/ipsec.d/cacerts/personal-vpn-ca-cert.pem /etc/ipsec.d/cacerts/*.pem; do
          if [ -f "$candidate" ]; then
            ca="$candidate"
            break
          fi
        done
        if [ ! -f "$ca" ]; then
          echo "CA certificate was not found" >&2
          exit 3
        fi

        escaped_password="$(printf '%s' "$password" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g')"
        new_line="$username : EAP \\"$escaped_password\\""
        tmp="$(mktemp)"
        backup="/etc/ipsec.secrets.vpsm-$(date +%Y%m%d%H%M%S)"
        trap 'rm -f "$tmp"' EXIT

        cp -a "$secrets" "$backup"
        awk -v user="$username" -v line="$new_line" '
          BEGIN { replaced=0 }
          $0 ~ "^[[:space:]]*" user "[[:space:]]*:[[:space:]]*EAP([[:space:]]|$)" {
            print line
            replaced=1
            next
          }
          { print }
          END {
            if (!replaced) print line
          }
        ' "$secrets" > "$tmp"

        install -m 600 -o root -g root "$tmp" "$secrets"
        ipsec rereadsecrets >/dev/null 2>&1 || ipsec reload >/dev/null

        printf '%s\\n' 'VPSM_PROFILE_OK'
        printf 'VPSM_CA_B64='
        base64 -w 0 "$ca" 2>/dev/null || base64 "$ca" | tr -d '\\n'
        printf '\\n'
        """
    }

    private static func caCertificateData(from output: String) throws -> Data {
        for line in output.split(separator: "\n") {
            if line.hasPrefix("VPSM_CA_B64=") {
                let encoded = String(line.dropFirst("VPSM_CA_B64=".count))
                if let data = Data(base64Encoded: encoded), !data.isEmpty {
                    return data
                }
            }
        }
        throw VPNProvisioningError.missingCertificate
    }

    private static func mobileConfig(
        displayName: String,
        serverAddress: String,
        remoteIdentifier: String,
        username: String,
        password: String,
        caCertificateData: Data
    ) throws -> Data {
        let rootCertificateUUID = UUID().uuidString
        let vpnUUID = UUID().uuidString
        let profileUUID = UUID().uuidString

        let vpnPayload: [String: Any] = [
            "PayloadType": "com.apple.vpn.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": "ru.alexpm.vpsmonitor.vpn.\(vpnUUID)",
            "PayloadUUID": vpnUUID,
            "PayloadDisplayName": displayName,
            "UserDefinedName": displayName,
            "VPNType": "IKEv2",
            "IKEv2": [
                "RemoteAddress": serverAddress,
                "RemoteIdentifier": remoteIdentifier,
                "LocalIdentifier": username,
                "AuthenticationMethod": "None",
                "ExtendedAuthEnabled": true,
                "AuthName": username,
                "AuthPassword": password,
                "EnablePFS": true,
                "DisableMOBIKE": false,
                "DisableRedirect": false,
                "DeadPeerDetectionRate": "Medium",
                "IKESecurityAssociationParameters": [
                    "EncryptionAlgorithm": "AES-256",
                    "IntegrityAlgorithm": "SHA2-256",
                    "DiffieHellmanGroup": 14,
                    "LifeTimeInMinutes": 1440
                ],
                "ChildSecurityAssociationParameters": [
                    "EncryptionAlgorithm": "AES-256",
                    "IntegrityAlgorithm": "SHA2-256",
                    "DiffieHellmanGroup": 14,
                    "LifeTimeInMinutes": 1440
                ]
            ] as [String: Any]
        ]

        let certificatePayload: [String: Any] = [
            "PayloadType": "com.apple.security.root",
            "PayloadVersion": 1,
            "PayloadIdentifier": "ru.alexpm.vpsmonitor.vpn.ca.\(rootCertificateUUID)",
            "PayloadUUID": rootCertificateUUID,
            "PayloadDisplayName": "\(displayName) CA",
            "PayloadContent": caCertificateData
        ]

        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "ru.alexpm.vpsmonitor.profile.\(profileUUID)",
            "PayloadUUID": profileUUID,
            "PayloadDisplayName": displayName,
            "PayloadDescription": "IKEv2 VPN profile generated by VPSMonitor.",
            "PayloadOrganization": "VPSMonitor",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [certificatePayload, vpnPayload]
        ]

        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
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
                let stdoutBuffer = VPNProvisioningPipeBuffer()
                let stderrBuffer = VPNProvisioningPipeBuffer()

                func read(_ pipe: Pipe, into buffer: VPNProvisioningPipeBuffer) {
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
                                ? L10n.text("Не удалось создать VPN-профиль.", "Could not create the VPN profile.")
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

public enum VPNProvisioningError: LocalizedError {
    case invalidUsername
    case weakPassword
    case missingCertificate

    public var errorDescription: String? {
        switch self {
        case .invalidUsername:
            L10n.text(
                "Имя VPN-пользователя должно быть 3-48 символов: латиница, цифры, точка, дефис или подчёркивание.",
                "VPN username must be 3-48 characters: letters, numbers, dot, dash, or underscore."
            )
        case .weakPassword:
            L10n.text(
                "Пароль VPN должен быть не короче 12 символов.",
                "VPN password must be at least 12 characters."
            )
        case .missingCertificate:
            L10n.text(
                "Сервер создал пользователя, но не вернул CA-сертификат для Apple-профиля.",
                "The server created the user but did not return the CA certificate for the Apple profile."
            )
        }
    }
}

private final class VPNProvisioningPipeBuffer: @unchecked Sendable {
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
