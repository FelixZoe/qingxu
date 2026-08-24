import Foundation

enum QingxuPreferenceKey {
  static let pomodoroModule = "qingxu.modules.pomodoro"
  static let rssModule = "qingxu.modules.rss"
  static let inboxModule = "qingxu.modules.inbox"
  static let haptics = "qingxu.feedback.haptics"
  static let completionSound = "qingxu.feedback.completionSound"
  static let dailyReminder = "qingxu.reminders.daily.enabled"
  static let dailyReminderMinutes = "qingxu.reminders.daily.minutes"
  static let weekStartsMonday = "qingxu.calendar.weekStartsMonday"
  static let showFestivals = "qingxu.calendar.showFestivals"
  static let showTaskIndicators = "qingxu.calendar.showTaskIndicators"
}

#if os(iOS)
import AudioToolbox
import UIKit
import UserNotifications

enum QingxuFeedback {
  static func selection(enabled: Bool) {
    guard enabled else { return }
    UISelectionFeedbackGenerator().selectionChanged()
  }

  static func taskCompletion(haptics: Bool, sound: Bool) {
    if haptics {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    if sound {
      AudioServicesPlaySystemSound(1104)
    }
  }
}

enum QingxuDailyReminder {
  static let identifier = "qingxu.daily-reminder"

  static func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  @discardableResult
  static func update(enabled: Bool, minutesAfterMidnight: Int) async throws -> Bool {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard enabled else { return true }

    let settings = await center.notificationSettings()
    var authorized = settings.authorizationStatus == .authorized
      || settings.authorizationStatus == .provisional
    if settings.authorizationStatus == .notDetermined {
      authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    guard authorized else { return false }

    let normalized = min(23 * 60 + 59, max(0, minutesAfterMidnight))
    var components = DateComponents()
    components.hour = normalized / 60
    components.minute = normalized % 60

    let content = UNMutableNotificationContent()
    content.title = "清序"
    content.body = "看一眼今天的安排，轻松开始。"
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    )
    try await center.add(request)
    return true
  }
}
#endif
