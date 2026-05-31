import Foundation

public struct AvailableUpdate: Equatable, Sendable {
    public let version: String          // e.g. "1.2"
    public let releaseURL: URL          // page on GitHub
    public let assetSizeBytes: Int64?   // size of first .dmg / .zip / .app.zip asset
    public let releaseNotes: String
}

@MainActor
public final class UpdateChecker: ObservableObject {
    @Published public private(set) var availableUpdate: AvailableUpdate?
    @Published public private(set) var isChecking = false

    private let owner: String
    private let repo: String
    private let currentVersion: String

    public init(owner: String = "thealexpm",
                repo: String = "VPSMonitor",
                currentVersion: String = UpdateChecker.bundleVersion()) {
        self.owner = owner
        self.repo = repo
        self.currentVersion = currentVersion
    }

    public static func bundleVersion() -> String {
        // CFBundleShortVersionString from Info.plist
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Check

    public func checkInBackground() {
        Task { await check() }
    }

    public func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            if isNewer(remote: release.tagVersion, than: currentVersion) {
                availableUpdate = AvailableUpdate(
                    version: release.tagVersion,
                    releaseURL: release.htmlURL,
                    assetSizeBytes: release.firstBinaryAssetSize,
                    releaseNotes: release.body ?? ""
                )
            } else {
                availableUpdate = nil
            }
        } catch {
            // Silently fail — no internet, rate limit, no releases yet, etc.
            availableUpdate = nil
        }
    }

    public func dismiss() {
        availableUpdate = nil
    }

    // MARK: - Networking

    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [GHAsset]
        let draft: Bool
        let prerelease: Bool

        var tagVersion: String {
            // Strip leading "v" if present: "v1.2" → "1.2"
            tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
        }

        var htmlURL: URL {
            URL(string: html_url) ?? URL(string: "https://github.com")!
        }

        /// Size of the first binary-ish asset (.dmg/.zip)
        var firstBinaryAssetSize: Int64? {
            let binary = assets.first { a in
                let n = a.name.lowercased()
                return n.hasSuffix(".dmg") || n.hasSuffix(".zip") || n.hasSuffix(".pkg")
            }
            return binary.map { Int64($0.size) }
        }
    }

    private struct GHAsset: Decodable {
        let name: String
        let size: Int
    }

    private func fetchLatestRelease() async throws -> GHRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(GHRelease.self, from: data)
        guard !release.draft, !release.prerelease else { throw URLError(.cannotParseResponse) }
        return release
    }

    // MARK: - Version comparison

    /// Compares semantic-like version strings ("1.2", "1.2.3", "v1.0").
    /// Returns true when `remote` > `local`.
    private func isNewer(remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").compactMap { Int($0) }
        }
        let r = parts(remote), l = parts(local)
        let count = max(r.count, l.count)
        for i in 0..<count {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
