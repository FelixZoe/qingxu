import ActivityKit
import Foundation
import OSLog
import WidgetKit

enum RemoteSystemFeatures {
  private static let logger = Logger(
    subsystem: "one.darker.qingxu",
    category: "RemoteSession"
  )

  static func publish(
    serverName: String,
    state: QingxuRemoteSurfaceState,
    detail: String,
    sessionStartedAt: Date?
  ) {
    let defaults = UserDefaults(suiteName: QingxuRemoteShared.appGroup)
    defaults?.set(serverName, forKey: QingxuRemoteShared.serverNameKey)
    defaults?.set(state.rawValue, forKey: QingxuRemoteShared.statusKey)
    defaults?.set(detail, forKey: QingxuRemoteShared.detailKey)
    defaults?.set(Date.now, forKey: QingxuRemoteShared.updatedAtKey)
    defaults?.set(sessionStartedAt, forKey: QingxuRemoteShared.sessionStartedAtKey)
    WidgetCenter.shared.reloadAllTimelines()

    guard #available(iOS 16.2, *) else { return }
    Task(priority: .userInitiated) {
      if state == .session, let sessionStartedAt {
        await startOrUpdateActivity(
          serverName: serverName,
          detail: detail,
          startedAt: sessionStartedAt
        )
      } else {
        await endActivities(
          state: state,
          detail: detail,
          startedAt: sessionStartedAt ?? .now
        )
      }
    }
  }

  @available(iOS 16.2, *)
  private static func content(
    state: QingxuRemoteSurfaceState,
    detail: String,
    startedAt: Date
  ) -> ActivityContent<QingxuRemoteSessionAttributes.ContentState> {
    ActivityContent(
      state: QingxuRemoteSessionAttributes.ContentState(
        status: state.rawValue,
        detail: detail,
        startedAt: startedAt
      ),
      staleDate: nil
    )
  }

  @available(iOS 16.2, *)
  private static func startOrUpdateActivity(
    serverName: String,
    detail: String,
    startedAt: Date
  ) async {
    let activeContent = content(state: .session, detail: detail, startedAt: startedAt)
    if let activity = Activity<QingxuRemoteSessionAttributes>.activities.first {
      await activity.update(activeContent)
      for duplicate in Activity<QingxuRemoteSessionAttributes>.activities.dropFirst() {
        await duplicate.end(activeContent, dismissalPolicy: .immediate)
      }
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    do {
      _ = try Activity.request(
        attributes: QingxuRemoteSessionAttributes(serverName: serverName),
        content: activeContent,
        pushType: nil
      )
    } catch {
      logger.error("Unable to start remote Live Activity: \(error.localizedDescription, privacy: .public)")
    }
  }

  @available(iOS 16.2, *)
  private static func endActivities(
    state: QingxuRemoteSurfaceState,
    detail: String,
    startedAt: Date
  ) async {
    let finalContent = content(state: state, detail: detail, startedAt: startedAt)
    for activity in Activity<QingxuRemoteSessionAttributes>.activities {
      await activity.end(finalContent, dismissalPolicy: .immediate)
    }
  }
}
