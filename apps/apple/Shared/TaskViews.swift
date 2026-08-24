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

struct TaskListScreen: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.openURL) private var openURL
  let scope: TaskScope

  @State private var searchText = ""
  @State private var editor: TaskEditorRoute?
  @State private var capture: TaskCaptureRoute?
  @State private var pendingDelete: TaskItem?
  @State private var recentlyDeleted: TaskItem?
  @State private var selectedDate = Date.now
  @AppStorage("qingxu.calendar.showFestivals") private var showFestivalLabels = true
  @AppStorage("qingxu.calendar.showTaskIndicators") private var showTaskIndicators = true
  #if os(iOS)
  @State private var calendarExpansion: CGFloat = 0
  @State private var calendarDragStart: CGFloat?
  @State private var todayContentTopBaseline: CGFloat?
  @State private var todayContentIsAtTop = true
  @State private var todayContentPullOrigin: CGFloat?
  #endif

  private var tasks: [TaskItem] {
    let values = scope == .inbox ? store.inboxTasks : store.tasks(on: selectedDate)
    guard scope == .inbox, !searchText.isEmpty else { return values }
    return values.filter {
      $0.title.localizedStandardContains(searchText) ||
      $0.notes.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        #if os(iOS)
        if scope == .today {
          todayFixedLayout
        } else {
          standardTaskList
        }
        #else
        standardTaskList
        #endif
      }
      .qingxuScreen()
      #if os(iOS)
      .navigationTitle(scope == .today ? "" : navigationTitle)
      .navigationBarTitleDisplayMode(scope == .today ? .inline : .large)
      .qingxuInboxSearch(enabled: scope == .inbox, text: $searchText)
      #else
      .navigationTitle(navigationTitle)
      .searchable(text: $searchText, prompt: "搜索任务")
      #endif
      .toolbar {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { addButton }
        #else
        if scope == .today {
          ToolbarItem(placement: .navigationBarLeading) {
            todayNavigationMenu
          }
          ToolbarItem(placement: .principal) {
            TodayNavigationTitle(date: selectedDate, expansion: calendarExpansion)
          }
          ToolbarItem(placement: .navigationBarTrailing) {
            todayDisplayControls
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

  private var defaultEmptyState: some View {
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

  private var standardTaskList: some View {
    List {
      taskRows

      if tasks.isEmpty {
        defaultEmptyState
          .frame(maxWidth: .infinity)
          .padding(.top, 120)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
    .environment(\.defaultMinListRowHeight, 1)
  }

  @ViewBuilder
  private var taskRows: some View {
    ForEach(tasks) { task in
      TaskRow(
        task: task,
        style: scope == .today ? .todayPanel : .card,
        scheduleLabel: scope == .today ? selectedDateLabel : nil
      ) {
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

  #if os(iOS)
  private var todayFixedLayout: some View {
    VStack(spacing: 0) {
      TodayExpandableCalendar(
        selection: $selectedDate,
        expansion: $calendarExpansion,
        showsFestivals: showFestivalLabels,
        showsTaskIndicators: showTaskIndicators
      )
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .background(QingxuPalette.background)
      .contentShape(Rectangle())
      .gesture(todayCalendarDrag)
      .zIndex(1)

      List {
        GeometryReader { geometry in
          Color.clear.preference(
            key: TodayTaskScrollOffsetKey.self,
            value: geometry.frame(in: .named(TodayTaskScrollSpace.name)).minY
          )
        }
        .frame(height: 0)
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        TodayTaskPanelHeader(title: selectedDateLabel)
          .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)

        taskRows

        if tasks.isEmpty {
          TodayEmptyState()
            .frame(maxWidth: .infinity)
            .padding(.top, 58)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

          Color.clear
            .frame(height: 360)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain)
      .environment(\.defaultMinListRowHeight, 1)
      .scrollContentBackground(.hidden)
      .coordinateSpace(name: TodayTaskScrollSpace.name)
      .onPreferenceChange(TodayTaskScrollOffsetKey.self) { offset in
        if todayContentTopBaseline == nil { todayContentTopBaseline = offset }
        let baseline = todayContentTopBaseline ?? offset
        todayContentIsAtTop = offset >= baseline - 1
      }
      // The calendar owns the vertical gesture while it is expanded. This
      // keeps the task list still until the month has collapsed back to a week.
      .scrollDisabled(calendarExpansion > 0.001)
      .simultaneousGesture(todayContentPullGesture)
      .background(QingxuPalette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .padding(.horizontal, 12)
    }
  }
  #endif

  private var selectedDateLabel: String {
    let calendar = Calendar.autoupdatingCurrent
    if calendar.isDateInToday(selectedDate) { return "今天" }
    if calendar.isDateInTomorrow(selectedDate) { return "明天" }
    return selectedDate.formatted(.dateTime.month().day())
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

  #if os(iOS)
  private var todayNavigationMenu: some View {
    Menu {
      Button { openAppTab("inbox") } label: {
        Label("收集箱", systemImage: "tray")
      }
      Button { openAppTab("today") } label: {
        Label("今天", systemImage: "calendar")
      }
      Button { openAppTab("pomodoro") } label: {
        Label("番茄钟", systemImage: "timer")
      }
      Button { openAppTab("rss") } label: {
        Label("RSS", systemImage: "dot.radiowaves.left.and.right")
      }
      Divider()
      Button { openAppTab("settings") } label: {
        Label("设置", systemImage: "gearshape")
      }
    } label: {
      Image(systemName: "sidebar.left")
        .font(.system(size: 17, weight: .medium))
        .frame(width: 40, height: 40)
        .background(QingxuPalette.surface, in: Circle())
        .overlay(Circle().stroke(QingxuPalette.separator.opacity(0.7), lineWidth: 0.5))
    }
    .accessibilityLabel("打开导航")
  }

  private var todayDisplayControls: some View {
    HStack(spacing: 0) {
      Button {
        setCalendarExpanded(calendarExpansion < 0.5)
      } label: {
        Image(systemName: calendarExpansion < 0.5
          ? "calendar.day.timeline.left"
          : "calendar")
          .font(.system(size: 16, weight: .medium))
          .frame(width: 42, height: 40)
      }
      .accessibilityLabel(calendarExpansion < 0.5 ? "显示整月" : "显示当前周")

      Rectangle()
        .fill(QingxuPalette.separator.opacity(0.72))
        .frame(width: 0.5, height: 18)

      Menu {
        Menu {
          Button {
            setCalendarExpanded(false)
          } label: {
            Label("当前周", systemImage: calendarExpansion < 0.5 ? "checkmark" : "calendar")
          }
          Button {
            setCalendarExpanded(true)
          } label: {
            Label("整月", systemImage: calendarExpansion >= 0.5 ? "checkmark" : "calendar")
          }
        } label: {
          Label("显示范围", systemImage: "line.3.horizontal.decrease")
        }

        Menu {
          Toggle(isOn: $showFestivalLabels) {
            Label("节日", systemImage: "leaf")
          }
          Toggle(isOn: $showTaskIndicators) {
            Label("任务标记", systemImage: "circlebadge")
          }
        } label: {
          Label("显示设置", systemImage: "slider.horizontal.3")
        }

        Button {
          capture = TaskCaptureRoute(scope: .today, scheduledAt: selectedDate)
        } label: {
          Label("安排任务", systemImage: "calendar.badge.plus")
        }

        Button { openAppTab("rss") } label: {
          Label("RSS 订阅", systemImage: "dot.radiowaves.left.and.right")
        }

        Divider()

        Button {
          withAnimation(.easeInOut(duration: 0.28)) { selectedDate = .now }
        } label: {
          Label("回到今天", systemImage: "calendar.badge.clock")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 42, height: 40)
      }
      .accessibilityLabel("更多日历操作")
    }
    .foregroundStyle(QingxuPalette.ink)
    .background(QingxuPalette.surface, in: Capsule())
    .overlay(Capsule().stroke(QingxuPalette.separator.opacity(0.7), lineWidth: 0.5))
  }

  private func setCalendarExpanded(_ expanded: Bool) {
    withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 0.9, blendDuration: 0.08)) {
      calendarExpansion = expanded ? 1 : 0
    }
    UISelectionFeedbackGenerator().selectionChanged()
  }

  private func openAppTab(_ host: String) {
    guard let url = URL(string: "qingxu://\(host)") else { return }
    openURL(url)
  }
  #endif

  private func dismissCapture() {
    withAnimation(.easeOut(duration: 0.2)) { capture = nil }
  }

  #if os(iOS)
  private var todayCalendarDrag: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        guard scope == .today,
              capture == nil,
              abs(value.translation.height) > abs(value.translation.width)
        else { return }
        if calendarDragStart == nil { calendarDragStart = calendarExpansion }
        let start = calendarDragStart ?? calendarExpansion
        calendarExpansion = min(
          1,
          max(0, start + value.translation.height / TodayCalendarMetrics.expansionDistance)
        )
      }
      .onEnded { value in
        guard scope == .today, let start = calendarDragStart else { return }
        let projected = start
          + value.predictedEndTranslation.height / TodayCalendarMetrics.expansionDistance
        let target: CGFloat = projected > 0.45 ? 1 : 0
        calendarDragStart = nil
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.08)) {
          calendarExpansion = target
        }
        if (start < 0.5 && target == 1) || (start >= 0.5 && target == 0) {
          UISelectionFeedbackGenerator().selectionChanged()
        }
      }
  }

  private var todayContentPullGesture: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        guard capture == nil,
              abs(value.translation.height) > abs(value.translation.width)
        else { return }

        let isExpanding = value.translation.height > 0
        let isCollapsing = value.translation.height < 0 && calendarExpansion > 0
        guard isCollapsing || (isExpanding && todayContentIsAtTop) else { return }

        if todayContentPullOrigin == nil {
          todayContentPullOrigin = value.translation.height
          calendarDragStart = calendarExpansion
        }

        let origin = todayContentPullOrigin ?? value.translation.height
        let start = calendarDragStart ?? calendarExpansion
        let distance = isExpanding
          ? max(0, value.translation.height - origin)
          : min(0, value.translation.height - origin)
        calendarExpansion = min(
          1,
          max(0, start + distance / TodayCalendarMetrics.expansionDistance)
        )
      }
      .onEnded { value in
        defer {
          todayContentPullOrigin = nil
          calendarDragStart = nil
        }
        guard let origin = todayContentPullOrigin,
              let start = calendarDragStart
        else { return }

        let projectedDistance = value.translation.height >= 0
          ? max(0, value.predictedEndTranslation.height - origin)
          : min(0, value.predictedEndTranslation.height - origin)
        let projected = start + projectedDistance / TodayCalendarMetrics.expansionDistance
        let target: CGFloat = projected > 0.45 ? 1 : 0
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.08)) {
          calendarExpansion = target
        }
        if (start < 0.5 && target == 1) || (start >= 0.5 && target == 0) {
          UISelectionFeedbackGenerator().selectionChanged()
        }
      }
  }
  #endif

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

private enum TaskRowStyle {
  case card
  case todayPanel
}

private struct TaskRow: View {
  let task: TaskItem
  let style: TaskRowStyle
  let scheduleLabel: String?
  let toggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Button(action: toggle) {
        if style == .todayPanel {
          ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .stroke(
                task.status == .completed ? QingxuPalette.accent : QingxuPalette.quiet.opacity(0.55),
                lineWidth: 1.6
              )
              .frame(width: 23, height: 23)
            if task.status == .completed {
              Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(QingxuPalette.accent)
            }
          }
        } else {
          Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(task.status == .completed ? QingxuPalette.accent : QingxuPalette.quiet)
        }
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(style == .todayPanel ? .title3.weight(.regular) : .body.weight(.medium))
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
      } else if let scheduleLabel {
        Text(scheduleLabel)
          .font(.subheadline)
          .foregroundStyle(QingxuPalette.accent)
      }
    }
    .padding(.horizontal, style == .todayPanel ? 4 : 16)
    .padding(.vertical, style == .todayPanel ? 15 : 13)
    .background {
      if style == .card {
        QingxuPalette.surface
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
    }
  }
}

#if os(iOS)
private extension View {
  @ViewBuilder
  func qingxuInboxSearch(enabled: Bool, text: Binding<String>) -> some View {
    if enabled {
      searchable(
        text: text,
        placement: .navigationBarDrawer(displayMode: .automatic),
        prompt: "搜索任务"
      )
    } else {
      self
    }
  }
}

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

private enum TodayCalendarMetrics {
  static let rowHeight: CGFloat = 52
  static let expansionDistance = rowHeight * 5
}

private enum TodayTaskScrollSpace {
  static let name = "qingxu.today.task-scroll"
}

private struct TodayTaskScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

private struct TodayTaskPanelHeader: View {
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Capsule()
        .fill(QingxuPalette.separator.opacity(0.95))
        .frame(width: 34, height: 4)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)

      Text(title)
        .font(.title2.weight(.bold))
        .foregroundStyle(QingxuPalette.ink)
    }
  }
}

private struct TodayNavigationTitle: View {
  let date: Date
  let expansion: CGFloat

  private let calendar = Calendar.autoupdatingCurrent
  private let months = [
    "一月", "二月", "三月", "四月", "五月", "六月",
    "七月", "八月", "九月", "十月", "十一月", "十二月"
  ]
  private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

  var body: some View {
    VStack(spacing: 0) {
      Text(monthTitle)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(QingxuPalette.ink.opacity(0.48 + 0.52 * Double(expansion)))
      Text(dayTitle)
        .font(.headline)
        .foregroundStyle(QingxuPalette.ink.opacity(1 - 0.34 * Double(expansion)))
        .opacity(1 - expansion)
        .frame(height: max(0, 20 * (1 - expansion)))
        .clipped()
    }
    .accessibilityElement(children: .combine)
  }

  private var monthTitle: String {
    months[calendar.component(.month, from: date) - 1]
  }

  private var dayTitle: String {
    if calendar.isDateInToday(date) { return "今天" }
    let day = calendar.component(.day, from: date)
    let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
    return "\(day)日 \(weekday)"
  }
}

private struct TodayExpandableCalendar: View {
  @Binding var selection: Date
  @Binding var expansion: CGFloat
  let showsFestivals: Bool
  let showsTaskIndicators: Bool

  private let rowHeight = TodayCalendarMetrics.rowHeight
  private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.locale = Locale(identifier: "zh_CN")
    value.firstWeekday = 2
    return value
  }

  private var progress: CGFloat {
    min(1, max(0, expansion))
  }

  private var monthStart: Date {
    calendar.dateInterval(of: .month, for: selection)?.start
      ?? calendar.startOfDay(for: selection)
  }

  private var gridDays: [Date] {
    let weekday = calendar.component(.weekday, from: monthStart)
    let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
    let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart
    return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
  }

  private var selectedRow: Int {
    (gridDays.firstIndex { calendar.isDate($0, inSameDayAs: selection) } ?? 0) / 7
  }

  private var revealedRows: CGFloat {
    5 * progress
  }

  /// Reveal the month from both sides of the selected week. Near the first or
  /// last week, unused space naturally spills to the side that still has rows.
  private var revealedLeadingRows: CGFloat {
    let leadingCapacity = CGFloat(selectedRow)
    let trailingCapacity = CGFloat(5 - selectedRow)
    var leading = min(leadingCapacity, revealedRows / 2)
    let trailing = min(trailingCapacity, revealedRows / 2)
    leading += min(leadingCapacity - leading, revealedRows - leading - trailing)
    return leading
  }

  private var gridOffset: CGFloat {
    -(CGFloat(selectedRow) - revealedLeadingRows) * rowHeight
  }

  private var visibleGridHeight: CGFloat {
    rowHeight * (1 + revealedRows)
  }

  var body: some View {
    VStack(spacing: 5) {
      HStack(spacing: 0) {
        ForEach(weekdays, id: \.self) { value in
          Text(value)
            .font(.caption)
            .foregroundStyle(QingxuPalette.quiet.opacity(0.8))
            .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 24)

      ZStack(alignment: .top) {
        TodayCalendarGrid(
          days: gridDays,
          selection: $selection,
          showsFestivals: showsFestivals,
          showsTaskIndicators: showsTaskIndicators,
          expansion: progress,
          selectedRow: selectedRow,
          revealedLeadingRows: revealedLeadingRows
        )
        .equatable()
        .offset(y: gridOffset)
      }
      .frame(height: visibleGridHeight, alignment: .top)
      .clipped()
    }
    .contentShape(Rectangle())
  }
}

private struct TodayCalendarGrid: View, Equatable {
  @EnvironmentObject private var store: AppStore
  let days: [Date]
  @Binding var selection: Date
  let showsFestivals: Bool
  let showsTaskIndicators: Bool
  let expansion: CGFloat
  let selectedRow: Int
  let revealedLeadingRows: CGFloat

  private let rowHeight = TodayCalendarMetrics.rowHeight

  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.locale = Locale(identifier: "zh_CN")
    value.firstWeekday = 2
    return value
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.days == rhs.days
      && lhs.selection == rhs.selection
      && lhs.showsFestivals == rhs.showsFestivals
      && lhs.showsTaskIndicators == rhs.showsTaskIndicators
      && lhs.expansion == rhs.expansion
      && lhs.selectedRow == rhs.selectedRow
      && lhs.revealedLeadingRows == rhs.revealedLeadingRows
  }

  var body: some View {
    let markedDays = taskDays

    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
      spacing: 0
    ) {
      ForEach(Array(days.enumerated()), id: \.element) { index, day in
        dayCell(
          day,
          hasTasks: markedDays.contains(calendar.startOfDay(for: day)),
          visibility: rowVisibility(index / 7)
        )
      }
    }
    .animation(.easeOut(duration: 0.16), value: selection)
  }

  private var taskDays: Set<Date> {
    guard showsTaskIndicators else { return [] }
    return Set(store.tasks.lazy
      .filter(\.isOpen)
      .flatMap { [$0.startAt, $0.deadlineAt].compactMap { $0 } }
      .map { calendar.startOfDay(for: $0) })
  }

  private func rowVisibility(_ row: Int) -> CGFloat {
    guard row != selectedRow else { return 1 }
    let viewportStart = CGFloat(selectedRow) - revealedLeadingRows
    let viewportEnd = viewportStart + 1 + expansion * 5
    let visiblePart = min(CGFloat(row + 1), viewportEnd)
      - max(CGFloat(row), viewportStart)
    return min(1, max(0, visiblePart))
  }

  private func dayCell(_ day: Date, hasTasks: Bool, visibility: CGFloat) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selection)
    let isToday = calendar.isDateInToday(day)
    let isCurrentMonth = calendar.isDate(day, equalTo: selection, toGranularity: .month)
    let festival = showsFestivals ? QingxuFestivalCalendar.title(for: day) : nil

    return Button {
      withAnimation(.easeInOut(duration: 0.18)) { selection = day }
    } label: {
      VStack(spacing: 0) {
        Text("\(calendar.component(.day, from: day))")
          .font(.system(size: 16, weight: isSelected ? .semibold : .medium, design: .rounded))
          .frame(width: 38, height: 38)
          .foregroundStyle(dayForeground(
            selected: isSelected,
            today: isToday,
            currentMonth: isCurrentMonth
          ))
          .background(isSelected ? QingxuPalette.accent : Color.clear, in: Circle())

        ZStack {
          if let festival {
            Text(festival)
              .font(.system(size: 9, weight: .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
              .foregroundStyle(isSelected ? Color.white.opacity(0.92) : QingxuPalette.success)
          } else if hasTasks {
            Circle()
              .fill(isSelected ? Color.white.opacity(0.9) : QingxuPalette.accent)
              .frame(width: 3.5, height: 3.5)
          }
        }
        .frame(height: 11)
      }
      .frame(maxWidth: .infinity)
      .frame(height: rowHeight)
    }
    .buttonStyle(.plain)
    .opacity(Double(0.14 + 0.86 * visibility))
    .scaleEffect(0.975 + 0.025 * visibility)
    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
  }

  private func dayForeground(selected: Bool, today: Bool, currentMonth: Bool) -> Color {
    if selected { return .white }
    if today { return QingxuPalette.accent }
    return currentMonth ? QingxuPalette.ink : QingxuPalette.quiet.opacity(0.38)
  }
}

private struct TodayEmptyState: View {
  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
          .fill(QingxuPalette.selected.opacity(0.52))
          .frame(width: 156, height: 106)
          .rotationEffect(.degrees(-8))

        Image(systemName: "sparkle")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(QingxuPalette.accent.opacity(0.62))
          .offset(x: -69, y: -42)
        Image(systemName: "sparkle")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(QingxuPalette.quiet.opacity(0.7))
          .offset(x: 72, y: 35)

        Image(systemName: "calendar")
          .font(.system(size: 68, weight: .light))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(QingxuPalette.accent)
          .rotationEffect(.degrees(4))
      }
      .frame(height: 126)

      VStack(spacing: 7) {
        Text("你这一天没有任务")
          .font(.title3.weight(.medium))
          .foregroundStyle(QingxuPalette.ink)
        Text("放松一下吧")
          .font(.subheadline)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .accessibilityElement(children: .combine)
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
