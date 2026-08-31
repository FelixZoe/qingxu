import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class MacFloatingPanelController: ObservableObject {
  @Published private(set) var isExpanded = false

  private let compactSize = NSSize(width: 104, height: 46)
  private let expandedSize = NSSize(width: 336, height: 52)
  private var panel: NSPanel?

  func present(store: AppStore) {
    if let panel {
      panel.orderFrontRegardless()
      return
    }

    let frame = initialFrame(size: compactSize)
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.contentViewController = NSHostingController(
      rootView: MacFloatingTimerPanel(store: store, controller: self)
    )
    panel.orderFrontRegardless()
    self.panel = panel
  }

  func toggleExpanded() {
    guard let panel else { return }
    let nextExpanded = !isExpanded
    let size = nextExpanded ? expandedSize : compactSize
    let current = panel.frame
    let target = NSRect(
      x: current.maxX - size.width,
      y: current.maxY - size.height,
      width: size.width,
      height: size.height
    )

    withAnimation(.easeInOut(duration: 0.24)) {
      isExpanded = nextExpanded
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.24
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = true
      panel.animator().setFrame(target, display: true)
    }
  }

  func openMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows
      .first(where: { !($0 is NSPanel) })?
      .makeKeyAndOrderFront(nil)
  }

  func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  private func initialFrame(size: NSSize) -> NSRect {
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    return NSRect(
      x: visible.maxX - size.width - 18,
      y: visible.maxY - size.height - 18,
      width: size.width,
      height: size.height
    )
  }
}

private struct MacFloatingTimerPanel: View {
  @ObservedObject var store: AppStore
  @ObservedObject var controller: MacFloatingPanelController
  @State private var isHovered = false

  private var progress: Double {
    guard store.pomodoro.timerDirection == .countdown else { return 1 }
    let total = max(1, store.pomodoro.duration(for: store.pomodoro.mode))
    return min(1, max(0, Double(store.displayedRemainingSeconds) / Double(total)))
  }

  private var currentTask: TaskItem? { store.todayTasks.first }

  var body: some View {
    HStack(spacing: 10) {
      if controller.isExpanded {
        expandedContent
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }

      Button(action: controller.toggleExpanded) {
        timerCapsule
      }
      .buttonStyle(.plain)
      .help(controller.isExpanded ? "收起" : "展开")
    }
    .padding(.horizontal, 7)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    .background {
      Capsule(style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.09), lineWidth: 0.8)
        }
    }
    .opacity(isHovered ? 1 : 0.88)
    .contentShape(Capsule(style: .continuous))
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.14)) {
        isHovered = hovering
      }
    }
  }

  private var expandedContent: some View {
    HStack(spacing: 8) {
      Button {
        if let currentTask { store.toggleTask(currentTask) }
      } label: {
        Image(systemName: currentTask == nil ? "checkmark.circle" : "circle")
          .font(.system(size: 14, weight: .medium))
      }
      .buttonStyle(.plain)
      .disabled(currentTask == nil)
      .help("完成当前任务")

      Text(currentTask?.title ?? "今天没有待办")
        .font(.system(size: 12.5, weight: .medium))
        .lineLimit(1)
        .frame(maxWidth: 132, alignment: .leading)

      Button(action: store.togglePomodoro) {
        Image(systemName: store.pomodoro.status == .running ? "pause.fill" : "play.fill")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .help(store.pomodoro.status == .running ? "暂停" : "开始")

      Button(action: controller.openMainWindow) {
        Image(systemName: "arrow.up.forward.app")
          .font(.system(size: 12, weight: .medium))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .help("打开清序")
    }
  }

  private var timerCapsule: some View {
    HStack(spacing: 6) {
      ZStack {
        Circle()
          .stroke(Color.primary.opacity(0.12), lineWidth: 2)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(Color.primary.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 20, height: 20)

      Text(format(store.displayedRemainingSeconds))
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
    }
    .frame(width: 86, height: 34)
    .contentShape(Capsule(style: .continuous))
  }

  private func format(_ seconds: Int) -> String {
    let safe = max(0, seconds)
    return String(format: "%02d:%02d", safe / 60, safe % 60)
  }
}
