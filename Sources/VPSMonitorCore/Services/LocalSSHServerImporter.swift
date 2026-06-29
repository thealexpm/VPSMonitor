import Foundation

public struct LocalSSHServerImporter {
    private struct Candidate {
        var name: String
        var host: String
        var user: String?
        var rank: Int
    }

    private let homeDirectory: URL
    private let includeShellHistory: Bool

    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        includeShellHistory: Bool = true
    ) {
        self.homeDirectory = homeDirectory
        self.includeShellHistory = includeShellHistory
    }

    public func importConfigurations() -> [MonitorConfiguration] {
        var candidates: [Candidate] = []
        candidates.append(contentsOf: sshConfigCandidates())
        if includeShellHistory {
            candidates.append(contentsOf: shellHistoryCandidates())
        }
        candidates.append(contentsOf: knownHostsCandidates())

        var candidatesByHost: [String: Candidate] = [:]
        for candidate in candidates {
            let host = candidate.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, !Self.shouldSkip(host: host) else { continue }
            let key = host.lowercased()
            if let existing = candidatesByHost[key] {
                candidatesByHost[key] = Self.merge(existing, candidate)
            } else {
                candidatesByHost[key] = candidate
            }
        }

        return candidatesByHost.values
            .sorted {
                if $0.rank != $1.rank { return $0.rank > $1.rank }
                return $0.host.localizedStandardCompare($1.host) == .orderedAscending
            }
            .map {
                MonitorConfiguration(
                    name: $0.name,
                    host: $0.host,
                    user: $0.user ?? "root",
                    refreshInterval: 30,
                    authMethod: .sshKey
                )
            }
    }

    private func sshConfigCandidates() -> [Candidate] {
        parseSSHConfig(at: homeDirectory.appendingPathComponent(".ssh/config"))
    }

    private func parseSSHConfig(at url: URL, visited: Set<URL> = []) -> [Candidate] {
        guard !visited.contains(url),
              let content = Self.readTextFile(at: url)
        else { return [] }

        var output: [Candidate] = []
        var currentHosts: [String] = []
        var currentUser: String?
        var currentHostName: String?

        func flushCurrentBlock() {
            for alias in currentHosts where Self.isConcreteSSHConfigHost(alias) {
                let name = alias
                // Keep the alias as host so SSH still honors Port, IdentityFile, ProxyJump, and other config.
                output.append(Candidate(
                    name: name,
                    host: alias,
                    user: currentUser,
                    rank: currentHostName == nil ? 90 : 95
                ))
            }
            currentHosts = []
            currentUser = nil
            currentHostName = nil
        }

        let directory = url.deletingLastPathComponent()
        for rawLine in content.components(separatedBy: .newlines) {
            let line = Self.stripComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let keyword = parts.first?.lowercased() else { continue }
            let values = Array(parts.dropFirst())

            switch keyword {
            case "include":
                flushCurrentBlock()
                for includePath in values {
                    let urls = Self.expandIncludePath(
                        includePath,
                        relativeTo: directory,
                        homeDirectory: homeDirectory
                    )
                    for includeURL in urls {
                        output.append(contentsOf: parseSSHConfig(at: includeURL, visited: visited.union([url])))
                    }
                }
            case "host":
                flushCurrentBlock()
                currentHosts = values
            case "user":
                currentUser = values.first?.nilIfEmpty
            case "hostname":
                currentHostName = values.first?.nilIfEmpty
            default:
                continue
            }
        }
        flushCurrentBlock()
        return output
    }

    private func shellHistoryCandidates() -> [Candidate] {
        [".zsh_history", ".bash_history", ".history"].flatMap { filename -> [Candidate] in
            let url = homeDirectory.appendingPathComponent(filename)
            guard let content = Self.readTextFile(at: url) else { return [] }
            return content.components(separatedBy: .newlines).flatMap(Self.parseHistoryLine)
        }
    }

    private func knownHostsCandidates() -> [Candidate] {
        [".ssh/known_hosts", ".ssh/known_hosts.old"].flatMap { path -> [Candidate] in
            let url = homeDirectory.appendingPathComponent(path)
            guard let content = Self.readTextFile(at: url) else { return [] }
            return content.components(separatedBy: .newlines).flatMap(Self.parseKnownHostsLine)
        }
    }

    private static func merge(_ lhs: Candidate, _ rhs: Candidate) -> Candidate {
        Candidate(
            name: lhs.rank >= rhs.rank ? lhs.name : rhs.name,
            host: lhs.host,
            user: lhs.user ?? rhs.user,
            rank: max(lhs.rank, rhs.rank)
        )
    }

    private static func parseHistoryLine(_ rawLine: String) -> [Candidate] {
        let line: String
        if rawLine.hasPrefix(": "), let semicolon = rawLine.firstIndex(of: ";") {
            line = String(rawLine[rawLine.index(after: semicolon)...])
        } else {
            line = rawLine
        }

        let tokens = tokenize(line)
        guard !tokens.isEmpty else { return [] }

        var candidates: [Candidate] = []
        for index in tokens.indices {
            let command = (tokens[index] as NSString).lastPathComponent
            switch command {
            case "ssh":
                if let candidate = parseSSHCommand(Array(tokens[(index + 1)...])) {
                    candidates.append(candidate)
                }
            case "scp", "sftp", "rsync":
                candidates.append(contentsOf: parseRemoteFileCommand(Array(tokens[(index + 1)...])))
            default:
                continue
            }
        }
        return candidates
    }

    private static func parseSSHCommand(_ tokens: [String]) -> Candidate? {
        var explicitUser: String?
        var skipNext = false
        var nextTokenIsOption = false
        var nextTokenIsUser = false
        var hasCustomPort = false
        let optionsWithSeparateValue: Set<String> = [
            "-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L",
            "-l", "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w"
        ]

        for token in tokens {
            if nextTokenIsUser {
                explicitUser = token.nilIfEmpty
                nextTokenIsUser = false
                continue
            }
            if nextTokenIsOption {
                if isPortOption(token) {
                    hasCustomPort = true
                }
                nextTokenIsOption = false
                continue
            }
            if skipNext {
                skipNext = false
                continue
            }
            if token == "--" { continue }
            if token == "-l" {
                nextTokenIsUser = true
                continue
            }
            if token.hasPrefix("-l"), token.count > 2 {
                explicitUser = String(token.dropFirst(2))
                continue
            }
            if token == "-p" {
                hasCustomPort = true
                skipNext = true
                continue
            }
            if token.hasPrefix("-p"), token.count > 2 {
                hasCustomPort = true
                continue
            }
            if token == "-o" {
                nextTokenIsOption = true
                continue
            }
            if token.hasPrefix("-o"), isPortOption(String(token.dropFirst(2))) {
                hasCustomPort = true
                continue
            }
            if optionsWithSeparateValue.contains(token) {
                skipNext = true
                continue
            }
            if token.hasPrefix("-") {
                continue
            }
            guard !hasCustomPort,
                  let target = parseRemoteTarget(token, fallbackUser: explicitUser)
            else { continue }
            return Candidate(name: target.host, host: target.host, user: target.user, rank: 100)
        }
        return nil
    }

    private static func parseRemoteFileCommand(_ tokens: [String]) -> [Candidate] {
        var candidates: [Candidate] = []
        var skipNext = false
        var nextTokenIsOption = false
        var hasCustomPort = false
        let optionsWithSeparateValue: Set<String> = ["-i", "-P", "-p", "-o", "-F", "-J", "-S", "-e"]

        for token in tokens {
            if nextTokenIsOption {
                if isPortOption(token) {
                    hasCustomPort = true
                }
                nextTokenIsOption = false
                continue
            }
            if skipNext {
                skipNext = false
                continue
            }
            if token == "-P" || token == "-p" {
                hasCustomPort = true
                skipNext = true
                continue
            }
            if token == "-o" {
                nextTokenIsOption = true
                continue
            }
            if token.hasPrefix("-o"), isPortOption(String(token.dropFirst(2))) {
                hasCustomPort = true
                continue
            }
            if optionsWithSeparateValue.contains(token) {
                skipNext = true
                continue
            }
            if token.hasPrefix("-") { continue }
            guard !hasCustomPort,
                  let target = parseRemoteTarget(token, fallbackUser: nil)
            else { continue }
            candidates.append(Candidate(name: target.host, host: target.host, user: target.user, rank: 80))
        }
        return candidates
    }

    private static func parseRemoteTarget(_ token: String, fallbackUser: String?) -> (user: String?, host: String)? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let remotePart = remoteIdentifier(from: cleaned)
        guard !remotePart.isEmpty, !remotePart.contains("/") else { return nil }

        if let at = remotePart.lastIndex(of: "@") {
            let user = String(remotePart[..<at])
            let host = String(remotePart[remotePart.index(after: at)...])
            guard !host.isEmpty,
                  let parsedHost = stripBracketedPort(from: host)?.host
            else { return nil }
            return (user.nilIfEmpty, parsedHost)
        }

        guard let parsedHost = stripBracketedPort(from: remotePart)?.host else { return nil }
        return (fallbackUser, parsedHost)
    }

    private static func remoteIdentifier(from token: String) -> String {
        if let at = token.lastIndex(of: "@") {
            let userPart = token[..<at]
            let hostAndMaybePath = token[token.index(after: at)...]
            if hostAndMaybePath.hasPrefix("["),
               let closing = hostAndMaybePath.firstIndex(of: "]") {
                return "\(userPart)@\(hostAndMaybePath[...closing])"
            }
        } else if token.hasPrefix("["),
                  let closing = token.firstIndex(of: "]") {
            return String(token[...closing])
        }

        return token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? token
    }

    private static func isPortOption(_ option: String) -> Bool {
        option.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("port=")
    }

    private static func parseKnownHostsLine(_ rawLine: String) -> [Candidate] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return [] }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !fields.isEmpty else { return [] }

        let hostField: String
        if fields[0].hasPrefix("@") {
            guard fields.count > 1 else { return [] }
            hostField = fields[1]
        } else {
            hostField = fields[0]
        }

        return hostField
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.hasPrefix("|1|") }
            .compactMap(stripBracketedPort)
            .filter { !$0.hasCustomPort }
            .map(\.host)
            .filter(isIPAddress)
            .map { Candidate(name: $0, host: $0, user: nil, rank: 40) }
    }

    private static func stripComment(_ line: String) -> String {
        guard let hash = line.firstIndex(of: "#") else { return line }
        return String(line[..<hash])
    }

    private static func readTextFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in command {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character == " " || character == "\t" || character == ";" || character == "&" || character == "|" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func expandIncludePath(_ path: String, relativeTo directory: URL, homeDirectory: URL) -> [URL] {
        let expandedPath: String
        if path == "~" {
            expandedPath = homeDirectory.path
        } else if path.hasPrefix("~/") {
            expandedPath = homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
        } else {
            expandedPath = path
        }

        let url = expandedPath.hasPrefix("/")
            ? URL(fileURLWithPath: expandedPath)
            : directory.appendingPathComponent(expandedPath)

        guard expandedPath.contains("*") || expandedPath.contains("?") else { return [url] }
        let directoryURL = url.deletingLastPathComponent()
        let pattern = url.lastPathComponent
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items.filter { wildcard(pattern, matches: $0.lastPathComponent) }
    }

    private static func isConcreteSSHConfigHost(_ host: String) -> Bool {
        !host.isEmpty &&
        !host.contains("*") &&
        !host.contains("?") &&
        !host.hasPrefix("!")
    }

    private static func shouldSkip(host: String) -> Bool {
        let lowercased = host.lowercased()
        let skippedHosts: Set<String> = [
            "github.com", "gist.github.com", "gitlab.com", "bitbucket.org",
            "ssh.github.com", "vs-ssh.visualstudio.com", "localhost",
            "127.0.0.1", "::1"
        ]
        return skippedHosts.contains(lowercased) || lowercased.hasPrefix("localhost.")
    }

    private static func isIPAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4,
           parts.allSatisfy({ !$0.isEmpty && Int($0).map { (0...255).contains($0) } == true }) {
            return true
        }
        return host.contains(":")
    }

    private static func stripBracketedPort(from host: String) -> (host: String, hasCustomPort: Bool)? {
        guard host.hasPrefix("["),
              let closing = host.firstIndex(of: "]")
        else { return (host, false) }
        let unbracketed = String(host[host.index(after: host.startIndex)..<closing])
        let suffix = host[host.index(after: closing)...]
        return (unbracketed, suffix.hasPrefix(":"))
    }

    private static func wildcard(_ pattern: String, matches value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
