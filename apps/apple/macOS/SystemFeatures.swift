import Foundation
import WidgetKit

enum SystemFeatures {
  private static let suiteName = "group.one.darker.qingxu"

  static func refresh(
    pomodoro: PomodoroState,
    todayTaskCount: Int,
    nextTodayTaskTitle: String?,
    todayTaskTitles: [String]
  ) {
    guard let defaults = UserDefaults(suiteName: suiteName) else { return }
    let now = Date()
    defaults.set(todayTaskCount, forKey: "todayTaskCount")
    defaults.set(nextTodayTaskTitle, forKey: "nextTodayTaskTitle")
    defaults.set(todayTaskTitles, forKey: "todayTaskTitles")
    defaults.set(pomodoro.mode.rawValue, forKey: "pomodoroMode")
    defaults.set(pomodoro.status.rawValue, forKey: "pomodoroStatus")
    defaults.set(pomodoro.timerDirection.rawValue, forKey: "pomodoroDirection")
    defaults.set(pomodoro.remaining(at: now), forKey: "pomodoroRemaining")
    defaults.set(pomodoro.endsAt, forKey: "pomodoroEndsAt")
    defaults.set(pomodoro.startedAt, forKey: "pomodoroStartedAt")
    defaults.set(pomodoro.dailyFocusGoal, forKey: "dailyFocusGoal")
    defaults.set(pomodoro.completedFocusCount(on: now), forKey: "dailyFocusCompleted")

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    var heatmap: [String: Int] = [:]
    for record in pomodoro.focusHistory where record.completed {
      let key = formatter.string(from: record.endedAt)
      heatmap[key, default: 0] += record.durationSeconds
    }
    if let data = try? JSONEncoder().encode(heatmap) {
      defaults.set(data, forKey: "focusHeatmap")
    }
    defaults.set(now, forKey: "widgetSnapshotUpdatedAt")
    WidgetCenter.shared.reloadAllTimelines()
  }
}
