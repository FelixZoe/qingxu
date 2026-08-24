import Combine
import Foundation

enum SyncPhase: Equatable {
  case localOnly
  case syncing
  case synced(Date)
  case failed(String)

  var title: String {
    switch self {
    case .localOnly: "仅保存在本地"
    case .syncing: "正在同步…"
    case .synced: "已同步"
    case .failed: "同步失败"
    }
  }
}

private struct SyncMetadata: Codable {
  var revision: UInt64
  var dirtyTaskIDs: Set<String>
  var pomodoroDirty: Bool
}

@MainActor
final class AppStore: ObservableObject {
  @Published private(set) var tasks: [TaskItem] = []
  @Published private(set) var pomodoro = PomodoroState.initial()
  @Published var syncSettings = SyncSettings()
  @Published private(set) var syncPhase: SyncPhase = .localOnly
  @Published private(set) var displayedRemainingSeconds = 25 * 60

  private let client = SyncClient()
  private var clockTask: Task<Void, Never>?
  private var pendingSync: Task<Void, Never>?
  private var changeFeedTask: Task<Void, Never>?
  private var serverOffset: TimeInterval = 0
  private var lastAutomaticSync = Date()
  private var lastRevision: UInt64 = 0
  private var changeFeedGeneration = 0
  private var dirtyTaskIDs: Set<String> = []
  private var pomodoroDirty = false
  private var activeSync: Task<Bool, Never>?

  init() {
    tasks = QingxuFiles.load([TaskItem].self, name: "tasks.json") ?? []
    pomodoro = QingxuFiles.load(PomodoroState.self, name: "pomodoro.json") ?? .initial()
    syncSettings = QingxuFiles.load(SyncSettings.self, name: "sync.json") ?? SyncSettings()
    syncSettings.token = SecureSyncToken.read()
    if let metadata = QingxuFiles.load(SyncMetadata.self, name: "sync-state.json") {
      lastRevision = metadata.revision
      dirtyTaskIDs = metadata.dirtyTaskIDs
      pomodoroDirty = metadata.pomodoroDirty
    } else {
      dirtyTaskIDs = Set(tasks.map(\.id))
      pomodoroDirty = true
    }
    if syncSettings.deviceName.isEmpty {
      syncSettings.deviceName = ProcessInfo.processInfo.hostName
    }
    displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
    refreshSystemSurfaces()
    startClock()
    if syncSettings.autoSync && syncSettings.isConfigured {
      scheduleSync(delay: .milliseconds(350))
    }
    configureChangeFeed()
  }

  deinit {
    clockTask?.cancel()
    pendingSync?.cancel()
    changeFeedTask?.cancel()
    activeSync?.cancel()
  }

  var inboxTasks: [TaskItem] {
    visibleTasks.filter { $0.status == .open }.sorted(by: taskOrder)
  }

  /// The task screens keep completed items visible so completion feels
  /// reversible. Open items stay first; completed items sink below them.
  var displayedInboxTasks: [TaskItem] {
    visibleTasks.sorted(by: displayTaskOrder)
  }

  var todayTasks: [TaskItem] {
    tasks(on: estimatedNow)
  }

  func tasks(on date: Date) -> [TaskItem] {
    let calendar = Calendar.autoupdatingCurrent
    return visibleTasks.filter { task in
      guard task.status == .open else { return false }
      return [task.startAt, task.deadlineAt]
        .compactMap { $0 }
        .contains { calendar.isDate($0, inSameDayAs: date) }
    }.sorted(by: taskOrder)
  }

  func displayedTasks(on date: Date) -> [TaskItem] {
    let calendar = Calendar.autoupdatingCurrent
    return visibleTasks.filter { task in
      [task.startAt, task.deadlineAt]
        .compactMap { $0 }
        .contains { calendar.isDate($0, inSameDayAs: date) }
    }.sorted(by: displayTaskOrder)
  }

  var completedTasks: [TaskItem] {
    visibleTasks.filter { $0.status == .completed }.sorted {
      ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
    }
  }

  var estimatedNow: Date { Date().addingTimeInterval(serverOffset) }

  @discardableResult
  func addTask(title: String, notes: String = "", forToday: Bool = false) -> TaskItem? {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTitle.isEmpty else { return nil }
    let now = estimatedNow
    let task = TaskItem(
      id: UUID().uuidString,
      title: cleanTitle,
      notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
      status: .open,
      projectId: nil,
      priority: nil,
      startAt: forToday ? Calendar.autoupdatingCurrent.startOfDay(for: now) : nil,
      deadlineAt: nil,
      completedAt: nil,
      order: Int64(now.timeIntervalSince1970 * 1_000),
      createdAt: now,
      updatedAt: now,
      deletedAt: nil
    )
    tasks.append(task)
    changed(taskID: task.id)
    return task
  }

  func updateTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    var updated = task
    updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.updatedAt = estimatedNow
    tasks[index] = updated
    changed(taskID: updated.id)
  }

  func toggleTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    let now = estimatedNow
    tasks[index].status = tasks[index].status == .completed ? .open : .completed
    tasks[index].completedAt = tasks[index].status == .completed ? now : nil
    tasks[index].updatedAt = now
    changed(taskID: tasks[index].id)
  }

  func deleteTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    let now = estimatedNow
    tasks[index].deletedAt = now
    tasks[index].updatedAt = now
    changed(taskID: tasks[index].id)
  }

  func restoreTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    tasks[index].deletedAt = nil
    tasks[index].updatedAt = estimatedNow
    changed(taskID: tasks[index].id)
  }

  func setPomodoroMode(_ mode: PomodoroMode) {
    pomodoro.mode = mode
    pomodoro.status = .idle
    pomodoro.endsAt = nil
    pomodoro.startedAt = nil
    pomodoro.remainingSeconds = pomodoro.timerDirection == .countUp ? 0 : pomodoro.duration(for: mode)
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func setPomodoroTimerDirection(_ direction: PomodoroTimerDirection) {
    pomodoro.timerDirection = direction
    pomodoro.mode = .focus
    pomodoro.status = .idle
    pomodoro.endsAt = nil
    pomodoro.startedAt = nil
    pomodoro.remainingSeconds = direction == .countUp ? 0 : pomodoro.duration(for: .focus)
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func togglePomodoro() {
    let now = estimatedNow
    if pomodoro.status == .running {
      pomodoro.remainingSeconds = pomodoro.remaining(at: now)
      pomodoro.endsAt = nil
      pomodoro.startedAt = nil
      pomodoro.status = .paused
    } else {
      if pomodoro.timerDirection == .countUp {
        pomodoro.startedAt = now
        pomodoro.endsAt = nil
      } else {
        let remaining = max(1, pomodoro.remainingSeconds)
        pomodoro.endsAt = now.addingTimeInterval(TimeInterval(remaining))
        pomodoro.startedAt = nil
      }
      pomodoro.status = .running
    }
    pomodoro.updatedAt = now
    pomodoroChanged()
  }

  func resetPomodoro() {
    pomodoro.status = .idle
    pomodoro.endsAt = nil
    pomodoro.startedAt = nil
    pomodoro.remainingSeconds = pomodoro.timerDirection == .countUp
      ? 0
      : pomodoro.duration(for: pomodoro.mode)
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func updateDurations(focus: Int, shortBreak: Int, longBreak: Int, longBreakEvery: Int) {
    pomodoro.focusMinutes = min(180, max(1, focus))
    pomodoro.shortBreakMinutes = min(60, max(1, shortBreak))
    pomodoro.longBreakMinutes = min(120, max(1, longBreak))
    pomodoro.longBreakEvery = min(12, max(2, longBreakEvery))
    if pomodoro.status != .running {
      pomodoro.remainingSeconds = pomodoro.timerDirection == .countUp
        ? 0
        : pomodoro.duration(for: pomodoro.mode)
    }
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func saveSyncSettings(_ settings: SyncSettings) throws {
    let serverChanged = settings.normalizedServerURL != syncSettings.normalizedServerURL
      || settings.token != syncSettings.token
    syncSettings = settings
    try SecureSyncToken.write(settings.token)
    try QingxuFiles.save(settings, name: "sync.json")
    if serverChanged {
      lastRevision = 0
      dirtyTaskIDs = Set(tasks.map(\.id))
      pomodoroDirty = true
      try persistSyncMetadata()
    }
    syncPhase = settings.autoSync ? .syncing : .localOnly
    if settings.autoSync { scheduleSync(delay: .milliseconds(100)) }
    configureChangeFeed()
  }

  func testConnection(_ settings: SyncSettings) async throws {
    try await client.testConnection(settings: settings)
  }

  @discardableResult
  func syncNow() async -> Bool {
    guard syncSettings.isConfigured else {
      syncPhase = .localOnly
      return false
    }
    if let activeSync {
      return await activeSync.value
    }
    let operation = Task { [weak self] in
      guard let self else { return false }
      return await self.performSync()
    }
    activeSync = operation
    let succeeded = await operation.value
    activeSync = nil
    return succeeded
  }

  private func performSync() async -> Bool {
    let sentTaskVersions = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in
      dirtyTaskIDs.contains(task.id) ? (task.id, task.updatedAt) : nil
    })
    let outgoingTasks = tasks.filter { sentTaskVersions[$0.id] != nil }
    let sentPomodoroVersion = pomodoroDirty ? pomodoro.updatedAt : nil
    let outgoingPomodoro = pomodoroDirty ? pomodoro : nil

    syncPhase = .syncing
    do {
      let response = try await client.sync(
        settings: syncSettings,
        tasks: outgoingTasks,
        pomodoro: outgoingPomodoro
      )
      let localTasksBeforeMerge = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
      let localPomodoroBeforeMerge = pomodoro
      serverOffset = response.serverTime.timeIntervalSinceNow

      tasks = merge(remoteTasks: response.tasks, into: tasks)
      if let remote = response.pomodoro, remote.updatedAt >= pomodoro.updatedAt {
        pomodoro = remote
      }

      for (id, sentVersion) in sentTaskVersions
      where localTasksBeforeMerge[id]?.updatedAt == sentVersion {
        dirtyTaskIDs.remove(id)
      }
      if let sentPomodoroVersion,
         localPomodoroBeforeMerge.updatedAt == sentPomodoroVersion {
        pomodoroDirty = false
      }
      lastRevision = max(lastRevision, response.revision ?? 0)
      try persistAll()
      try persistSyncMetadata()
      displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
      syncPhase = .synced(.now)
      lastAutomaticSync = .now
      refreshSystemSurfaces()
      if !dirtyTaskIDs.isEmpty || pomodoroDirty {
        scheduleSync(delay: .milliseconds(40))
      }
      return true
    } catch {
      syncPhase = .failed(error.localizedDescription)
      return false
    }
  }

  private var visibleTasks: [TaskItem] { tasks.filter { $0.deletedAt == nil } }

  private func taskOrder(_ left: TaskItem, _ right: TaskItem) -> Bool {
    if left.order == right.order { return left.createdAt < right.createdAt }
    return left.order < right.order
  }

  private func displayTaskOrder(_ left: TaskItem, _ right: TaskItem) -> Bool {
    if left.status != right.status {
      return left.status == .open
    }
    if left.status == .completed {
      return (left.completedAt ?? left.updatedAt) > (right.completedAt ?? right.updatedAt)
    }
    return taskOrder(left, right)
  }

  private func changed(taskID: String) {
    dirtyTaskIDs.insert(taskID)
    try? QingxuFiles.save(tasks, name: "tasks.json")
    try? persistSyncMetadata()
    refreshSystemSurfaces()
    scheduleSync()
  }

  private func pomodoroChanged() {
    pomodoroDirty = true
    displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
    try? QingxuFiles.save(pomodoro, name: "pomodoro.json")
    try? persistSyncMetadata()
    refreshSystemSurfaces()
    scheduleSync(delay: .zero)
  }

  private func persistAll() throws {
    try QingxuFiles.save(tasks, name: "tasks.json")
    try QingxuFiles.save(pomodoro, name: "pomodoro.json")
  }

  private func persistSyncMetadata() throws {
    try QingxuFiles.save(
      SyncMetadata(
        revision: lastRevision,
        dirtyTaskIDs: dirtyTaskIDs,
        pomodoroDirty: pomodoroDirty
      ),
      name: "sync-state.json"
    )
  }

  private func merge(remoteTasks: [TaskItem], into localTasks: [TaskItem]) -> [TaskItem] {
    var merged = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })
    for remote in remoteTasks {
      guard let local = merged[remote.id] else {
        merged[remote.id] = remote
        continue
      }
      if remote.updatedAt >= local.updatedAt {
        merged[remote.id] = remote
      }
    }
    return Array(merged.values)
  }

  private func scheduleSync(delay: Duration = .milliseconds(70)) {
    guard syncSettings.autoSync && syncSettings.isConfigured else { return }
    pendingSync?.cancel()
    pendingSync = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.syncNow()
    }
  }

  private func configureChangeFeed() {
    changeFeedGeneration += 1
    let generation = changeFeedGeneration
    changeFeedTask?.cancel()
    guard syncSettings.autoSync && syncSettings.isConfigured else { return }
    changeFeedTask = Task { [weak self] in
      await self?.watchChanges(generation: generation)
    }
  }

  private func watchChanges(generation: Int) async {
    var failureCount = 0
    while !Task.isCancelled && generation == changeFeedGeneration {
      do {
        let change = try await client.waitForChanges(
          settings: syncSettings,
          since: lastRevision
        )
        guard !Task.isCancelled, generation == changeFeedGeneration else { return }
        failureCount = 0
        let isNewRevision = change.revision > lastRevision
        if change.changed && isNewRevision {
          let succeeded = await syncNow()
          if !succeeded {
            failureCount = 1
            try? await Task.sleep(for: .seconds(1))
          }
        } else if isNewRevision {
          lastRevision = change.revision
          try? persistSyncMetadata()
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, generation == changeFeedGeneration else { return }
        failureCount = min(failureCount + 1, 5)
        try? await Task.sleep(for: .seconds(1 << failureCount))
      }
    }
  }

  private func startClock() {
    clockTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        self.tick()
      }
    }
  }

  private func tick() {
    displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
    if pomodoro.timerDirection == .countdown,
       pomodoro.status == .running,
       displayedRemainingSeconds == 0 {
      advancePomodoro()
    }
    let interval: TimeInterval = 5 * 60
    if syncSettings.autoSync,
       syncSettings.isConfigured,
       activeSync == nil,
       Date().timeIntervalSince(lastAutomaticSync) >= interval {
      lastAutomaticSync = .now
      Task { await syncNow() }
    }
  }

  private func advancePomodoro() {
    if pomodoro.mode == .focus {
      pomodoro.completedFocusSessions += 1
      pomodoro.mode = pomodoro.completedFocusSessions.isMultiple(of: pomodoro.longBreakEvery)
        ? .longBreak
        : .shortBreak
    } else {
      pomodoro.mode = .focus
    }
    pomodoro.status = .running
    pomodoro.startedAt = nil
    pomodoro.remainingSeconds = pomodoro.duration(for: pomodoro.mode)
    pomodoro.endsAt = estimatedNow.addingTimeInterval(TimeInterval(pomodoro.remainingSeconds))
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  private func refreshSystemSurfaces() {
    SystemFeatures.refresh(
      pomodoro: pomodoro,
      todayTaskCount: todayTasks.count,
      nextTodayTaskTitle: todayTasks.first?.title
    )
  }
}
