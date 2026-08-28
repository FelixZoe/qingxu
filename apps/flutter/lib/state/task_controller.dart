import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/sync_settings.dart';
import '../models/pomodoro_state.dart';
import '../models/task_item.dart';
import '../services/pomodoro_storage.dart';
import '../services/pomodoro_storage_base.dart';
import '../services/ios_system_features.dart';
import '../services/secure_token_storage.dart';
import '../services/secure_token_storage_base.dart';
import '../services/sync_client.dart';
import '../services/sync_client_base.dart';
import '../services/sync_settings_storage.dart';
import '../services/sync_settings_storage_base.dart';
import '../services/task_storage.dart';
import '../services/task_storage_base.dart';

enum SyncActivity { unconfigured, idle, testing, syncing, success, error }

class TaskController extends ChangeNotifier {
  TaskController({
    TaskStorageBase? storage,
    SyncSettingsStorageBase? syncSettingsStorage,
    SecureTokenStorageBase? secureTokenStorage,
    SyncClientBase? syncClient,
    PomodoroStorageBase? pomodoroStorage,
    this.syncDebounce = const Duration(milliseconds: 100),
  }) : _storage = storage ?? TaskStorage(),
       _syncSettingsStorage = syncSettingsStorage ?? SyncSettingsStorage(),
       _secureTokenStorage = secureTokenStorage ?? SecureTokenStorage(),
       _syncClient = syncClient ?? SyncClient(),
       _pomodoroStorage = pomodoroStorage ?? PomodoroStorage();

  final TaskStorageBase _storage;
  final SyncSettingsStorageBase _syncSettingsStorage;
  final SecureTokenStorageBase _secureTokenStorage;
  final SyncClientBase _syncClient;
  final PomodoroStorageBase _pomodoroStorage;
  final Duration syncDebounce;
  final List<TaskItem> _tasks = [];
  PomodoroState _pomodoro = PomodoroState.initial();
  Duration _serverClockOffset = Duration.zero;

  static const projects = <ProjectItem>[
    ProjectItem('personal', '个人', 0xFF78A4D6),
    ProjectItem('qingxu', '清序第一版', 0xFFD79468),
  ];

  String activeView = 'today';
  String search = '';
  String? selectedTaskId;

  SyncSettings _syncSettings = const SyncSettings();
  SyncActivity _syncActivity = SyncActivity.unconfigured;
  String _syncMessage = '尚未配置同步';
  DateTime? _lastSyncedAt;
  String? _lastServerTime;
  Timer? _syncDebounceTimer;
  Timer? _autoPullTimer;
  int _lastRevision = 0;
  int _changeFeedGeneration = 0;
  Future<bool>? _activeSync;
  Future<void> _saveTail = Future<void>.value();
  bool _syncQueued = false;
  int _syncConfigurationGeneration = 0;
  bool _disposed = false;

  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  SyncSettings get syncSettings => _syncSettings;
  SyncActivity get syncActivity => _syncActivity;
  String get syncMessage => _syncMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get lastServerTime => _lastServerTime;
  bool get syncSupported => _syncClient.isSupported;
  PomodoroState get pomodoro => _pomodoro;
  DateTime get estimatedServerNow =>
      DateTime.now().toUtc().add(_serverClockOffset);
  int get pomodoroRemainingSeconds => _pomodoro.remainingAt(estimatedServerNow);
  bool get isSyncBusy =>
      _syncActivity == SyncActivity.testing ||
      _syncActivity == SyncActivity.syncing;

  TaskItem? get selectedTask {
    for (final task in _tasks) {
      if (task.id == selectedTaskId && task.deletedAt == null) return task;
    }
    return null;
  }

  String get currentTitle {
    if (search.trim().isNotEmpty) return search.trim();
    if (activeView.startsWith('project:')) {
      final id = activeView.substring('project:'.length);
      return projects.where((project) => project.id == id).firstOrNull?.title ??
          '项目';
    }
    return const {
          'inbox': '收集箱',
          'today': '今天',
          'pomodoro': '番茄钟',
          'settings': '设置',
        }[activeView] ??
        '今天';
  }

  List<TaskItem> get visibleTasks {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final query = search.trim().toLowerCase();

    final result = _tasks.where((task) {
      if (task.deletedAt != null) return false;
      if (query.isNotEmpty) {
        return '${task.title}\n${task.notes}'.toLowerCase().contains(query);
      }
      if (activeView.startsWith('project:')) {
        return task.isOpen &&
            task.projectId == activeView.substring('project:'.length);
      }
      if (!task.isOpen) return false;
      final start = task.startAt?.toLocal();
      return switch (activeView) {
        'today' => start != null && start.isBefore(startTomorrow),
        'inbox' => start == null,
        _ => false,
      };
    }).toList();

    result.sort((first, second) {
      final firstDate = first.startAt?.millisecondsSinceEpoch ?? 1 << 62;
      final secondDate = second.startAt?.millisecondsSinceEpoch ?? 1 << 62;
      final dateOrder = firstDate.compareTo(secondDate);
      return dateOrder == 0 ? first.order.compareTo(second.order) : dateOrder;
    });
    return result;
  }

  Future<void> initialize() async {
    await _loadTasks();
    await _loadPomodoro();
    await _loadSyncSettings();
    if (_tasks.isEmpty) _seed();

    if (syncSupported && _syncSettings.autoSync && _syncSettings.isConfigured) {
      unawaited(syncNow());
    }
    _configureAutoPull();
    _configureChangeFeed();
    _publishSystemSnapshot();
  }

  Future<void> _loadPomodoro() async {
    try {
      final encoded = await _pomodoroStorage.load();
      if (encoded == null || encoded.isEmpty) return;
      _pomodoro = PomodoroState.fromJson(
        Map<String, Object?>.from(jsonDecode(encoded) as Map<dynamic, dynamic>),
      );
    } on Object {
      _pomodoro = PomodoroState.initial();
    }
  }

  Future<void> _loadTasks() async {
    final encoded = await _storage.load();
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      _tasks.addAll(
        decoded.map(
          (value) => TaskItem.fromJson(
            Map<String, Object?>.from(value as Map<dynamic, dynamic>),
          ),
        ),
      );
    } on Object {
      _tasks.clear();
    }
  }

  Future<void> _loadSyncSettings() async {
    final encoded = await _syncSettingsStorage.load();
    String? legacyToken;
    String? securityWarning;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = Map<String, Object?>.from(
          jsonDecode(encoded) as Map<dynamic, dynamic>,
        );
        legacyToken = decoded['token'] as String?;
        _syncSettings = SyncSettings.fromJson(decoded);
      } on Object {
        _syncSettings = const SyncSettings();
      }
    }
    String? secureToken;
    var secureReadSucceeded = false;
    try {
      secureToken = await _secureTokenStorage.read();
      secureReadSucceeded = true;
    } on Object {
      securityWarning = '无法读取系统安全存储，请重新输入同步密钥';
    }
    final loadedToken = secureToken?.trim().isNotEmpty == true
        ? secureToken!.trim()
        : legacyToken?.trim() ?? '';
    _syncSettings = SyncSettings(
      serverUrl: _syncSettings.serverUrl,
      token: loadedToken,
      deviceName: _syncSettings.deviceName,
      autoSync: _syncSettings.autoSync,
    ).normalized();

    if (legacyToken?.trim().isNotEmpty == true && secureReadSucceeded) {
      var safeToRemoveLegacyToken = secureToken?.trim().isNotEmpty == true;
      if (!safeToRemoveLegacyToken) {
        try {
          await _secureTokenStorage.write(legacyToken!);
          safeToRemoveLegacyToken = true;
        } on Object {
          securityWarning = '旧密钥无法迁移到系统安全存储，已保留旧密钥以防止丢失';
        }
      }
      if (safeToRemoveLegacyToken) {
        try {
          await _syncSettingsStorage.save(jsonEncode(_syncSettings.toJson()));
        } on Object {
          securityWarning ??= '旧配置清理失败，请重新保存同步设置';
        }
      }
    }
    if (_syncSettings.deviceName.isEmpty) {
      _syncSettings = SyncSettings(
        serverUrl: _syncSettings.serverUrl,
        token: _syncSettings.token,
        deviceName: _syncClient.defaultDeviceName,
        autoSync: _syncSettings.autoSync,
      );
    }
    _syncActivity = _syncSettings.isConfigured
        ? SyncActivity.idle
        : SyncActivity.unconfigured;
    _syncMessage =
        securityWarning ?? (_syncSettings.isConfigured ? '等待同步' : '尚未配置同步');
  }

  void selectView(String view) {
    activeView = view;
    search = '';
    selectedTaskId = null;
    _notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    _notifyListeners();
  }

  void selectTask(String? id) {
    selectedTaskId = id;
    _notifyListeners();
  }

  TaskItem? addTask(String title, {bool openEditor = false}) {
    final value = title.trim();
    if (value.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final local = DateTime.now();
    final today = DateTime(local.year, local.month, local.day, 9).toUtc();
    final task = TaskItem(
      id: 'task-${now.microsecondsSinceEpoch}',
      title: value,
      notes: '',
      status: TaskStatus.open,
      projectId: activeView.startsWith('project:')
          ? activeView.substring('project:'.length)
          : null,
      startAt: activeView == 'today' ? today : null,
      deadlineAt: null,
      completedAt: null,
      order: now.microsecondsSinceEpoch,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    _tasks.add(task);
    if (openEditor) selectedTaskId = task.id;
    _changed();
    return task;
  }

  void updateTask(TaskItem updated) {
    final index = _tasks.indexWhere((task) => task.id == updated.id);
    if (index < 0) return;
    _tasks[index] = updated.copyWith(updatedAt: DateTime.now().toUtc());
    _changed();
  }

  void toggleTask(TaskItem task) {
    final completed = task.status != TaskStatus.completed;
    updateTask(
      task.copyWith(
        status: completed ? TaskStatus.completed : TaskStatus.open,
        completedAt: completed ? DateTime.now().toUtc() : null,
        clearCompletedAt: !completed,
      ),
    );
  }

  void deleteTask(TaskItem task) {
    selectedTaskId = null;
    updateTask(task.copyWith(deletedAt: DateTime.now().toUtc()));
  }

  void restoreTask(TaskItem task) {
    updateTask(task.copyWith(clearDeletedAt: true));
  }

  void togglePomodoro() {
    final now = estimatedServerNow;
    if (_pomodoro.status == PomodoroStatus.running) {
      _setPomodoro(
        _pomodoro.copyWith(
          status: PomodoroStatus.paused,
          remainingSeconds: _pomodoro.remainingAt(now),
          clearEndsAt: true,
          clearStartedAt: true,
          updatedAt: now,
        ),
      );
      return;
    }
    final remaining = _pomodoro.timerDirection == PomodoroTimerDirection.countUp
        ? _pomodoro.remainingSeconds
        : (_pomodoro.remainingSeconds > 0
              ? _pomodoro.remainingSeconds
              : _pomodoro.configuredDurationFor(_pomodoro.mode).inSeconds);
    _setPomodoro(
      _pomodoro.copyWith(
        status: PomodoroStatus.running,
        phaseId: '${now.microsecondsSinceEpoch}-${_pomodoro.mode.name}',
        remainingSeconds: remaining,
        endsAt: _pomodoro.timerDirection == PomodoroTimerDirection.countdown
            ? now.add(Duration(seconds: remaining))
            : null,
        clearEndsAt: _pomodoro.timerDirection == PomodoroTimerDirection.countUp,
        startedAt: _pomodoro.timerDirection == PomodoroTimerDirection.countUp ? now : null,
        clearStartedAt: _pomodoro.timerDirection == PomodoroTimerDirection.countdown,
        updatedAt: now,
      ),
    );
  }

  void resetPomodoro() {
    final now = estimatedServerNow;
    _setPomodoro(
      _pomodoro.copyWith(
        status: PomodoroStatus.idle,
        remainingSeconds: _pomodoro.timerDirection == PomodoroTimerDirection.countUp
            ? 0
            : _pomodoro.configuredDurationFor(_pomodoro.mode).inSeconds,
        clearEndsAt: true,
        clearStartedAt: true,
        updatedAt: now,
      ),
    );
  }

  void selectPomodoroMode(PomodoroMode mode) {
    final now = estimatedServerNow;
    _setPomodoro(
      _pomodoro.copyWith(
        mode: mode,
        status: PomodoroStatus.idle,
        remainingSeconds: _pomodoro.configuredDurationFor(mode).inSeconds,
        clearEndsAt: true,
        clearStartedAt: true,
        updatedAt: now,
      ),
    );
  }

  void selectPomodoroTimerDirection(PomodoroTimerDirection direction) {
    final now = estimatedServerNow;
    _setPomodoro(
      _pomodoro.copyWith(
        mode: PomodoroMode.focus,
        status: PomodoroStatus.idle,
        timerDirection: direction,
        remainingSeconds: direction == PomodoroTimerDirection.countUp
            ? 0
            : _pomodoro.configuredDurationFor(PomodoroMode.focus).inSeconds,
        clearEndsAt: true,
        clearStartedAt: true,
        updatedAt: now,
      ),
    );
  }

  void skipPomodoro() => _advancePomodoro(countFocus: false);

  void updatePomodoroDurations({
    required int focusMinutes,
    required int shortBreakMinutes,
    required int longBreakMinutes,
    int? longBreakEvery,
    int? dailyFocusGoal,
  }) {
    final now = estimatedServerNow;
    final updated = _pomodoro.copyWith(
      status: PomodoroStatus.idle,
      focusMinutes: focusMinutes.clamp(1, 180),
      shortBreakMinutes: shortBreakMinutes.clamp(1, 60),
      longBreakMinutes: longBreakMinutes.clamp(1, 120),
      longBreakEvery: (longBreakEvery ?? _pomodoro.longBreakEvery).clamp(2, 12),
      dailyFocusGoal: (dailyFocusGoal ?? _pomodoro.dailyFocusGoal).clamp(1, 24),
      clearEndsAt: true,
      updatedAt: now,
    );
    _setPomodoro(
      updated.copyWith(
        remainingSeconds: updated.configuredDurationFor(updated.mode).inSeconds,
      ),
    );
  }

  bool advancePomodoroIfNeeded() {
    if (_pomodoro.status != PomodoroStatus.running ||
        _pomodoro.timerDirection == PomodoroTimerDirection.countUp ||
        _pomodoro.remainingAt(estimatedServerNow) > 0) {
      return false;
    }
    _advancePomodoro(countFocus: _pomodoro.mode == PomodoroMode.focus);
    return true;
  }

  void _advancePomodoro({required bool countFocus}) {
    final now = estimatedServerNow;
    final completed = _pomodoro.completedFocusSessions + (countFocus ? 1 : 0);
    final nextMode = _pomodoro.mode == PomodoroMode.focus
        ? (completed > 0 && completed % _pomodoro.longBreakEvery == 0
              ? PomodoroMode.longBreak
              : PomodoroMode.shortBreak)
        : PomodoroMode.focus;
    final history = <FocusSessionRecord>[
      if (countFocus)
        FocusSessionRecord(
          id: '${now.microsecondsSinceEpoch}-focus',
          startedAt: now.subtract(
            _pomodoro.configuredDurationFor(PomodoroMode.focus),
          ),
          endedAt: now,
          durationSeconds: _pomodoro
              .configuredDurationFor(PomodoroMode.focus)
              .inSeconds,
          completed: true,
        ),
      ..._pomodoro.focusHistory,
    ];
    _setPomodoro(
      PomodoroState(
        mode: nextMode,
        status: PomodoroStatus.running,
        remainingSeconds: _pomodoro.configuredDurationFor(nextMode).inSeconds,
        completedFocusSessions: completed,
        focusMinutes: _pomodoro.focusMinutes,
        shortBreakMinutes: _pomodoro.shortBreakMinutes,
        longBreakMinutes: _pomodoro.longBreakMinutes,
        longBreakEvery: _pomodoro.longBreakEvery,
        dailyFocusGoal: _pomodoro.dailyFocusGoal,
        phaseId: '${now.microsecondsSinceEpoch}-${nextMode.name}',
        timerDirection: _pomodoro.timerDirection,
        endsAt: now.add(_pomodoro.configuredDurationFor(nextMode)),
        focusHistory: history.take(730).toList(growable: false),
        updatedAt: now,
      ),
    );
  }

  void _setPomodoro(PomodoroState value) {
    _pomodoro = value;
    _notifyListeners();
    unawaited(_persistPomodoro().catchError((Object _) {}));
    _scheduleSync(delay: Duration.zero);
    _configureAutoPull();
    _publishSystemSnapshot();
  }

  Future<bool> saveSyncSettings(SyncSettings value) async {
    final normalized = value.normalized();
    final previous = _syncSettings;
    try {
      await _secureTokenStorage.write(normalized.token);
      try {
        await _syncSettingsStorage.save(jsonEncode(normalized.toJson()));
      } on Object {
        try {
          await _secureTokenStorage.write(previous.token);
        } on Object {
          // Preserve the original failure. Saving again reconciles both stores.
        }
        rethrow;
      }
    } on Object catch (error) {
      _setSyncError('设置保存失败：${_readableError(error)}');
      return false;
    }

    _syncConfigurationGeneration += 1;
    _syncSettings = normalized;
    _syncDebounceTimer?.cancel();
    _syncActivity = normalized.isConfigured
        ? SyncActivity.idle
        : SyncActivity.unconfigured;
    _syncMessage = normalized.isConfigured ? '同步设置已保存' : '尚未配置同步';
    if (_activeSync != null) {
      _syncQueued = normalized.autoSync && normalized.isConfigured;
    } else if (normalized.autoSync && normalized.isConfigured) {
      _scheduleSync();
    }
    _configureAutoPull();
    _configureChangeFeed();
    _notifyListeners();
    return true;
  }

  Future<bool> testSyncConnection(SyncSettings value) async {
    if (!syncSupported) {
      _setSyncError('当前平台暂不支持同步设置');
      return false;
    }
    if (_activeSync != null) {
      _syncMessage = '正在同步，请稍后再测试连接';
      _notifyListeners();
      return false;
    }
    final candidate = value.normalized();
    if (!candidate.isConfigured) {
      _setSyncError(candidate.validationMessage ?? '同步设置不完整');
      return false;
    }

    _syncActivity = SyncActivity.testing;
    _syncMessage = '正在测试连接…';
    _notifyListeners();
    try {
      await _syncClient.testConnection(candidate);
      _syncActivity = SyncActivity.success;
      _syncMessage = '服务器连接正常';
      _notifyListeners();
      return true;
    } on Object catch (error) {
      _setSyncError(_readableError(error));
      return false;
    }
  }

  Future<bool> syncNow() async {
    if (!syncSupported) {
      _setSyncError('当前平台暂不支持同步');
      return false;
    }
    if (!_syncSettings.isConfigured) {
      _setSyncError(_syncSettings.validationMessage ?? '同步设置不完整');
      return false;
    }
    final running = _activeSync;
    if (running != null) {
      _syncQueued = true;
      return running;
    }

    final operation = _performSync();
    _activeSync = operation;
    final succeeded = await operation;
    if (identical(_activeSync, operation)) _activeSync = null;
    if (_syncQueued && !_disposed) {
      _syncQueued = false;
      unawaited(syncNow());
    }
    return succeeded;
  }

  Future<bool> _performSync() async {
    _syncDebounceTimer?.cancel();
    final configurationGeneration = _syncConfigurationGeneration;
    final settings = _syncSettings;
    _syncActivity = SyncActivity.syncing;
    _syncMessage = '正在同步…';
    _notifyListeners();
    try {
      final response = await _syncClient.sync(
        settings,
        List<TaskItem>.unmodifiable(_tasks),
        _pomodoro,
      );
      if (configurationGeneration != _syncConfigurationGeneration) {
        return true;
      }
      if (response.revision > _lastRevision) {
        _lastRevision = response.revision;
      }
      _mergeRemote(response.tasks);
      final serverTime = DateTime.tryParse(response.serverTime)?.toUtc();
      if (serverTime != null) {
        _serverClockOffset = serverTime.difference(DateTime.now().toUtc());
      }
      final remotePomodoro = response.pomodoro;
      if (remotePomodoro != null &&
          (remotePomodoro.updatedAt.isAfter(_pomodoro.updatedAt) ||
              remotePomodoro.updatedAt.isAtSameMomentAs(_pomodoro.updatedAt))) {
        _pomodoro = remotePomodoro;
      }
      await Future.wait([_persistTasks(), _persistPomodoro()]);
      _lastSyncedAt = DateTime.now();
      _lastServerTime = response.serverTime;
      _syncActivity = SyncActivity.success;
      _syncMessage = '同步完成';
      _notifyListeners();
      _configureAutoPull();
      _publishSystemSnapshot();
      return true;
    } on Object catch (error) {
      if (configurationGeneration != _syncConfigurationGeneration) {
        return false;
      }
      _setSyncError(_readableError(error));
      return false;
    }
  }

  void _mergeRemote(List<TaskItem> remoteTasks) {
    final byId = <String, TaskItem>{for (final task in _tasks) task.id: task};
    for (final remote in remoteTasks) {
      final local = byId[remote.id];
      final remoteWinsEqualTimestamp =
          local != null &&
          remote.updatedAt.isAtSameMomentAs(local.updatedAt) &&
          local.deletedAt == null &&
          remote.deletedAt != null;
      if (local == null ||
          remote.updatedAt.isAfter(local.updatedAt) ||
          remoteWinsEqualTimestamp) {
        byId[remote.id] = remote;
      }
    }
    _tasks
      ..clear()
      ..addAll(byId.values);
    final selected = selectedTask;
    if (selectedTaskId != null && selected == null) selectedTaskId = null;
  }

  void _changed() {
    _notifyListeners();
    unawaited(_persistTasks().catchError((Object _) {}));
    _scheduleSync();
    _publishSystemSnapshot();
  }

  void _publishSystemSnapshot() {
    final localNow = DateTime.now();
    final tomorrow = DateTime(localNow.year, localNow.month, localNow.day + 1);
    final todayTasks = _tasks.where((task) {
      if (!task.isOpen || task.deletedAt != null) return false;
      final start = task.startAt?.toLocal();
      return start != null && start.isBefore(tomorrow);
    }).toList(growable: false);
    IOSSystemFeatures.update(
      pomodoro: _pomodoro,
      todayTaskCount: todayTasks.length,
      todayTaskTitles: todayTasks.take(3).map((task) => task.title).toList(),
    );
  }

  Future<void> _persistTasks() {
    final encoded = jsonEncode(_tasks.map((task) => task.toJson()).toList());
    final previous = _saveTail;
    final operation = () async {
      try {
        await previous;
      } on Object {
        // A later snapshot should still be written after an earlier write fails.
      }
      await _storage.save(encoded);
    }();
    _saveTail = operation;
    return operation;
  }

  Future<void> _persistPomodoro() =>
      _pomodoroStorage.save(jsonEncode(_pomodoro.toJson()));

  void _scheduleSync({Duration? delay}) {
    _syncDebounceTimer?.cancel();
    if (!syncSupported ||
        !_syncSettings.autoSync ||
        !_syncSettings.isConfigured ||
        _disposed) {
      return;
    }
    _syncDebounceTimer = Timer(
      delay ?? syncDebounce,
      () => unawaited(syncNow()),
    );
  }

  void _configureAutoPull() {
    _autoPullTimer?.cancel();
    if (_disposed ||
        !syncSupported ||
        !_syncSettings.autoSync ||
        !_syncSettings.isConfigured) {
      return;
    }
    _autoPullTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncNow()),
    );
  }

  void _configureChangeFeed() {
    final generation = ++_changeFeedGeneration;
    final client = _syncClient;
    if (client is! SyncChangeClient) return;
    if (_disposed ||
        !syncSupported ||
        !_syncSettings.autoSync ||
        !_syncSettings.isConfigured) {
      return;
    }
    unawaited(_watchChanges(client as SyncChangeClient, generation));
  }

  Future<void> _watchChanges(SyncChangeClient client, int generation) async {
    while (!_disposed && generation == _changeFeedGeneration) {
      try {
        final change = await client.waitForChanges(
          _syncSettings,
          since: _lastRevision,
        );
        if (_disposed || generation != _changeFeedGeneration) return;
        final isNewRevision = change.revision > _lastRevision;
        if (change.changed && isNewRevision) {
          final succeeded = await syncNow();
          if (!succeeded) {
            await Future<void>.delayed(const Duration(seconds: 3));
          }
        } else if (isNewRevision) {
          _lastRevision = change.revision;
        }
      } on Object {
        if (_disposed || generation != _changeFeedGeneration) return;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  void _setSyncError(String message) {
    _syncActivity = SyncActivity.error;
    _syncMessage = message;
    _notifyListeners();
  }

  String _readableError(Object error) {
    if (error is SyncException) return error.message;
    final value = error.toString();
    return value.length <= 180 ? value : '${value.substring(0, 180)}…';
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  void _seed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9).toUtc();
    final tomorrow = today.add(const Duration(days: 1));
    final created = DateTime.now().toUtc();
    _tasks.addAll([
      _seedTask('seed-quick', '体验快速新增任务', 1000, today, null, created),
      _seedTask('seed-focus', '整理今天真正重要的三件事', 2000, today, 'personal', created),
      _seedTask(
        'seed-offline',
        '确认离线保存正常',
        3000,
        today,
        'qingxu',
        created,
        notes: '新增任务后刷新页面，内容仍然保留。',
      ),
      _seedTask('seed-sync', '配置你的多端同步', 4000, tomorrow, 'qingxu', created),
    ]);
    unawaited(_persistTasks().catchError((Object _) {}));
  }

  TaskItem _seedTask(
    String id,
    String title,
    int order,
    DateTime startAt,
    String? projectId,
    DateTime createdAt, {
    String notes = '',
  }) {
    return TaskItem(
      id: id,
      title: title,
      notes: notes,
      status: TaskStatus.open,
      projectId: projectId,
      startAt: startAt,
      deadlineAt: null,
      completedAt: null,
      order: order,
      createdAt: createdAt,
      updatedAt: createdAt,
      deletedAt: null,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _changeFeedGeneration += 1;
    _syncDebounceTimer?.cancel();
    _autoPullTimer?.cancel();
    super.dispose();
  }
}
