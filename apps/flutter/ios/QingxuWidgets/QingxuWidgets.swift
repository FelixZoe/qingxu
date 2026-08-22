import ActivityKit
import SwiftUI
import WidgetKit

private let qingxuAppGroup = "group.one.darker.qingxu"

private struct QingxuEntry: TimelineEntry {
  let date: Date
  let todayTaskCount: Int
  let mode: String
  let status: String
  let endsAt: Date?
  let remainingSeconds: Int
}

private struct QingxuProvider: TimelineProvider {
  func placeholder(in context: Context) -> QingxuEntry {
    QingxuEntry(
      date: .now,
      todayTaskCount: 3,
      mode: "focus",
      status: "idle",
      endsAt: nil,
      remainingSeconds: 25 * 60
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (QingxuEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QingxuEntry>) -> Void) {
    let snapshot = entry()
    let nextUpdate = snapshot.status == "running"
      ? Date().addingTimeInterval(30)
      : Date().addingTimeInterval(15 * 60)
    completion(Timeline(entries: [snapshot], policy: .after(nextUpdate)))
  }

  private func entry() -> QingxuEntry {
    let defaults = UserDefaults(suiteName: qingxuAppGroup)
    return QingxuEntry(
      date: .now,
      todayTaskCount: defaults?.integer(forKey: "todayTaskCount") ?? 0,
      mode: defaults?.string(forKey: "pomodoroMode") ?? "focus",
      status: defaults?.string(forKey: "pomodoroStatus") ?? "idle",
      endsAt: defaults?.object(forKey: "pomodoroEndsAt") as? Date,
      remainingSeconds: defaults?.integer(forKey: "pomodoroRemainingSeconds") ?? 25 * 60
    )
  }
}

private struct QingxuWidgetSurface<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(16)
      .qingxuWidgetBackground(Color(red: 0.98, green: 0.973, blue: 0.949))
  }
}

private extension View {
  @ViewBuilder
  func qingxuWidgetBackground(_ color: Color) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { color }
    } else {
      background(color)
    }
  }
}

private struct TodayWidgetView: View {
  let entry: QingxuEntry

  var body: some View {
    QingxuWidgetSurface {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "sun.max.fill")
            .foregroundStyle(Color(red: 0.325, green: 0.459, blue: 0.561))
          Spacer()
          Text("清序")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(entry.todayTaskCount)")
          .font(.system(size: 38, weight: .bold, design: .rounded))
        Text(entry.todayTaskCount == 0 ? "今天已清空" : "项待办 · 今天")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .widgetURL(URL(string: "qingxu://today"))
  }
}

private struct FocusWidgetView: View {
  let entry: QingxuEntry

  var body: some View {
    QingxuWidgetSurface {
      VStack(alignment: .leading, spacing: 10) {
        Label(modeTitle, systemImage: "timer")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color(red: 0.325, green: 0.459, blue: 0.561))
        Spacer()
        timerText
          .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
        Text(entry.status == "running" ? "正在所有设备同步" : "轻触打开番茄钟")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .widgetURL(URL(string: "qingxu://pomodoro"))
  }

  @ViewBuilder
  private var timerText: some View {
    if entry.status == "running", let endsAt = entry.endsAt, endsAt > Date() {
      Text(timerInterval: Date()...endsAt, countsDown: true)
    } else {
      Text(format(entry.remainingSeconds))
    }
  }

  private var modeTitle: String {
    switch entry.mode {
    case "shortBreak": return "短暂休息"
    case "longBreak": return "长休息"
    default: return "专注"
    }
  }

  private func format(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

struct QingxuTodayWidget: Widget {
  let kind = "QingxuTodayWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuProvider()) { entry in
      TodayWidgetView(entry: entry)
    }
    .configurationDisplayName("今日任务")
    .description("快速查看今天还剩多少项任务。")
    .supportedFamilies([.systemSmall])
  }
}

struct QingxuFocusWidget: Widget {
  let kind = "QingxuFocusWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuProvider()) { entry in
      FocusWidgetView(entry: entry)
    }
    .configurationDisplayName("专注状态")
    .description("查看当前番茄钟，并快速回到专注页面。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@available(iOSApplicationExtension 16.2, *)
struct QingxuLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: QingxuPomodoroAttributes.self) { context in
      HStack(spacing: 12) {
        Image(systemName: "timer")
          .foregroundStyle(.green)
        VStack(alignment: .leading, spacing: 2) {
          Text(modeTitle(context.state.mode)).font(.caption.weight(.semibold))
          liveTimer(context.state)
            .font(.title2.bold().monospacedDigit())
        }
        Spacer()
      }
      .padding(.horizontal)
      .activityBackgroundTint(Color.black.opacity(0.92))
      .activitySystemActionForegroundColor(.white)
      .widgetURL(URL(string: "qingxu://pomodoro"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("清序", systemImage: "timer")
            .font(.caption.weight(.semibold))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(modeTitle(context.state.mode)).font(.caption2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          liveTimer(context.state)
            .font(.title.bold().monospacedDigit())
        }
      } compactLeading: {
        Image(systemName: "timer")
      } compactTrailing: {
        liveTimer(context.state)
          .font(.caption2.monospacedDigit())
          .frame(maxWidth: 52)
      } minimal: {
        Image(systemName: "timer")
      }
      .widgetURL(URL(string: "qingxu://pomodoro"))
      .keylineTint(.green)
    }
  }

  @ViewBuilder
  private func liveTimer(_ state: QingxuPomodoroAttributes.ContentState) -> some View {
    if state.status == "running", let endsAt = state.endsAt, endsAt > Date() {
      Text(timerInterval: Date()...endsAt, countsDown: true)
    } else {
      Text(String(format: "%02d:%02d", state.remainingSeconds / 60, state.remainingSeconds % 60))
    }
  }

  private func modeTitle(_ mode: String) -> String {
    switch mode {
    case "shortBreak": return "休息"
    case "longBreak": return "长休息"
    default: return "专注"
    }
  }
}

@main
struct QingxuWidgetBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    QingxuTodayWidget()
    QingxuFocusWidget()
    QingxuLiveActivity()
  }
}
