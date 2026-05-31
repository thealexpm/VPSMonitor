import Foundation

public enum MonitorFormatters {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public static func duration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "\(days) дн. \(hours) ч."
        }
        let minutes = (seconds % 3_600) / 60
        return "\(hours) ч. \(minutes) мин."
    }

    public static func milliseconds(_ interval: TimeInterval) -> String {
        "\(Int(interval * 1_000)) мс"
    }
}
