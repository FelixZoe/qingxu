import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct QingxuPomodoroAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var mode: String
    var status: String
    var timerDirection: String
    var phaseID: String
    var endsAt: Date?
    var startedAt: Date?
    var remainingSeconds: Int
    var totalSeconds: Int
    var todayCompleted: Int
    var dailyGoal: Int
  }

  var title: String
}
