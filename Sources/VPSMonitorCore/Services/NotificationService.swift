import Foundation
import UserNotifications

public enum NotificationService {
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func sendServerDown(serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("VPS недоступен", "VPS unavailable")
        content.body = L10n.text("\(serverName) не отвечает", "\(serverName) is not responding")
        content.sound = .default
        deliver(content, id: "server-down-\(serverName)")
    }

    public static func sendServerRestored(serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("VPS снова доступен", "VPS available again")
        content.body = L10n.text("\(serverName) отвечает", "\(serverName) is responding")
        content.sound = .default
        deliver(content, id: "server-restored-\(serverName)")
    }

    public static func sendServiceStopped(serviceName: String, serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("Служба остановлена", "Service stopped")
        content.body = L10n.text("\(serviceName) на \(serverName)", "\(serviceName) on \(serverName)")
        content.sound = .default
        deliver(content, id: "service-stopped-\(serverName)-\(serviceName)")
    }

    private static func deliver(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
