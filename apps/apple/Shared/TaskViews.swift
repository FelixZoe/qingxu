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
  let scheduledAt: Date?
}

#if os(iOS)
private struct CalendarPickerRoute: Identifiable {
  let id = UUID()
}
#endif

struct TaskListScreen: View {
  @EnvironmentObject private var store: AppStore
  let scope: TaskScope

  @State private var searchText = ""
  @State private var editor: TaskEditorRoute?
  @State private var capture: TaskCaptureRoute?
  @State private var pendingDelete: TaskItem?
  @State private var recentlyDeleted: TaskItem?
  @State private var selectedDate = Date.now
  #if os(iOS)
  @State private var calendarPicker: CalendarPickerRoute?
  #endif

  private var tasks: [TaskItem] {
    let values = scope == .inbox ? store.inboxTasks : store.tasks(on: selectedDate)
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
          #if os(iOS)
          if scope == .today {
            TodayWeekStrip(selection: $selectedDate)
              .listRowInsets(.init(top: 4, leading: 16, bottom: 10, trailing: 16))
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
          }
          #endif
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
            .frame(maxWidth: .infinity)
            .padding(.top, scope == .today ? 42 : 120)
            .foregroundStyle(QingxuPalette.quiet)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
      }
      .qingxuScreen()
      .navigationTitle(navigationTitle)
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
        #else
        if scope == .today {
          ToolbarItem(placement: .primaryAction) {
            Button {
              calendarPicker = CalendarPickerRoute()
            } label: {
              Image(systemName: "calendar")
                .frame(width: 36, height: 36)
            }
            .accessibilityLabel("打开月历")
          }
        }
        #endif
      }
      #if os(iOS)
      .overlay(alignment: .bottomTrailing) {
        if capture == nil {
          addButton
            .padding(.trailing, 20)
            .padding(.bottom, 18)
            .transition(.scale.combined(with: .opacity))
        }
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
      .sheet(item: $calendarPicker) { _ in
        CalendarPickerSheet(selection: $selectedDate)
          .presentationDetents([.fraction(0.68)])
          .presentationDragIndicator(.visible)
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
      #if os(iOS)
      .overlay {
        if capture != nil {
          Color.black.opacity(0.2)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismissCapture() }
            .transition(.opacity)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let capture {
          TaskQuickCaptureBar(
            scope: capture.scope,
            initialSchedule: capture.scheduledAt,
            onDismiss: dismissCapture
          )
          .environmentObject(store)
          .padding(.horizontal, 8)
          .padding(.bottom, 6)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.easeOut(duration: 0.22), value: capture?.id)
      #endif
    }
  }

  private var navigationTitle: String {
    guard scope == .today else { return scope.title }
    if Calendar.autoupdatingCurrent.isDateInToday(selectedDate) { return "今天" }
    return selectedDate.formatted(.dateTime.month().day().weekday(.wide))
  }

  private var addButton: some View {
    Button {
      #if os(iOS)
      capture = TaskCaptureRoute(
        scope: scope,
        scheduledAt: scope == .today ? selectedDate : nil
      )
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

  private func dismissCapture() {
    withAnimation(.easeOut(duration: 0.2)) { capture = nil }
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
private enum CaptureModal: String, Identifiable {
  case schedule

  var id: String { rawValue }
}

private struct TaskQuickCaptureBar: View {
  @EnvironmentObject private var store: AppStore

  let onDismiss: () -> Void

  @FocusState private var titleFocused: Bool
  @State private var title = ""
  @State private var notes = ""
  @State private var presentedModal: CaptureModal?
  @State private var hasSchedule: Bool
  @State private var scheduledAt: Date
  @State private var includesTime = false
  @State private var priority: TaskPriority?

  init(scope: TaskScope, initialSchedule: Date?, onDismiss: @escaping () -> Void) {
    self.onDismiss = onDismiss
    let date = initialSchedule ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
    _hasSchedule = State(initialValue: initialSchedule != nil || scope == .today)
    _scheduledAt = State(initialValue: date)
  }

  var body: some View {
    composer
      .frame(height: 172)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .stroke(QingxuPalette.separator.opacity(0.7), lineWidth: 0.7)
      }
      .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
      .sheet(item: $presentedModal) { _ in
        schedulePicker
          .presentationDetents([.fraction(0.82)])
          .presentationDragIndicator(.visible)
      }
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
          presentedModal = .schedule
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
            presentedModal = nil
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") {
            hasSchedule = true
            presentedModal = nil
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
    onDismiss()
  }
}

private struct TodayWeekStrip: View {
  @Binding var selection: Date

  private let calendar = Calendar.autoupdatingCurrent

  private var days: [Date] {
    let interval = calendar.dateInterval(of: .weekOfYear, for: selection)
    let start = interval?.start ?? calendar.startOfDay(for: selection)
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack {
        Text(selection.formatted(.dateTime.year().month(.wide)))
          .font(.subheadline.weight(.semibold))
        Spacer()
        Button("回到今天") {
          withAnimation(.easeInOut(duration: 0.2)) { selection = .now }
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.plain)
        .foregroundStyle(QingxuPalette.accent)
      }

      HStack(spacing: 4) {
        ForEach(days, id: \.self) { day in
          let selected = calendar.isDate(day, inSameDayAs: selection)
          Button {
            withAnimation(.easeInOut(duration: 0.18)) { selection = day }
          } label: {
            VStack(spacing: 6) {
              Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2)
              Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.white : QingxuPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
              selected ? QingxuPalette.accent : Color.clear,
              in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        }
      }
    }
    .padding(14)
    .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

private struct CalendarPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: Date

  var body: some View {
    NavigationStack {
      DatePicker(
        "选择日期",
        selection: $selection,
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .tint(QingxuPalette.accent)
      .padding(.horizontal, 18)
      .frame(maxHeight: .infinity, alignment: .top)
      .qingxuScreen()
      .navigationTitle("日历")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") { dismiss() }
            .fontWeight(.semibold)
        }
      }
    }
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
