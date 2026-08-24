import ActivityKit
import Foundation
import OSLog
import WidgetKit

enum SystemFeatures {
  private static let appGroup = "group.one.darker.qingxu"
  private static let logger = Logger(
    subsystem: "one.darker.qingxu",
    category: "LiveActivity"
  )

  static func refresh(pomodoro: PomodoroState, todayTaskCount: Int, nextTodayTaskTitle: String?) {
    let defaults = UserDefaults(suiteName: appGroup)
    defaults?.set(todayTaskCount, forKey: "todayTaskCount")
    defaults?.set(nextTodayTaskTitle, forKey: "nextTodayTaskTitle")
    defaults?.set(pomodoro.mode.rawValue, forKey: "pomodoroMode")
    defaults?.set(pomodoro.status.rawValue, forKey: "pomodoroStatus")
    defaults?.set(pomodoro.remaining(at: .now), forKey: "pomodoroRemainingSeconds")
    defaults?.set(pomodoro.endsAt, forKey: "pomodoroEndsAt")
    WidgetCenter.shared.reloadAllTimelines()
    updateLiveActivity(pomodoro)
  }

  @available(iOS 16.2, *)
  private static func content(_ pomodoro: PomodoroState) -> ActivityContent<QingxuPomodoroAttributes.ContentState> {
    ActivityContent(
      state: .init(
        mode: pomodoro.mode.rawValue,
        status: pomodoro.status.rawValue,
        endsAt: pomodoro.endsAt,
        remainingSeconds: pomodoro.remaining(at: .now)
      ),
      staleDate: pomodoro.endsAt
    )
  }

  private static func updateLiveActivity(_ pomodoro: PomodoroState) {
    guard #available(iOS 16.2, *) else { return }
    Task(priority: .userInitiated) {
      let activities = Activity<QingxuPomodoroAttributes>.activities
      if pomodoro.status == .running {
        if let activity = activities.first {
          await activity.update(content(pomodoro))
          for duplicate in activities.dropFirst() {
            await duplicate.end(content(pomodoro), dismissalPolicy: .immediate)
          }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
          do {
            _ = try Activity.request(
              attributes: QingxuPomodoroAttributes(title: "清序专注"),
              content: content(pomodoro),
              pushType: nil
            )
          } catch {
            logger.error("Unable to start Live Activity: \(error.localizedDescription, privacy: .public)")
          }
        }
      } else {
        for activity in activities {
          await activity.end(content(pomodoro), dismissalPolicy: .immediate)
        }
      }
    }
  }
}
