import Foundation
import WidgetKit

enum RemoteSystemFeatures {
  static func publish(
    serverName: String,
    state: QingxuRemoteSurfaceState,
    detail: String,
    sessionStartedAt: Date?
  ) {
    guard let defaults = UserDefaults(suiteName: QingxuRemoteShared.appGroup) else { return }
    defaults.set(serverName, forKey: QingxuRemoteShared.serverNameKey)
    defaults.set(state.rawValue, forKey: QingxuRemoteShared.statusKey)
    defaults.set(detail, forKey: QingxuRemoteShared.detailKey)
    defaults.set(Date.now, forKey: QingxuRemoteShared.updatedAtKey)
    defaults.set(sessionStartedAt, forKey: QingxuRemoteShared.sessionStartedAtKey)
    WidgetCenter.shared.reloadAllTimelines()
  }
}
