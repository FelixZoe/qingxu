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
  private static let liveActivityStatusKey = "qingxu.liveActivity.status"

  static func refresh(
    pomodoro: PomodoroState,
    todayTaskCount: Int,
    nextTodayTaskTitle: String?,
    todayTaskTitles: [String]
  ) {
    let defaults = UserDefaults(suiteName: appGroup)
    defaults?.set(todayTaskCount, forKey: "todayTaskCount")
    defaults?.set(nextTodayTaskTitle, forKey: "nextTodayTaskTitle")
    defaults?.set(Array(todayTaskTitles.prefix(3)), forKey: "todayTaskTitles")
    defaults?.set(pomodoro.mode.rawValue, forKey: "pomodoroMode")
    defaults?.set(pomodoro.status.rawValue, forKey: "pomodoroStatus")
    defaults?.set(pomodoro.timerDirection.rawValue, forKey: "pomodoroTimerDirection")
    defaults?.set(pomodoro.remaining(at: .now), forKey: "pomodoroRemainingSeconds")
    defaults?.set(pomodoro.dailyFocusGoal, forKey: "pomodoroDailyGoal")
    defaults?.set(pomodoro.completedFocusCount(), forKey: "pomodoroTodayCompleted")
    defaults?.set(pomodoro.endsAt, forKey: "pomodoroEndsAt")
    let countUpDisplayStart = pomodoro.startedAt?.addingTimeInterval(
      TimeInterval(-pomodoro.remainingSeconds)
    )
    defaults?.set(countUpDisplayStart, forKey: "pomodoroStartedAt")
    WidgetCenter.shared.reloadAllTimelines()
    updateLiveActivity(pomodoro)
  }

  @available(iOS 16.2, *)
  private static func content(_ pomodoro: PomodoroState) -> ActivityContent<QingxuPomodoroAttributes.ContentState> {
    let countUpDisplayStart = pomodoro.startedAt?.addingTimeInterval(
      TimeInterval(-pomodoro.remainingSeconds)
    )
    return ActivityContent(
      state: QingxuPomodoroAttributes.ContentState(
        mode: pomodoro.mode.rawValue,
        status: pomodoro.status.rawValue,
        timerDirection: pomodoro.timerDirection.rawValue,
        phaseID: pomodoro.phaseID,
        endsAt: pomodoro.endsAt,
        startedAt: countUpDisplayStart,
        remainingSeconds: pomodoro.remaining(at: .now),
        totalSeconds: pomodoro.duration(for: pomodoro.mode),
        todayCompleted: pomodoro.completedFocusCount(),
        dailyGoal: pomodoro.dailyFocusGoal,
        focusHeatmap: focusHeatmap(pomodoro)
      ),
      staleDate: pomodoro.endsAt
    )
  }

  private static func focusHeatmap(_ pomodoro: PomodoroState, weeks: Int = 18) -> [Int] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.timeZone = .autoupdatingCurrent
    let today = calendar.startOfDay(for: .now)
    let dayCount = weeks * 7
    let firstDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

    return (0..<dayCount).map { offset in
      let date = calendar.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
      let seconds = pomodoro.focusHistory
        .filter { $0.completed && calendar.isDate($0.endedAt, inSameDayAs: date) }
        .reduce(0) { $0 + $1.durationSeconds }
      switch seconds {
      case 0: 0
      case 1..<(25 * 60): 1
      case (25 * 60)..<(60 * 60): 2
      case (60 * 60)..<(120 * 60): 3
      default: 4
      }
    }
  }

  private static func updateLiveActivity(_ pomodoro: PomodoroState) {
    guard #available(iOS 16.2, *) else { return }
    Task(priority: .userInitiated) {
      if pomodoro.status == .running {
        _ = await startOrUpdateLiveActivity(pomodoro)
      } else {
        for activity in Activity<QingxuPomodoroAttributes>.activities {
          await activity.end(content(pomodoro), dismissalPolicy: .immediate)
        }
        setLiveActivityStatus("番茄钟尚未开始")
      }
    }
  }

  @available(iOS 16.2, *)
  private static func startOrUpdateLiveActivity(_ pomodoro: PomodoroState) async -> String {
    let activities = Activity<QingxuPomodoroAttributes>.activities
    if let activity = activities.first {
      await activity.update(content(pomodoro))
      for duplicate in activities.dropFirst() {
        await duplicate.end(content(pomodoro), dismissalPolicy: .immediate)
      }
      let message = "实时活动正在运行"
      setLiveActivityStatus(message)
      return message
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      let message = "系统未允许实时活动，请在“设置 > 清序 > 实时活动”中开启"
      setLiveActivityStatus(message)
      logger.notice("Live Activities are disabled by the system")
      return message
    }

    do {
      let activity = try Activity.request(
        attributes: QingxuPomodoroAttributes(title: "清序专注"),
        content: content(pomodoro),
        pushType: nil
      )
      let message = "实时活动已启动（\(activity.id.prefix(8))）"
      setLiveActivityStatus(message)
      return message
    } catch {
      let message = "实时活动启动失败：\(error.localizedDescription)"
      setLiveActivityStatus(message)
      logger.error("Unable to start Live Activity: \(error.localizedDescription, privacy: .public)")
      return message
    }
  }

  static func restartLiveActivity(for pomodoro: PomodoroState) async -> String {
    guard #available(iOS 16.2, *) else { return "需要 iOS 16.2 或更高版本" }
    for activity in Activity<QingxuPomodoroAttributes>.activities {
      await activity.end(content(pomodoro), dismissalPolicy: .immediate)
    }
    guard pomodoro.status == .running else {
      let message = "请先启动番茄钟，再测试灵动岛"
      setLiveActivityStatus(message)
      return message
    }
    try? await Task.sleep(for: .milliseconds(250))
    return await startOrUpdateLiveActivity(pomodoro)
  }

  static var liveActivityStatus: String {
    UserDefaults.standard.string(forKey: liveActivityStatusKey) ?? "尚未检测"
  }

  private static func setLiveActivityStatus(_ value: String) {
    UserDefaults.standard.set(value, forKey: liveActivityStatusKey)
  }
}
