import Foundation
#if os(iOS)
import ActivityKit
#endif

enum QingxuRemoteSurfaceState: String {
  case idle
  case connecting
  case online
  case offline
  case session
}

enum QingxuRemoteShared {
  static let appGroup = "group.one.darker.qingxu"
  static let serverNameKey = "qingxu.remote.widget.serverName"
  static let statusKey = "qingxu.remote.widget.status"
  static let detailKey = "qingxu.remote.widget.detail"
  static let updatedAtKey = "qingxu.remote.widget.updatedAt"
  static let sessionStartedAtKey = "qingxu.remote.widget.sessionStartedAt"
}

#if os(iOS)
struct QingxuRemoteSessionAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let status: String
    let detail: String
    let startedAt: Date
  }

  let serverName: String
}
#endif
