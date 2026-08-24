import BackgroundTasks
import Foundation

enum RSSBackgroundRefresh {
  static let identifier = "one.darker.qingxu.rss.refresh"

  static func schedule() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }
}
