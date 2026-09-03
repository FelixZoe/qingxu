import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private let qingxuAppGroup = "group.one.darker.qingxu"

private enum QingxuWidgetPalette {
  static let background = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1)
      : UIColor(red: 0.980, green: 0.980, blue: 0.980, alpha: 1)
  })
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.427, green: 0.620, blue: 1.000, alpha: 1)
      : UIColor(red: 0.204, green: 0.471, blue: 0.965, alpha: 1)
  })
  static let elevated = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.118, green: 0.118, blue: 0.133, alpha: 1)
      : UIColor.white
  })
  static let hairline = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.10)
      : UIColor.black.withAlphaComponent(0.07)
  })
}

enum QingxuWidgetDestination: String, AppEnum {
  case today
  case pomodoro

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "清序页面"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .today: "今天",
    .pomodoro: "番茄钟",
  ]
}

struct OpenQingxuWidgetIntent: AppIntent {
  static let title: LocalizedStringResource = "打开清序"
  static let openAppWhenRun = true

  @Parameter(title: "页面") var destination: QingxuWidgetDestination

  init() { destination = .today }
  init(destination: QingxuWidgetDestination) { self.destination = destination }

  func perform() async throws -> some IntentResult {
    UserDefaults(suiteName: qingxuAppGroup)?.set(
      destination.rawValue,
      forKey: "pendingWidgetDestination"
    )
    return .result()
  }
}

private struct WidgetWeather: Decodable {
  let cityName: String
  let temperature: String
  let text: String
  let humidity: String
}

private struct WidgetQuote: Decodable {
  let text: String
  let source: String
}

private struct QingxuEntry: TimelineEntry {
  let date: Date
  let todayTaskCount: Int
  let nextTodayTaskTitle: String?
  let todayTaskTitles: [String]
  let mode: String
  let status: String
  let timerDirection: String
  let endsAt: Date?
  let startedAt: Date?
  let remainingSeconds: Int
  let todayCompleted: Int
  let dailyGoal: Int
  let focusHeatmap: [Int]
  let weather: WidgetWeather?
  let quote: WidgetQuote?
  let snapshotUpdatedAt: Date?
}

private struct QingxuProvider: TimelineProvider {
  func placeholder(in context: Context) -> QingxuEntry {
    QingxuEntry(
      date: .now,
      todayTaskCount: 3,
      nextTodayTaskTitle: "整理今天的安排",
      todayTaskTitles: ["整理今天的安排", "检查同步状态"],
      mode: "focus",
      status: "idle",
      timerDirection: "countdown",
      endsAt: nil,
      startedAt: nil,
      remainingSeconds: 25 * 60,
      todayCompleted: 2,
      dailyGoal: 4,
      focusHeatmap: Array(repeating: 0, count: 126),
      weather: WidgetWeather(cityName: "上海", temperature: "23", text: "晴", humidity: "52"),
      quote: WidgetQuote(text: "把今天真正重要的事做好。", source: "清序"),
      snapshotUpdatedAt: .now
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
    let weather = decode(WidgetWeather.self, data: defaults?.data(forKey: "qingxu.ambient.weather-cache.v1"))
    let quote = decode(WidgetQuote.self, data: defaults?.data(forKey: "qingxu.ambient.quote-cache.v1"))
    return QingxuEntry(
      date: .now,
      todayTaskCount: defaults?.integer(forKey: "todayTaskCount") ?? 0,
      nextTodayTaskTitle: defaults?.string(forKey: "nextTodayTaskTitle"),
      todayTaskTitles: defaults?.stringArray(forKey: "todayTaskTitles") ?? [],
      mode: defaults?.string(forKey: "pomodoroMode") ?? "focus",
      status: defaults?.string(forKey: "pomodoroStatus") ?? "idle",
      timerDirection: defaults?.string(forKey: "pomodoroTimerDirection") ?? "countdown",
      endsAt: defaults?.object(forKey: "pomodoroEndsAt") as? Date,
      startedAt: defaults?.object(forKey: "pomodoroStartedAt") as? Date,
      remainingSeconds: defaults?.integer(forKey: "pomodoroRemainingSeconds") ?? 25 * 60,
      todayCompleted: defaults?.integer(forKey: "pomodoroTodayCompleted") ?? 0,
      dailyGoal: max(1, defaults?.integer(forKey: "pomodoroDailyGoal") ?? 4),
      focusHeatmap: defaults?.array(forKey: "focusHeatmapLevels") as? [Int] ?? [],
      weather: weather,
      quote: quote,
      snapshotUpdatedAt: defaults?.object(forKey: "widgetSnapshotUpdatedAt") as? Date
    )
  }

  private func decode<T: Decodable>(_ type: T.Type, data: Data?) -> T? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

private struct QingxuWidgetSurface<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content.padding(16)
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
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Image(systemName: "calendar")
              .foregroundStyle(QingxuWidgetPalette.accent)
            Text(entry.date, format: .dateTime.month().day())
              .font(.caption.weight(.semibold))
            Spacer()
            if #available(iOSApplicationExtension 17.0, *) {
              Button(intent: OpenQingxuWidgetIntent(destination: .today)) {
                Image(systemName: "arrow.up.right")
                  .font(.caption.weight(.semibold))
              }
              .buttonStyle(.plain)
              .tint(.secondary)
            }
          }

          if family == .systemMedium {
            HStack(alignment: .top, spacing: 18) {
              VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.todayTaskCount)")
                  .font(.system(size: 44, weight: .semibold, design: .rounded))
                  .monospacedDigit()
                Text(entry.todayTaskCount == 0 ? "今天已清空" : "项待办")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .frame(width: 72, alignment: .leading)

              Rectangle()
                .fill(QingxuWidgetPalette.hairline)
                .frame(width: 1)

              VStack(alignment: .leading, spacing: 7) {
                if entry.todayTaskTitles.isEmpty {
                  Text("给自己留一点轻松")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                } else {
                  ForEach(Array(entry.todayTaskTitles.prefix(3).enumerated()), id: \.offset) { _, title in
                    HStack(spacing: 7) {
                      Circle()
                        .strokeBorder(.secondary.opacity(0.55), lineWidth: 1)
                        .frame(width: 10, height: 10)
                      Text(title).lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          } else {
            Spacer(minLength: 0)
            Text("\(entry.todayTaskCount)")
              .font(.system(size: 42, weight: .semibold, design: .rounded))
              .monospacedDigit()
            Text(entry.nextTodayTaskTitle ?? (entry.todayTaskCount == 0 ? "今天已清空" : "项待办"))
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
              .lineLimit(2)
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
        VStack(alignment: .leading, spacing: 9) {
          HStack {
            Label(modeTitle, systemImage: "timer")
              .font(.caption.weight(.semibold))
              .foregroundStyle(QingxuWidgetPalette.accent)
            Spacer()
            Text("\(entry.todayCompleted)/\(entry.dailyGoal)")
              .font(.caption2.weight(.semibold).monospacedDigit())
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          timerText
            .font(.system(size: family == .systemMedium ? 38 : 32, weight: .medium, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          HStack(spacing: 6) {
            Circle()
              .fill(entry.status == "running" ? QingxuWidgetPalette.accent : .secondary.opacity(0.35))
              .frame(width: 6, height: 6)
            Text(statusTitle)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
            Spacer()
            if #available(iOSApplicationExtension 17.0, *) {
              Button(intent: OpenQingxuWidgetIntent(destination: .pomodoro)) {
                Image(systemName: "arrow.up.right")
                  .font(.caption.weight(.semibold))
              }
              .buttonStyle(.plain)
              .tint(.secondary)
            }
          }
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

  private var statusTitle: String {
    switch entry.status {
    case "running": return "实时计时中"
    case "paused": return "已暂停"
    default: return "准备开始"
    }
  }

  private func format(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

private struct OverviewWidgetView: View {
  let entry: QingxuEntry

  var body: some View {
    QingxuWidgetSurface {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          Label("今天", systemImage: "sun.horizon.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(QingxuWidgetPalette.accent)
          Text("\(entry.todayTaskCount)")
            .font(.system(size: 38, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text(entry.nextTodayTaskTitle ?? (entry.todayTaskCount == 0 ? "今天已清空" : "项待办"))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Rectangle().fill(QingxuWidgetPalette.hairline).frame(width: 1)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label(modeTitle, systemImage: "timer")
              .font(.caption.weight(.semibold))
            Spacer()
            Text("\(entry.todayCompleted)/\(entry.dailyGoal)")
              .font(.caption2.weight(.semibold).monospacedDigit())
              .foregroundStyle(.secondary)
          }
          timerText
            .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(entry.status == "running" ? "正在同步计时" : "准备下一次专注")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .widgetURL(URL(string: "qingxu://today"))
  }

  @ViewBuilder
  private var timerText: some View {
    if entry.status == "running", entry.timerDirection == "countUp", let startedAt = entry.startedAt {
      Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
    } else if entry.status == "running", let endsAt = entry.endsAt, endsAt > Date() {
      Text(timerInterval: Date()...endsAt, countsDown: true)
    } else {
      Text(String(format: "%02d:%02d", entry.remainingSeconds / 60, entry.remainingSeconds % 60))
    }
  }

  private var modeTitle: String {
    switch entry.mode {
    case "shortBreak": return "短暂休息"
    case "longBreak": return "长休息"
    default: return "专注"
    }
  }

}

private struct AmbientWidgetView: View {
  let entry: QingxuEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    QingxuWidgetSurface {
      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline) {
          if let weather = entry.weather {
            Text("\(weather.temperature)°")
              .font(.system(size: family == .systemMedium ? 34 : 30, weight: .medium, design: .rounded))
              .monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
              Text(weather.text).font(.caption.weight(.semibold))
              Text(weather.cityName).font(.caption2).foregroundStyle(.secondary)
            }
          } else {
            Label("天气待刷新", systemImage: "cloud.sun")
              .font(.caption.weight(.semibold))
          }
          Spacer()
          Image(systemName: "quote.opening")
            .font(.caption)
            .foregroundStyle(QingxuWidgetPalette.accent)
        }
        Spacer(minLength: 0)
        Text(entry.quote?.text ?? "把今天真正重要的事做好。")
          .font(family == .systemMedium ? .subheadline.weight(.medium) : .caption.weight(.medium))
          .lineLimit(family == .systemMedium ? 2 : 3)
        if let source = entry.quote?.source, !source.isEmpty {
          Text("— \(source)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .widgetURL(URL(string: "qingxu://today"))
  }
}

private struct WidgetHeatmapView: View {
  let entry: QingxuEntry
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 18)

  var body: some View {
    QingxuWidgetSurface {
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Label("专注热力图", systemImage: "square.grid.3x3.fill")
            .font(.caption.weight(.semibold))
          Spacer()
          Text("近 18 周").font(.caption2).foregroundStyle(.secondary)
        }
        LazyVGrid(columns: columns, spacing: 3) {
          ForEach(0..<126, id: \.self) { index in
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
              .fill(heatColor(level(at: index)))
              .aspectRatio(1, contentMode: .fit)
          }
        }
        HStack {
          Text("今日已完成 \(entry.todayCompleted) 次")
          Spacer()
          Text("目标 \(entry.dailyGoal) 次")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
      }
    }
    .widgetURL(URL(string: "qingxu://pomodoro"))
  }

  private func level(at index: Int) -> Int {
    entry.focusHeatmap.indices.contains(index) ? min(4, max(0, entry.focusHeatmap[index])) : 0
  }

  private func heatColor(_ level: Int) -> Color {
    switch level {
    case 1: return QingxuWidgetPalette.accent.opacity(0.28)
    case 2: return QingxuWidgetPalette.accent.opacity(0.48)
    case 3: return QingxuWidgetPalette.accent.opacity(0.72)
    case 4: return QingxuWidgetPalette.accent
    default: return Color.secondary.opacity(0.10)
    }
  }
}

struct QingxuTodayWidget: Widget {
  let kind = "QingxuTodayWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuProvider()) { entry in
      TodayWidgetView(entry: entry)
        .qingxuWidgetBackground(QingxuWidgetPalette.background)
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
        .qingxuWidgetBackground(QingxuWidgetPalette.background)
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
      HStack(spacing: 10) {
        Image(systemName: context.state.mode == "focus" ? "timer" : "cup.and.saucer.fill")
          .foregroundStyle(QingxuWidgetPalette.accent)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(modeTitle(context.state.mode)).font(.caption.weight(.semibold))
            Text("今日 \(context.state.todayCompleted)/\(context.state.dailyGoal)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
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
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(QingxuWidgetPalette.accent)
            .frame(width: 28, height: 28)
        }
        DynamicIslandExpandedRegion(.trailing) {
          liveTimer(context.state)
            .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 66, alignment: .trailing)
            .id(context.state.phaseID)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 7) {
            HStack(spacing: 8) {
              Text(modeTitle(context.state.mode))
                .font(.system(size: 13, weight: .semibold))
              Spacer(minLength: 8)
              Text("今日 \(context.state.todayCompleted)/\(context.state.dailyGoal)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            FocusHeatmapStrip(values: context.state.focusHeatmap)
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 2)
          .padding(.bottom, 2)
        }
      } compactLeading: {
        Image(systemName: context.state.mode == "focus" ? "timer" : "cup.and.saucer.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(QingxuWidgetPalette.accent)
          .frame(width: 12)
      } compactTrailing: {
        liveTimer(context.state)
          .font(.system(size: 10.5, weight: .medium, design: .monospaced))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .frame(width: 34, alignment: .trailing)
          .id(context.state.phaseID)
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

struct QingxuOverviewWidget: Widget {
  let kind = "QingxuOverviewWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuProvider()) { entry in
      OverviewWidgetView(entry: entry)
        .qingxuWidgetBackground(QingxuWidgetPalette.background)
    }
    .configurationDisplayName("今日总览")
    .description("在一个简洁组件中查看任务与实时专注状态。")
    .supportedFamilies([.systemMedium])
  }
}

struct QingxuAmbientWidget: Widget {
  let kind = "QingxuAmbientWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuProvider()) { entry in
      AmbientWidgetView(entry: entry)
        .qingxuWidgetBackground(QingxuWidgetPalette.background)
    }
    .configurationDisplayName("天气与一言")
    .description("安静地查看天气与每日一句。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct QingxuHeatmapWidget: Widget {
  let kind = "QingxuHeatmapWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuProvider()) { entry in
      WidgetHeatmapView(entry: entry)
        .qingxuWidgetBackground(QingxuWidgetPalette.background)
    }
    .configurationDisplayName("专注热力图")
    .description("以简洁热力图查看近十八周的专注节奏。")
    .supportedFamilies([.systemMedium])
  }
}

private struct FocusHeatmapStrip: View {
  let values: [Int]
  private let columns = 18
  private let rows = 7

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<columns, id: \.self) { column in
        VStack(spacing: 2) {
          ForEach(0..<rows, id: \.self) { row in
            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
              .fill(color(for: value(at: column * rows + row)))
              .frame(width: 7, height: 4)
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("近十八周专注热力图")
  }

  private func value(at index: Int) -> Int {
    values.indices.contains(index) ? min(4, max(0, values[index])) : 0
  }

  private func color(for level: Int) -> Color {
    switch level {
    case 1: return Color(red: 0.39, green: 0.78, blue: 0.54).opacity(0.48)
    case 2: return Color(red: 0.27, green: 0.73, blue: 0.45).opacity(0.72)
    case 3: return Color(red: 0.16, green: 0.62, blue: 0.36)
    case 4: return Color(red: 0.08, green: 0.43, blue: 0.24)
    default: return Color.white.opacity(0.10)
    }
  }
}

@main
struct QingxuWidgetBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    QingxuTodayWidget()
    QingxuFocusWidget()
    QingxuOverviewWidget()
    QingxuAmbientWidget()
    QingxuHeatmapWidget()
    QingxuLiveActivity()
  }
}
