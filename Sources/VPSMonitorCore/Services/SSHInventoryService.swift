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
        let vpn = await buildVPNSnapshot(from: inventory)
        let domainRouting = buildDomainRoutingSnapshot(from: inventory)
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
            ),
            vpn: vpn,
            domainRouting: domainRouting
        )
    }

    private func buildVPNSnapshot(from inventory: RemoteInventory) async -> VPNSnapshot? {
        guard !inventory.vpnStatuses.isEmpty else { return nil }

        let geolocation = IPGeolocationService()
        var countryCodes: [String: String] = [:]
        for ip in Set(inventory.vpnClients.map(\.publicIP)).filter({ !$0.isEmpty }) {
            countryCodes[ip] = await geolocation.countryCode(for: ip)
        }

        let enrichedClients = inventory.vpnClients.map { client in
            client.withCountryCode(countryCodes[client.publicIP] ?? nil)
        }

        let stacks = inventory.vpnStatuses.map { status in
            let clients = enrichedClients.filter { $0.stack == status.stack }
            return VPNStatus(
                stack: status.stack,
                serviceName: status.serviceName,
                activeState: status.activeState,
                subState: status.subState,
                activeConnections: status.activeConnections,
                listeningPorts: status.listeningPorts,
                details: status.details,
                clients: clients
            )
        }
        return VPNSnapshot(stacks: stacks)
    }

    private func buildDomainRoutingSnapshot(from inventory: RemoteInventory) -> DomainRoutingSnapshot? {
        guard let header = inventory.domainRouteHeader else { return nil }
        return DomainRoutingSnapshot(
            dnsServiceState: header.dnsServiceState,
            routeServiceState: header.routeServiceState,
            whitelistDomains: inventory.domainWhitelistDomains.sorted(),
            candidateDomains: inventory.domainRouteCandidates.sorted {
                if $0.queryCount == $1.queryCount { return $0.domain < $1.domain }
                return $0.queryCount > $1.queryCount
            },
            routedIPCount: header.routedIPCount,
            configPath: header.configPath,
            logPath: header.logPath
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
            host: configuration.host,
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
            host: configuration.host,
            defaultErrorMessage: L10n.text(
                "Ошибка подключения. Проверьте логин и пароль.",
                "Connection failed. Check the username and password."
            )
        )
    }

    private func runSSH(
        arguments: [String],
        environment: [String: String]?,
        host: String,
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
                        let errorMessage = msg.isEmpty
                            ? defaultErrorMessage
                            : Self.userActionableMessage(for: msg, host: host)
                        continuation.resume(throwing: SSHInventoryError.connectionFailed(errorMessage))
                        return
                    }
                    continuation.resume(returning: String(data: stdoutBuffer.data, encoding: .utf8) ?? "")
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func userActionableMessage(for sshError: String, host: String) -> String {
        let lowercased = sshError.lowercased()
        guard isPrivateIPv4(host),
              lowercased.contains("no route to host") || lowercased.contains("network is unreachable")
        else {
            return sshError
        }

        return L10n.text(
            "macOS может блокировать доступ VPSMonitor к локальной сети. Откройте Системные настройки -> Конфиденциальность и безопасность -> Локальная сеть и разрешите доступ для VPSMonitor.\n\nИсходная ошибка SSH: \(sshError)",
            "macOS may be blocking VPSMonitor access to the local network. Open System Settings -> Privacy & Security -> Local Network and allow access for VPSMonitor.\n\nOriginal SSH error: \(sshError)"
        )
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let first = Int(parts[0]),
              let second = Int(parts[1]),
              parts.allSatisfy({ Int($0) != nil }) else {
            return false
        }

        return first == 10
            || (first == 192 && second == 168)
            || (first == 172 && (16...31).contains(second))
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

emit_vpn_status() {
  stack="$1"; service="$2"; active="$3"; sub="$4"; connections="$5"; ports="$6"; details="$7"
  emit VPN "$(b64 "$stack")" "$(b64 "$service")" "$(b64 "$active")" "$(b64 "$sub")" \
    "${connections:-0}" "$(b64 "$ports")" "$(b64 "$details")"
}

emit_vpn_client() {
  stack="$1"; connection_id="$2"; identity="$3"; public_ip="$4"; virtual_ip="$5"
  connected_for="$6"; protocol="$7"; proposal="$8"; bytes_in="$9"; bytes_out="${10}"
  packets_in="${11}"; packets_out="${12}"; last_activity="${13}"
  emit VPNCLIENT "$(b64 "$stack")" "$(b64 "$connection_id")" "$(b64 "$identity")" \
    "$(b64 "$public_ip")" "$(b64 "$virtual_ip")" "$(b64 "$connected_for")" \
    "$(b64 "$protocol")" "$(b64 "$proposal")" "${bytes_in:-0}" "${bytes_out:-0}" \
    "${packets_in:-0}" "${packets_out:-0}" "${last_activity:-0}"
}

service_state() {
  svc="$1"
  systemctl show "$svc" -p ActiveState -p SubState --no-pager 2>/dev/null |
    awk -F= '
      /^ActiveState=/ { active=$2 }
      /^SubState=/ { substate=$2 }
      END {
        if (active == "") active="inactive";
        if (substate == "") substate="dead";
        print active "|" substate
      }'
}

udp_ports() {
  pattern="$1"
  ss -H -lunp 2>/dev/null |
    awk '{print $4}' |
    sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' |
    grep -E "$pattern" |
    sort -n -u |
    paste -sd, - 2>/dev/null
}

detect_strongswan() {
  svc=""
  for candidate in strongswan-starter.service strongswan.service charon-systemd.service ipsec.service; do
    if systemctl list-unit-files "$candidate" --no-legend --no-pager 2>/dev/null | grep -q "$candidate"; then
      svc="$candidate"; break
    fi
  done
  [ -n "$svc" ] || pgrep -x charon >/dev/null 2>&1 || return 0
  [ -n "$svc" ] || svc="charon"
  state="$(service_state "$svc")"
  active="${state%%|*}"; sub="${state#*|}"
  status="$(ipsec statusall 2>/dev/null || swanctl --list-sas 2>/dev/null || true)"
  connections="$(printf '%s\n' "$status" | sed -n 's/.*Security Associations (\([0-9][0-9]*\) up,.*/\1/p' | head -n 1)"
  [ -n "$connections" ] || connections="$(printf '%s\n' "$status" | grep -Ei 'ESTABLISHED|IKE_SA' | wc -l | tr -d ' ')"
  details="$(printf '%s\n' "$status" | sed -n '1,4p' | tr '\n' '; ' | cut -c 1-180)"
  [ -n "$details" ] || details="IKEv2/IPsec service detected"
  emit_vpn_status "strongSwan" "$svc" "$active" "$sub" "$connections" "$(udp_ports '^(500|4500)$')" "$details"
  parse_strongswan_clients "$status"
}

parse_strongswan_clients() {
  status_text="$1"
  connection_id=""; identity=""; public_ip=""; virtual_ip=""; connected_for=""
  proposal=""; bytes_in=0; bytes_out=0; packets_in=0; packets_out=0; last_activity=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]ESTABLISHED[[:space:]](.+)[[:space:]]ago,.*\.\.\.([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\[ ]]; then
      connection_id="${BASH_REMATCH[1]}"
      connected_for="${BASH_REMATCH[2]} ago"
      public_ip="${BASH_REMATCH[3]}"
      identity=""; virtual_ip=""; proposal=""
      bytes_in=0; bytes_out=0; packets_in=0; packets_out=0; last_activity=0
    elif [[ "$line" =~ Remote[[:space:]]EAP[[:space:]]identity:[[:space:]](.*)$ ]]; then
      identity="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ IKE[[:space:]]proposal:[[:space:]](.*)$ ]]; then
      proposal="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ([0-9]+)[[:space:]]bytes_i[[:space:]]\(([0-9]+)[[:space:]]pkts,[[:space:]]([0-9]+)s[[:space:]]ago\),[[:space:]]([0-9]+)[[:space:]]bytes_o[[:space:]]\(([0-9]+)[[:space:]]pkts,[[:space:]]([0-9]+)s[[:space:]]ago\) ]]; then
      bytes_in="${BASH_REMATCH[1]}"
      packets_in="${BASH_REMATCH[2]}"
      last_in="${BASH_REMATCH[3]}"
      bytes_out="${BASH_REMATCH[4]}"
      packets_out="${BASH_REMATCH[5]}"
      last_out="${BASH_REMATCH[6]}"
      if [ "$last_in" -le "$last_out" ] 2>/dev/null; then last_activity="$last_in"; else last_activity="$last_out"; fi
    elif [[ "$line" =~ ===[[:space:]]([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/[0-9]+ ]]; then
      virtual_ip="${BASH_REMATCH[1]}"
      if [ -n "$connection_id" ] && [ -n "$public_ip" ]; then
        emit_vpn_client "strongSwan" "$connection_id" "$identity" "$public_ip" "$virtual_ip" \
          "$connected_for" "IKEv2/IPsec" "$proposal" "$bytes_in" "$bytes_out" \
          "$packets_in" "$packets_out" "$last_activity"
      fi
    fi
  done <<< "$status_text"
}

detect_wireguard() {
  command -v wg >/dev/null 2>&1 || return 0
  interfaces="$(wg show interfaces 2>/dev/null || true)"
  [ -n "$interfaces" ] || return 0
  peers=0
  details=""
  for iface in $interfaces; do
    count="$(wg show "$iface" peers 2>/dev/null | wc -l | tr -d ' ')"
    peers=$((peers + count))
    details="${details}${iface}: ${count} peers; "
  done
  service="wg-quick@${interfaces%% *}.service"
  state="$(service_state "$service")"
  emit_vpn_status "WireGuard" "$service" "${state%%|*}" "${state#*|}" "$peers" "$(udp_ports '^(51820|51821)$')" "$details"
}

detect_openvpn() {
  units="$(systemctl list-units 'openvpn*.service' --all --no-legend --no-pager 2>/dev/null | awk '{print $1}')"
  [ -n "$units" ] || pgrep -x openvpn >/dev/null 2>&1 || return 0
  if [ -z "$units" ]; then units="openvpn"; fi
  for svc in $units; do
    state="$(service_state "$svc")"
    details="$(journalctl -u "$svc" --since '30 minutes ago' --no-pager 2>/dev/null | grep -Ei 'peer connection|initialization sequence completed|client' | tail -n 2 | tr '\n' '; ' | cut -c 1-180)"
    [ -n "$details" ] || details="OpenVPN service detected"
    emit_vpn_status "OpenVPN" "$svc" "${state%%|*}" "${state#*|}" "0" "$(udp_ports '^(1194)$')" "$details"
  done
}

detect_strongswan
detect_wireguard
detect_openvpn

detect_domain_routing() {
  config="/etc/vpsm-domain-router/domains.conf"
  log="/var/log/vpsm-domain-router-dns.log"
  [ -f "$config" ] || return 0

  dns_state="$(systemctl is-active vpsm-domain-dns.service 2>/dev/null || true)"
  route_state="$(systemctl is-active vpsm-domain-route.service 2>/dev/null || true)"
  if [ "$route_state" != "active" ] &&
     ipset list vpsm_wgexit4 >/dev/null 2>&1 &&
     ip rule show 2>/dev/null | grep -q 'fwmark 0x194' &&
     ip route show table 194 2>/dev/null | grep -q '^default '; then
    route_state="active"
  fi
  routed_count="$(ipset list vpsm_wgexit4 2>/dev/null | awk -F: '/Number of entries:/ {gsub(/ /, "", $2); print $2}' | head -n 1)"
  [ -n "$routed_count" ] || routed_count=0

  emit DOMAINROUTE "$(b64 "$dns_state")" "$(b64 "$route_state")" "$routed_count" "$(b64 "$config")" "$(b64 "$log")"

  whitelist_tmp="$(mktemp)"
  sed -n 's#^[[:space:]]*ipset=/\([^/][^/]*\)/vpsm_wgexit4[[:space:]]*$#\1#p' "$config" |
    awk 'NF {print tolower($0)}' |
    sort -u > "$whitelist_tmp"

  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    emit DOMAINWHITELIST "$(b64 "$domain")"
  done < "$whitelist_tmp"

  if [ -f "$log" ]; then
    tail -n 2500 "$log" 2>/dev/null |
      awk '
        /query\[[A-Z0-9]+\]/ {
          domain="";
          for (i=1; i<=NF; i++) {
            if ($i ~ /^query\[[A-Z0-9]+\]$/ && (i + 1) <= NF) {
              domain=$(i + 1);
            }
          }
          if (domain == "") next;
          gsub(/\.$/, "", domain);
          domain=tolower(domain);
          if (domain ~ /^[0-9.]+$/) next;
          if (domain ~ /(in-addr|ip6)\.arpa$/) next;
          counts[domain]++;
          last[domain]=$1 " " $2 " " $3;
        }
        END {
          for (domain in counts) print counts[domain] "|" last[domain] "|" domain;
        }' |
      sort -t'|' -k1,1nr -k3,3 |
      head -n 80 |
      while IFS='|' read -r count last domain; do
        [ -n "$domain" ] || continue
        if ! grep -Fxq "$domain" "$whitelist_tmp"; then
          emit DOMAINCANDIDATE "$(b64 "$domain")" "${count:-0}" "$(b64 "$last")"
        fi
      done
  fi

  rm -f "$whitelist_tmp"
}

detect_domain_routing

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

# Detect app processes that are not represented as systemd services.
# This catches bots launched via cron, pm2, screen/tmux, docker wrappers or a plain shell.
for procdir in /proc/[0-9]*; do
  [ -d "$procdir" ] || continue
  pid="${procdir##*/}"
  cwd="$(readlink "$procdir/cwd" 2>/dev/null || true)"
  [ -n "$cwd" ] || continue
  case "$cwd" in
    /opt/*|/var/www/*|/srv/*|/app/*|/apps/*|/web/*|/www/*|/websites/*|/sites/*|/projects/*|/data/*|/storage/*|/docker/*|/containers/*|/root/*|/home/*/*) ;;
    *) continue ;;
  esac
  comm="$(tr -d '\0' < "$procdir/comm" 2>/dev/null || true)"
  cmdline="$(tr '\0' ' ' < "$procdir/cmdline" 2>/dev/null | cut -c 1-120 || true)"
  [ -n "$comm" ] || comm="pid-$pid"
  [ -n "$cmdline" ] || cmdline="$comm"
  _ps="$(ps -p "$pid" -o %cpu= -o rss= 2>/dev/null || true)"
  cpu_x100=0; mem_kb=0
  if [ -n "$_ps" ]; then
    cpu_x100="$(printf '%s\n' "$_ps" | awk '{printf "%d", $1 * 100 + 0.5}')"
    mem_kb="$(printf '%s\n' "$_ps"   | awk '{print int($2)}')"
  fi
  emit SERVICE "$(b64 "process:$comm:$pid")" "$(b64 "Running process: $cmdline")" \
    "$(b64 active)" "$(b64 running)" "$(b64 "$cwd")" "$(b64 process)" \
    "0" "${cpu_x100:-0}" "${mem_kb:-0}"
done
"""#
}

public enum SSHInventoryError: LocalizedError {
    case connectionFailed(String)
    case noPasswordStored

    public var requiresPassword: Bool {
        guard case .connectionFailed(let message) = self else { return false }
        let lowercased = message.lowercased()
        return lowercased.contains("permission denied (")
            && (lowercased.contains("password") || lowercased.contains("keyboard-interactive"))
    }

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
