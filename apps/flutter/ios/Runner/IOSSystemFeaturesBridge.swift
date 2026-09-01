import ActivityKit
import Flutter
import Foundation
import WidgetKit

final class IOSSystemFeaturesBridge {
  private static let appGroup = "group.one.darker.qingxu"
  private var channel: FlutterMethodChannel?

  func connect(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "one.darker.qingxu/system-features",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "updateSnapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let payload = call.arguments as? [String: Any],
        let pomodoro = payload["pomodoro"] as? [String: Any]
      else {
        result(FlutterError(code: "invalid_snapshot", message: "Missing pomodoro snapshot.", details: nil))
        return
      }
      self?.update(
        pomodoro: pomodoro,
        todayTaskCount: payload["todayTaskCount"] as? Int ?? 0,
        todayTaskTitles: payload["todayTaskTitles"] as? [String] ?? []
      )
      result(nil)
    }
    self.channel = channel
  }

  private func update(
    pomodoro: [String: Any],
    todayTaskCount: Int,
    todayTaskTitles: [String]
  ) {
    let mode = pomodoro["mode"] as? String ?? "focus"
    let status = pomodoro["status"] as? String ?? "idle"
    let timerDirection = pomodoro["timerDirection"] as? String ?? "countdown"
    let remainingSeconds = pomodoro["remainingSeconds"] as? Int ?? 25 * 60
    let phaseID = pomodoro["phaseID"] as? String ?? "\(mode)-\(pomodoro["updatedAt"] as? String ?? "legacy")"
    let dailyGoal = pomodoro["dailyFocusGoal"] as? Int ?? 4
    let totalSeconds: Int
    switch mode {
    case "shortBreak": totalSeconds = (pomodoro["shortBreakMinutes"] as? Int ?? 5) * 60
    case "longBreak": totalSeconds = (pomodoro["longBreakMinutes"] as? Int ?? 15) * 60
    default: totalSeconds = (pomodoro["focusMinutes"] as? Int ?? 25) * 60
    }
    let calendar = Calendar.autoupdatingCurrent
    let todayCompleted = (pomodoro["focusHistory"] as? [[String: Any]] ?? []).filter { record in
      guard record["completed"] as? Bool == true,
            let value = record["endedAt"] as? String,
            let date = ISO8601DateFormatter().date(from: value) else { return false }
      return calendar.isDateInToday(date)
    }.count
    let endsAt = (pomodoro["endsAt"] as? String).flatMap(ISO8601DateFormatter().date)
    let startedAt = (pomodoro["startedAt"] as? String).flatMap(ISO8601DateFormatter().date)
    let displayStartedAt = startedAt?.addingTimeInterval(TimeInterval(-remainingSeconds))

    if let defaults = UserDefaults(suiteName: Self.appGroup) {
      defaults.set(todayTaskCount, forKey: "todayTaskCount")
      defaults.set(Array(todayTaskTitles.prefix(3)), forKey: "todayTaskTitles")
      defaults.set(mode, forKey: "pomodoroMode")
      defaults.set(status, forKey: "pomodoroStatus")
      defaults.set(timerDirection, forKey: "pomodoroTimerDirection")
      defaults.set(remainingSeconds, forKey: "pomodoroRemainingSeconds")
      defaults.set(dailyGoal, forKey: "pomodoroDailyGoal")
      defaults.set(todayCompleted, forKey: "pomodoroTodayCompleted")
      defaults.set(endsAt, forKey: "pomodoroEndsAt")
      defaults.set(displayStartedAt, forKey: "pomodoroStartedAt")
    }
    WidgetCenter.shared.reloadAllTimelines()

    guard #available(iOS 16.2, *) else { return }
    let state = QingxuPomodoroAttributes.ContentState(
      mode: mode,
      status: status,
      timerDirection: timerDirection,
      phaseID: phaseID,
      endsAt: endsAt,
      startedAt: displayStartedAt,
      remainingSeconds: remainingSeconds,
      totalSeconds: totalSeconds,
      todayCompleted: todayCompleted,
      dailyGoal: dailyGoal,
      focusHeatmap: focusHeatmap(pomodoro["focusHistory"] as? [[String: Any]] ?? [])
    )
    Task { @MainActor in
      await self.updateLiveActivity(state)
    }
  }

  private func focusHeatmap(_ records: [[String: Any]], weeks: Int = 18) -> [Int] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.timeZone = .autoupdatingCurrent
    let today = calendar.startOfDay(for: .now)
    let dayCount = weeks * 7
    let firstDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

    let datedRecords: [(date: Date, seconds: Int)] = records.compactMap { record in
      guard record["completed"] as? Bool == true,
            let value = record["endedAt"] as? String,
            let date = parseISODate(value)
      else { return nil }
      return (date, record["durationSeconds"] as? Int ?? 0)
    }

    return (0..<dayCount).map { offset in
      let date = calendar.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
      let seconds = datedRecords
        .filter { calendar.isDate($0.date, inSameDayAs: date) }
        .reduce(0) { $0 + $1.seconds }
      switch seconds {
      case 0: 0
      case 1..<(25 * 60): 1
      case (25 * 60)..<(60 * 60): 2
      case (60 * 60)..<(120 * 60): 3
      default: 4
      }
    }
  }

  private func parseISODate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }

  @available(iOS 16.2, *)
  @MainActor
  private func updateLiveActivity(_ state: QingxuPomodoroAttributes.ContentState) async {
    let activities = Activity<QingxuPomodoroAttributes>.activities
    let isActivelyRunning = state.status == "running" && (
      state.timerDirection == "countUp" || (state.endsAt ?? .distantPast) > Date()
    )
    let content = ActivityContent(
      state: state,
      staleDate: isActivelyRunning ? state.endsAt : nil
    )

    if isActivelyRunning {
      if let activity = activities.first {
        await activity.update(content)
      } else {
        do {
          _ = try Activity.request(
            attributes: QingxuPomodoroAttributes(title: "清序专注"),
            content: content,
            pushType: nil
          )
        } catch {
          // Live Activities can be disabled by the user or unavailable on the device.
        }
      }
    } else {
      for activity in activities {
        await activity.end(content, dismissalPolicy: .immediate)
      }
    }
  }
}
