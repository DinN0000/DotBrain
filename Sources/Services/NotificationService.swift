import Foundation
import UserNotifications

/// macOS notification service
enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    static func sendProcessingComplete(classified: Int, total: Int, failed: Int) {
        var body = "\(classified)/\(total)개 파일 분류 완료"
        if failed > 0 {
            body += " (\(failed)개 실패)"
        }
        send(title: "AI-PKM 인박스 정리", body: body)
    }
}
