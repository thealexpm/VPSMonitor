import Foundation
import UserNotifications

public enum NotificationService {
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func sendServerDown(serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = "VPS недоступен"
        content.body = "\(serverName) не отвечает"
        content.sound = .default
        deliver(content, id: "server-down-\(serverName)")
    }

    public static func sendServerRestored(serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = "VPS снова доступен"
        content.body = "\(serverName) отвечает"
        content.sound = .default
        deliver(content, id: "server-restored-\(serverName)")
    }

    public static func sendServiceStopped(serviceName: String, serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Служба остановлена"
        content.body = "\(serviceName) на \(serverName)"
        content.sound = .default
        deliver(content, id: "service-stopped-\(serverName)-\(serviceName)")
    }

    private static func deliver(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
