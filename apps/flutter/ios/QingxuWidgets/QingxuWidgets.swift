import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

private let qingxuAppGroup = "group.one.darker.qingxu"

private enum QingxuWidgetPalette {
  static let background = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.043, green: 0.043, blue: 0.047, alpha: 1)
      : UIColor(red: 0.969, green: 0.969, blue: 0.961, alpha: 1)
  })
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.945, green: 0.945, blue: 0.933, alpha: 1)
      : UIColor(red: 0.125, green: 0.129, blue: 0.141, alpha: 1)
  })
}

private struct QingxuEntry: TimelineEntry {
  let date: Date
  let todayTaskCount: Int
  let nextTodayTaskTitle: String?
  let mode: String
  let status: String
  let timerDirection: String
  let endsAt: Date?
  let startedAt: Date?
  let remainingSeconds: Int
}

private struct QingxuProvider: TimelineProvider {
  func placeholder(in context: Context) -> QingxuEntry {
    QingxuEntry(
      date: .now,
      todayTaskCount: 3,
      nextTodayTaskTitle: "整理今天的安排",
      mode: "focus",
      status: "idle",
      timerDirection: "countdown",
      endsAt: nil,
      startedAt: nil,
      remainingSeconds: 25 * 60
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (QingxuEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QingxuEntry>) -> Void) {
    let snapshot = entry()
    let nextUpdate = snapshot.status == "running"
      ? max(Date().addingTimeInterval(60), snapshot.endsAt ?? Date().addingTimeInterval(15 * 60))
      : Date().addingTimeInterval(15 * 60)
    completion(Timeline(entries: [snapshot], policy: .after(nextUpdate)))
  }

  private func entry() -> QingxuEntry {
    let defaults = UserDefaults(suiteName: qingxuAppGroup)
    return QingxuEntry(
      date: .now,
      todayTaskCount: defaults?.integer(forKey: "todayTaskCount") ?? 0,
      nextTodayTaskTitle: defaults?.string(forKey: "nextTodayTaskTitle"),
      mode: defaults?.string(forKey: "pomodoroMode") ?? "focus",
      status: defaults?.string(forKey: "pomodoroStatus") ?? "idle",
      timerDirection: defaults?.string(forKey: "pomodoroTimerDirection") ?? "countdown",
      endsAt: defaults?.object(forKey: "pomodoroEndsAt") as? Date,
      startedAt: defaults?.object(forKey: "pomodoroStartedAt") as? Date,
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
      .qingxuWidgetBackground(QingxuWidgetPalette.background)
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
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if family == .accessoryCircular {
      VStack(spacing: 1) {
        Image(systemName: "checkmark.circle")
        Text("\(entry.todayTaskCount)").font(.title3.bold().monospacedDigit())
      }
      .widgetURL(URL(string: "qingxu://today"))
    } else if family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 3) {
        Label("今日任务", systemImage: "checkmark.circle")
          .font(.caption.weight(.semibold))
        Text(entry.nextTodayTaskTitle ?? (entry.todayTaskCount == 0 ? "今天已清空" : "还有 \(entry.todayTaskCount) 项待办"))
          .font(.caption2)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .widgetURL(URL(string: "qingxu://today"))
    } else if family == .accessoryInline {
      Label("今日 \(entry.todayTaskCount) 项待办", systemImage: "checkmark.circle")
        .widgetURL(URL(string: "qingxu://today"))
    } else {
      QingxuWidgetSurface {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "sun.max.fill")
            .foregroundStyle(QingxuWidgetPalette.accent)
          Spacer()
          Text("清序")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        Spacer()
        if family == .systemMedium {
          HStack(alignment: .bottom, spacing: 16) {
            Text("\(entry.todayTaskCount)")
              .font(.system(size: 40, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 4) {
              Text(entry.todayTaskCount == 0 ? "今天已清空" : "项待办")
                .font(.caption).foregroundStyle(.secondary)
              Text(entry.nextTodayTaskTitle ?? "给自己留一点轻松")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            }
            Spacer()
          }
        } else {
          Text("\(entry.todayTaskCount)")
            .font(.system(size: 38, weight: .bold, design: .rounded))
          Text(entry.todayTaskCount == 0 ? "今天已清空" : "项待办 · 今天")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      }
      .widgetURL(URL(string: "qingxu://today"))
    }
  }
}

private struct FocusWidgetView: View {
  let entry: QingxuEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if family == .accessoryCircular {
      VStack(spacing: 1) {
        Image(systemName: "timer")
        timerText
          .font(.caption2.bold().monospacedDigit())
      }
      .widgetURL(URL(string: "qingxu://pomodoro"))
    } else if family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 3) {
        Label(modeTitle, systemImage: "timer").font(.caption.weight(.semibold))
        timerText.font(.title3.bold().monospacedDigit())
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .widgetURL(URL(string: "qingxu://pomodoro"))
    } else if family == .accessoryInline {
      HStack(spacing: 4) {
        Text(modeTitle)
        timerText
      }
      .widgetURL(URL(string: "qingxu://pomodoro"))
    } else {
      QingxuWidgetSurface {
        VStack(alignment: .leading, spacing: 10) {
          Label(modeTitle, systemImage: "timer")
            .font(.caption.weight(.semibold))
            .foregroundStyle(QingxuWidgetPalette.accent)
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
  }

  @ViewBuilder
  private var timerText: some View {
    if entry.status == "running", entry.timerDirection == "countUp", let startedAt = entry.startedAt {
      Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
    } else if entry.status == "running", let endsAt = entry.endsAt, endsAt > Date() {
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
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
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
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

@available(iOSApplicationExtension 16.2, *)
struct QingxuLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: QingxuPomodoroAttributes.self) { context in
      HStack(spacing: 12) {
        Image(systemName: "timer")
          .foregroundStyle(QingxuWidgetPalette.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text(modeTitle(context.state.mode)).font(.caption.weight(.semibold))
          liveTimer(context.state)
            .font(.title3.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
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
          Image(systemName: context.state.mode == "focus" ? "timer" : "cup.and.saucer.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(QingxuWidgetPalette.accent)
            .frame(width: 24, height: 24)
        }
        DynamicIslandExpandedRegion(.center) {
          liveTimer(context.state)
            .font(.title3.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(minWidth: 76)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(modeTitle(context.state.mode))
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 8) {
            Circle()
              .fill(QingxuWidgetPalette.accent)
              .frame(width: 6, height: 6)
            Text(context.state.status == "running" ? "专注进行中" : "计时已暂停")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.top, 2)
        }
      } compactLeading: {
        Image(systemName: context.state.mode == "focus" ? "timer" : "cup.and.saucer.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(QingxuWidgetPalette.accent)
          .frame(width: 12)
      } compactTrailing: {
        liveTimer(context.state)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(width: 38, alignment: .trailing)
      } minimal: {
        Image(systemName: context.state.mode == "focus" ? "timer" : "cup.and.saucer.fill")
      }
      .widgetURL(URL(string: "qingxu://pomodoro"))
      .keylineTint(QingxuWidgetPalette.accent)
    }
  }

  @ViewBuilder
  private func liveTimer(_ state: QingxuPomodoroAttributes.ContentState) -> some View {
    if state.status == "running", state.timerDirection == "countUp", let startedAt = state.startedAt {
      Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
    } else if state.status == "running", let endsAt = state.endsAt, endsAt > Date() {
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
