import SwiftUI

enum TaskScope {
  case inbox
  case today

  var title: String { self == .inbox ? "收集箱" : "今天" }
  var emptyTitle: String { self == .inbox ? "收集箱已清空" : "今天没有任务" }
  var emptyDetail: String { self == .inbox ? "随时记录任务和想法" : "留一点时间给自己" }
  var symbol: String { self == .inbox ? "tray" : "sun.max" }
}

private struct TaskEditorRoute: Identifiable {
  let id = UUID()
  let task: TaskItem?
  let scope: TaskScope
}

private struct TaskCaptureRoute: Identifiable {
  let id = UUID()
  let scope: TaskScope
}

struct TaskListScreen: View {
  @EnvironmentObject private var store: AppStore
  let scope: TaskScope

  @State private var searchText = ""
  @State private var editor: TaskEditorRoute?
  @State private var capture: TaskCaptureRoute?
  @State private var pendingDelete: TaskItem?
  @State private var recentlyDeleted: TaskItem?

  private var tasks: [TaskItem] {
    let values = scope == .inbox ? store.inboxTasks : store.todayTasks
    guard !searchText.isEmpty else { return values }
    return values.filter {
      $0.title.localizedStandardContains(searchText) ||
      $0.notes.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        List {
          ForEach(tasks) { task in
            TaskRow(task: task) {
              withAnimation(.easeInOut(duration: 0.2)) { store.toggleTask(task) }
            }
            .contentShape(Rectangle())
            .onTapGesture { editor = TaskEditorRoute(task: task, scope: scope) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) { pendingDelete = task } label: {
                Label("删除", systemImage: "trash")
              }
            }
            .listRowInsets(.init(top: 5, leading: 20, bottom: 5, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)

        if tasks.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: scope.symbol)
              .font(.system(size: 42, weight: .light))
            Text(scope.emptyTitle)
              .font(.title3.weight(.semibold))
              .foregroundStyle(.primary)
            Text(scope.emptyDetail)
              .font(.subheadline)
          }
          .foregroundStyle(QingxuPalette.quiet)
        }
      }
      .qingxuScreen()
      .navigationTitle(scope.title)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.large)
      .searchable(
        text: $searchText,
        placement: .navigationBarDrawer(displayMode: .automatic),
        prompt: "搜索任务"
      )
      #else
      .searchable(text: $searchText, prompt: "搜索任务")
      #endif
      .toolbar {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { addButton }
        #endif
      }
      #if os(iOS)
      .overlay(alignment: .bottomTrailing) {
        addButton
          .padding(.trailing, 20)
          .padding(.bottom, 18)
      }
      #endif
      .overlay(alignment: .bottom) {
        if let recentlyDeleted {
          undoBanner(for: recentlyDeleted)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .sheet(item: $editor) { route in
        TaskEditorSheet(task: route.task, scope: route.scope)
          .environmentObject(store)
      }
      #if os(iOS)
      .sheet(item: $capture) { route in
        TaskQuickCaptureSheet(scope: route.scope)
          .environmentObject(store)
      }
      #endif
      .confirmationDialog(
        "删除“\(pendingDelete?.title ?? "任务")”？",
        isPresented: Binding(
          get: { pendingDelete != nil },
          set: { if !$0 { pendingDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("删除", role: .destructive) {
          guard let task = pendingDelete else { return }
          withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteTask(task)
            recentlyDeleted = task
          }
          pendingDelete = nil
        }
        Button("取消", role: .cancel) { pendingDelete = nil }
      }
    }
  }

  private var addButton: some View {
    Button {
      #if os(iOS)
      capture = TaskCaptureRoute(scope: scope)
      #else
      editor = TaskEditorRoute(task: nil, scope: scope)
      #endif
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .frame(width: 54, height: 54)
        .foregroundStyle(.white)
        .background(QingxuPalette.accent, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("新增任务")
    .qingxuFloatingSurface()
  }

  private func undoBanner(for task: TaskItem) -> some View {
    HStack {
      Text("任务已删除").font(.subheadline)
      Spacer()
      Button("撤销") {
        withAnimation(.easeInOut(duration: 0.2)) {
          store.restoreTask(task)
          recentlyDeleted = nil
        }
      }
      .fontWeight(.semibold)
    }
    .padding(.horizontal, 16)
    .frame(height: 48)
    .background(.regularMaterial, in: Capsule())
  }
}

private struct TaskRow: View {
  let task: TaskItem
  let toggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Button(action: toggle) {
        Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(task.status == .completed ? QingxuPalette.accent : QingxuPalette.quiet)
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(.body.weight(.medium))
          .strikethrough(task.status == .completed)
        if !task.notes.isEmpty {
          Text(task.notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      if let priority = task.priority {
        Image(systemName: priority.symbol)
          .font(.caption.weight(.semibold))
          .foregroundStyle(priority.color)
          .accessibilityLabel(priority.title)
      }
      if let deadline = task.deadlineAt {
        Text(deadline, format: .dateTime.month().day())
          .font(.caption)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
    .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

#if os(iOS)
private enum CapturePage {
  case composer
  case schedule
}

private struct TaskQuickCaptureSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss

  let scope: TaskScope

  @FocusState private var titleFocused: Bool
  @State private var title = ""
  @State private var notes = ""
  @State private var page = CapturePage.composer
  @State private var detent: PresentationDetent = .height(208)
  @State private var hasSchedule: Bool
  @State private var scheduledAt: Date
  @State private var includesTime = false
  @State private var priority: TaskPriority?

  init(scope: TaskScope) {
    self.scope = scope
    let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    _hasSchedule = State(initialValue: scope == .today)
    _scheduledAt = State(initialValue: today)
  }

  var body: some View {
    Group {
      switch page {
      case .composer:
        composer
      case .schedule:
        schedulePicker
      }
    }
    .presentationDetents([.height(208), .large], selection: $detent)
    .presentationDragIndicator(.hidden)
    .qingxuScreen()
  }

  private var composer: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 9) {
        TextField("例如：每月 9 号还信用卡", text: $title)
          .font(.system(size: 18, weight: .medium))
          .focused($titleFocused)
          .submitLabel(.done)
          .onSubmit(save)
          .accessibilityIdentifier("quickCaptureTitle")

        TextField("描述", text: $notes, axis: .vertical)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1...2)
          .accessibilityIdentifier("quickCaptureNotes")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 20)

      Spacer(minLength: 12)

      HStack(spacing: 8) {
        captureButton(
          symbol: hasSchedule ? "calendar.badge.checkmark" : "calendar",
          label: hasSchedule ? scheduleLabel : "安排"
        ) {
          titleFocused = false
          withAnimation(.easeInOut(duration: 0.28)) {
            page = .schedule
            detent = .large
          }
        }

        Menu {
          ForEach(TaskPriority.allCases) { value in
            Button {
              priority = value
            } label: {
              Label(value.title, systemImage: value.symbol)
            }
          }
          if priority != nil {
            Divider()
            Button("清除优先级", role: .destructive) { priority = nil }
          }
        } label: {
          Image(systemName: priority?.symbol ?? "flag")
            .foregroundStyle(priority?.color ?? QingxuPalette.quiet)
            .frame(width: 38, height: 38)
            .background(QingxuPalette.secondaryBackground, in: Circle())
        }
        .accessibilityLabel(priority?.title ?? "设置优先级")

        Button {
          hasSchedule.toggle()
          if hasSchedule {
            scheduledAt = Calendar.autoupdatingCurrent.startOfDay(for: .now)
          }
        } label: {
          Image(systemName: hasSchedule ? "sun.max.fill" : "tray")
            .frame(width: 38, height: 38)
            .background(QingxuPalette.secondaryBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasSchedule ? QingxuPalette.accent : QingxuPalette.quiet)
        .accessibilityLabel(hasSchedule ? "已安排到今天" : "保存在收集箱")

        Spacer()

        Button(action: save) {
          Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .bold))
            .frame(width: 42, height: 42)
            .foregroundStyle(.white)
            .background(QingxuPalette.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        .accessibilityLabel("保存任务")
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
    }
    .onAppear {
      DispatchQueue.main.async { titleFocused = true }
    }
  }

  private var schedulePicker: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          HStack(spacing: 10) {
            scheduleShortcut("今天", symbol: "calendar", date: .now)
            scheduleShortcut(
              "明天",
              symbol: "sunrise",
              date: Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now) ?? .now
            )
            scheduleShortcut("下周一", symbol: "calendar.badge.clock", date: nextMonday)
          }

          DatePicker(
            "日期",
            selection: $scheduledAt,
            displayedComponents: .date
          )
          .datePickerStyle(.graphical)
          .tint(QingxuPalette.accent)

          VStack(spacing: 0) {
            Toggle("指定时间", isOn: $includesTime)
              .padding(.horizontal, 16)
              .frame(height: 54)
            if includesTime {
              Divider().padding(.leading, 16)
              DatePicker(
                "时间",
                selection: $scheduledAt,
                displayedComponents: .hourAndMinute
              )
              .padding(.horizontal, 16)
              .frame(height: 54)
            }
          }
          .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
      }
      .navigationTitle("安排")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("返回") {
            withAnimation(.easeInOut(duration: 0.28)) {
              page = .composer
              detent = .height(208)
            }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") {
            hasSchedule = true
            withAnimation(.easeInOut(duration: 0.28)) {
              page = .composer
              detent = .height(208)
            }
          }
          .fontWeight(.semibold)
        }
      }
    }
  }

  private func captureButton(
    symbol: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
        Text(label).lineLimit(1)
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(hasSchedule ? QingxuPalette.accent : QingxuPalette.quiet)
      .padding(.horizontal, 12)
      .frame(height: 38)
      .background(QingxuPalette.secondaryBackground, in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private func scheduleShortcut(_ title: String, symbol: String, date: Date) -> some View {
    Button {
      scheduledAt = Calendar.autoupdatingCurrent.startOfDay(for: date)
      hasSchedule = true
    } label: {
      VStack(spacing: 8) {
        Image(systemName: symbol).font(.title3)
        Text(title).font(.caption)
      }
      .foregroundStyle(QingxuPalette.accent)
      .frame(maxWidth: .infinity)
      .frame(height: 72)
      .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var nextMonday: Date {
    let calendar = Calendar.autoupdatingCurrent
    return calendar.nextDate(
      after: .now,
      matching: DateComponents(weekday: 2),
      matchingPolicy: .nextTime
    ) ?? .now
  }

  private var scheduleLabel: String {
    if Calendar.autoupdatingCurrent.isDateInToday(scheduledAt) { return "今天" }
    if Calendar.autoupdatingCurrent.isDateInTomorrow(scheduledAt) { return "明天" }
    return scheduledAt.formatted(.dateTime.month().day())
  }

  private func save() {
    guard let created = store.addTask(title: title, notes: notes) else { return }
    var updated = created
    updated.priority = priority
    if hasSchedule {
      updated.startAt = includesTime
        ? scheduledAt
        : Calendar.autoupdatingCurrent.startOfDay(for: scheduledAt)
    }
    store.updateTask(updated)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    dismiss()
  }
}

private extension TaskPriority {
  var color: Color {
    switch self {
    case .high: QingxuPalette.danger
    case .medium: Color.orange
    case .low: QingxuPalette.accent
    }
  }
}
#else
private extension TaskPriority {
  var color: Color { QingxuPalette.accent }
}
#endif

private struct TaskEditorSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss

  let task: TaskItem?
  let scope: TaskScope

  @State private var title: String
  @State private var notes: String
  @State private var scheduledToday: Bool
  @State private var hasDeadline: Bool
  @State private var deadline: Date

  init(task: TaskItem?, scope: TaskScope) {
    self.task = task
    self.scope = scope
    _title = State(initialValue: task?.title ?? "")
    _notes = State(initialValue: task?.notes ?? "")
    _scheduledToday = State(initialValue: task?.startAt != nil || scope == .today)
    _hasDeadline = State(initialValue: task?.deadlineAt != nil)
    _deadline = State(initialValue: task?.deadlineAt ?? .now)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("任务") {
          TextField("要做什么？", text: $title)
          TextField("备注（可选）", text: $notes, axis: .vertical)
            .lineLimit(3...7)
        }
        Section("时间") {
          Toggle("安排到今天", isOn: $scheduledToday)
          Toggle("设置截止时间", isOn: $hasDeadline)
          if hasDeadline {
            DatePicker("截止", selection: $deadline)
          }
        }
      }
      .qingxuScreen()
      .navigationTitle(task == nil ? "新增任务" : "编辑任务")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 360, minHeight: 360)
  }

  private func save() {
    let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    if var task {
      task.title = title
      task.notes = notes
      task.startAt = scheduledToday ? today : nil
      task.deadlineAt = hasDeadline ? deadline : nil
      store.updateTask(task)
    } else {
      guard let created = store.addTask(title: title, notes: notes, forToday: scheduledToday) else { return }
      if hasDeadline {
        var updated = created
        updated.deadlineAt = deadline
        store.updateTask(updated)
      }
    }
    dismiss()
  }
}
