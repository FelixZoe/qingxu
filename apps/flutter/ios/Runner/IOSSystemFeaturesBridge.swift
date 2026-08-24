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
        todayTaskCount: payload["todayTaskCount"] as? Int ?? 0
      )
      result(nil)
    }
    self.channel = channel
  }

  private func update(pomodoro: [String: Any], todayTaskCount: Int) {
    let mode = pomodoro["mode"] as? String ?? "focus"
    let status = pomodoro["status"] as? String ?? "idle"
    let timerDirection = pomodoro["timerDirection"] as? String ?? "countdown"
    let remainingSeconds = pomodoro["remainingSeconds"] as? Int ?? 25 * 60
    let endsAt = (pomodoro["endsAt"] as? String).flatMap(ISO8601DateFormatter().date)
    let startedAt = (pomodoro["startedAt"] as? String).flatMap(ISO8601DateFormatter().date)
    let displayStartedAt = startedAt?.addingTimeInterval(TimeInterval(-remainingSeconds))

    if let defaults = UserDefaults(suiteName: Self.appGroup) {
      defaults.set(todayTaskCount, forKey: "todayTaskCount")
      defaults.set(mode, forKey: "pomodoroMode")
      defaults.set(status, forKey: "pomodoroStatus")
      defaults.set(timerDirection, forKey: "pomodoroTimerDirection")
      defaults.set(remainingSeconds, forKey: "pomodoroRemainingSeconds")
      defaults.set(endsAt, forKey: "pomodoroEndsAt")
      defaults.set(displayStartedAt, forKey: "pomodoroStartedAt")
    }
    WidgetCenter.shared.reloadAllTimelines()

    guard #available(iOS 16.2, *) else { return }
    let state = QingxuPomodoroAttributes.ContentState(
      mode: mode,
      status: status,
      timerDirection: timerDirection,
      endsAt: endsAt,
      startedAt: displayStartedAt,
      remainingSeconds: remainingSeconds
    )
    Task { @MainActor in
      await self.updateLiveActivity(state)
    }
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
