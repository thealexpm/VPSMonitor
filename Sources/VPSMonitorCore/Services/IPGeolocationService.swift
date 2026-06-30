import Foundation

public struct IPGeolocationService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func countryCode(for host: String) async -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !isPrivateHost(trimmed),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://ipinfo.io/\(encoded)/country") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return ServerPresentation.normalizedCountryCode(text)
        } catch {
            return nil
        }
    }

    private func isPrivateHost(_ host: String) -> Bool {
        host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("172.16.")
    }
}
