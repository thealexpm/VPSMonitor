import Foundation

public enum MonitorFormatters {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public static func duration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return L10n.text("\(days) дн. \(hours) ч.", "\(days)d \(hours)h")
        }
        let minutes = (seconds % 3_600) / 60
        return L10n.text("\(hours) ч. \(minutes) мин.", "\(hours)h \(minutes)m")
    }

    public static func milliseconds(_ interval: TimeInterval) -> String {
        L10n.text("\(Int(interval * 1_000)) мс", "\(Int(interval * 1_000)) ms")
    }
}
