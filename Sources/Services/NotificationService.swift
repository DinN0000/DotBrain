import Foundation
import AppKit

/// macOS notification service using NSUserNotification fallback for non-bundled apps
enum NotificationService {
    static func sendProcessingComplete(classified: Int, total: Int, failed: Int) {
        var body = "\(classified)/\(total)개 파일 분류 완료"
        if failed > 0 {
            body += " (\(failed)개 실패)"
        }
        send(title: "DotBrain 인박스 정리", body: body)
    }

    static func send(title: String, body: String) {
        // Use NSSound for audio feedback
        NSSound.beep()

        // Try UserNotifications if available, otherwise silently skip
        // SPM executables without a proper .app bundle can't use UNUserNotificationCenter
        // so we just log to stdout as fallback
        NSLog("[%@] %@", title, body)
    }
}
