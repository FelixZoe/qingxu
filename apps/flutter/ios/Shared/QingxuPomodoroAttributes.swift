import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct QingxuPomodoroAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var mode: String
    var status: String
    var timerDirection: String
    var endsAt: Date?
    var startedAt: Date?
    var remainingSeconds: Int
  }

  var title: String
}
