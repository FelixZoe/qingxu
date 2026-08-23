import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/models/sync_settings.dart';
import 'package:qingxu/models/pomodoro_state.dart';
import 'package:qingxu/models/task_item.dart';
import 'package:qingxu/services/secure_token_storage_base.dart';
import 'package:qingxu/services/sync_client_base.dart';
import 'package:qingxu/services/sync_settings_storage_base.dart';
import 'package:qingxu/services/task_storage_stub.dart';
import 'package:qingxu/state/task_controller.dart';

void main() {
  const configured = SyncSettings(
    serverUrl: 'https://sync.example.test',
    token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    deviceName: '测试设备',
    autoSync: false,
  );

  test(
    'sync uses device settings, merges by updatedAt, and persists',
    () async {
      final taskStorage = TaskStorage();
      final settingsStorage = MemorySettingsStorage(
        jsonEncode(configured.toJson()),
      );
      final secureTokenStorage = MemorySecureTokenStorage(configured.token);
      final client = FakeSyncClient(
        onSync: (tasks) {
          final newer = tasks.firstWhere((task) => task.id == 'seed-quick');
          final older = tasks.firstWhere((task) => task.id == 'seed-focus');
          return SyncResponse(
            tasks: [
              newer.copyWith(
                title: '来自服务器的新版本',
                updatedAt: newer.updatedAt.add(const Duration(hours: 1)),
              ),
              older.copyWith(
                title: '不应覆盖本地的旧版本',
                updatedAt: older.updatedAt.subtract(const Duration(hours: 1)),
              ),
            ],
            serverTime: '2026-08-22T12:00:00.000Z',
          );
        },
      );
      final controller = TaskController(
        storage: taskStorage,
        syncSettingsStorage: settingsStorage,
        secureTokenStorage: secureTokenStorage,
        syncClient: client,
      );
      await controller.initialize();

      expect(await controller.syncNow(), isTrue);
      expect(client.lastSettings?.deviceName, '测试设备');
      expect(client.lastTasks, hasLength(4));
      expect(
        controller.tasks.firstWhere((task) => task.id == 'seed-quick').title,
        '来自服务器的新版本',
      );
      expect(
        controller.tasks.firstWhere((task) => task.id == 'seed-focus').title,
        '整理今天真正重要的三件事',
      );
      expect(controller.lastServerTime, '2026-08-22T12:00:00.000Z');

      final restored = TaskController(
        storage: taskStorage,
        syncSettingsStorage: settingsStorage,
        secureTokenStorage: secureTokenStorage,
        syncClient: client,
      );
      await restored.initialize();
      expect(
        restored.tasks.firstWhere((task) => task.id == 'seed-quick').title,
        '来自服务器的新版本',
      );
    },
  );

  test(
    'server change notification immediately pulls running pomodoro',
    () async {
      const automatic = SyncSettings(
        serverUrl: 'https://sync.example.test',
        token:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        deviceName: '实时测试设备',
        autoSync: true,
      );
      final client = LiveSyncClient();
      final controller = TaskController(
        storage: TaskStorage(),
        syncSettingsStorage: MemorySettingsStorage(
          jsonEncode(automatic.toJson()),
        ),
        secureTokenStorage: MemorySecureTokenStorage(automatic.token),
        syncClient: client,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await waitUntil(() => client.syncCalls >= 1 && client.hasWaiter);

      final now = DateTime.utc(2026, 8, 23, 8);
      client.emitPomodoro(
        PomodoroState.initial(now).copyWith(
          status: PomodoroStatus.running,
          remainingSeconds: 25 * 60,
          endsAt: now.add(const Duration(minutes: 25)),
          updatedAt: now,
        ),
      );

      await waitUntil(
        () => controller.pomodoro.status == PomodoroStatus.running,
      );
      expect(client.syncCalls, greaterThanOrEqualTo(2));
      expect(controller.pomodoro.endsAt, now.add(const Duration(minutes: 25)));
    },
  );

  test('settings persist and automatic sync runs after local changes', () async {
    final taskStorage = TaskStorage();
    final settingsStorage = MemorySettingsStorage();
    final secureTokenStorage = MemorySecureTokenStorage();
    final client = FakeSyncClient();
    final controller = TaskController(
      storage: taskStorage,
      syncSettingsStorage: settingsStorage,
      secureTokenStorage: secureTokenStorage,
      syncClient: client,
      syncDebounce: const Duration(milliseconds: 5),
    );
    await controller.initialize();

    final saved = await controller.saveSyncSettings(
      const SyncSettings(
        serverUrl: 'https://sync.example.test/',
        token:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        deviceName: 'Windows 测试机',
        autoSync: true,
      ),
    );
    expect(saved, isTrue);
    expect(jsonDecode(settingsStorage.value!) as Map, isNot(contains('token')));
    expect(secureTokenStorage.value, configured.token);
    await waitUntil(() => client.syncCalls == 1);

    controller.addTask('触发防抖同步');
    await waitUntil(() => client.syncCalls == 2);
    expect(client.lastTasks.any((task) => task.title == '触发防抖同步'), isTrue);

    final restoredClient = FakeSyncClient();
    final restored = TaskController(
      storage: taskStorage,
      syncSettingsStorage: settingsStorage,
      secureTokenStorage: secureTokenStorage,
      syncClient: restoredClient,
      syncDebounce: const Duration(milliseconds: 5),
    );
    await restored.initialize();
    expect(restored.syncSettings.serverUrl, 'https://sync.example.test');
    expect(restored.syncSettings.deviceName, 'Windows 测试机');
    expect(restored.syncSettings.autoSync, isTrue);
    await waitUntil(() => restoredClient.syncCalls == 1);
  });

  test('sync failure keeps all offline tasks intact', () async {
    final taskStorage = TaskStorage();
    final controller = TaskController(
      storage: taskStorage,
      syncSettingsStorage: MemorySettingsStorage(
        jsonEncode(configured.toJson()),
      ),
      secureTokenStorage: MemorySecureTokenStorage(configured.token),
      syncClient: FakeSyncClient(failure: const SyncException('服务器离线')),
    );
    await controller.initialize();
    controller.addTask('离线任务');
    final before = controller.tasks.map((task) => task.toJson()).toList();

    expect(await controller.syncNow(), isFalse);
    expect(controller.syncActivity, SyncActivity.error);
    expect(controller.syncMessage, '服务器离线');
    expect(controller.tasks.map((task) => task.toJson()).toList(), before);
  });

  test('legacy plaintext token is migrated out of the settings file', () async {
    final settingsStorage = MemorySettingsStorage(
      jsonEncode({...configured.toJson(), 'token': configured.token}),
    );
    final secureTokenStorage = MemorySecureTokenStorage();
    final controller = TaskController(
      storage: TaskStorage(),
      syncSettingsStorage: settingsStorage,
      secureTokenStorage: secureTokenStorage,
      syncClient: FakeSyncClient(),
    );

    await controller.initialize();

    expect(controller.syncSettings.token, configured.token);
    expect(secureTokenStorage.value, configured.token);
    expect(jsonDecode(settingsStorage.value!) as Map, isNot(contains('token')));
  });

  test(
    'existing secure token wins over stale legacy plaintext token',
    () async {
      const legacyToken =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final settingsStorage = MemorySettingsStorage(
        jsonEncode({...configured.toJson(), 'token': legacyToken}),
      );
      final secureTokenStorage = MemorySecureTokenStorage(configured.token);
      final controller = TaskController(
        storage: TaskStorage(),
        syncSettingsStorage: settingsStorage,
        secureTokenStorage: secureTokenStorage,
        syncClient: FakeSyncClient(),
      );

      await controller.initialize();

      expect(controller.syncSettings.token, configured.token);
      expect(secureTokenStorage.value, configured.token);
      expect(
        jsonDecode(settingsStorage.value!) as Map,
        isNot(contains('token')),
      );
    },
  );

  test('failed secure migration keeps the legacy plaintext token', () async {
    final settingsStorage = MemorySettingsStorage(
      jsonEncode({...configured.toJson(), 'token': configured.token}),
    );
    final secureTokenStorage = MemorySecureTokenStorage()..failWrite = true;
    final controller = TaskController(
      storage: TaskStorage(),
      syncSettingsStorage: settingsStorage,
      secureTokenStorage: secureTokenStorage,
      syncClient: FakeSyncClient(),
    );

    await controller.initialize();

    expect(controller.syncSettings.token, configured.token);
    expect(
      jsonDecode(settingsStorage.value!) as Map,
      containsPair('token', configured.token),
    );
    expect(controller.syncActivity, SyncActivity.idle);
    expect(controller.syncMessage, contains('已保留旧密钥'));
  });

  test(
    'failed settings save restores secure token and active settings',
    () async {
      const replacement = SyncSettings(
        serverUrl: 'https://replacement.example.test',
        token:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        deviceName: '替换设备',
        autoSync: false,
      );
      final settingsStorage = MemorySettingsStorage(
        jsonEncode(configured.toJson()),
      )..failSave = true;
      final secureTokenStorage = MemorySecureTokenStorage(configured.token);
      final controller = TaskController(
        storage: TaskStorage(),
        syncSettingsStorage: settingsStorage,
        secureTokenStorage: secureTokenStorage,
        syncClient: FakeSyncClient(),
      );
      await controller.initialize();

      expect(await controller.saveSyncSettings(replacement), isFalse);
      expect(controller.syncSettings.serverUrl, configured.serverUrl);
      expect(controller.syncSettings.token, configured.token);
      expect(secureTokenStorage.value, configured.token);
    },
  );

  test(
    'equal timestamp server tombstone wins over a live local task',
    () async {
      final controller = TaskController(
        storage: TaskStorage(),
        syncSettingsStorage: MemorySettingsStorage(
          jsonEncode(configured.toJson()),
        ),
        secureTokenStorage: MemorySecureTokenStorage(configured.token),
        syncClient: FakeSyncClient(
          onSync: (tasks) {
            final live = tasks.firstWhere((task) => task.id == 'seed-quick');
            return SyncResponse(
              tasks: [live.copyWith(deletedAt: live.updatedAt)],
              serverTime: '2026-08-22T12:00:00.000Z',
            );
          },
        ),
      );
      await controller.initialize();

      expect(await controller.syncNow(), isTrue);
      expect(
        controller.tasks
            .firstWhere((task) => task.id == 'seed-quick')
            .deletedAt,
        isNotNull,
      );
    },
  );

  test('response from old sync configuration is discarded', () async {
    final client = ControlledSyncClient();
    final controller = TaskController(
      storage: TaskStorage(),
      syncSettingsStorage: MemorySettingsStorage(
        jsonEncode(configured.toJson()),
      ),
      secureTokenStorage: MemorySecureTokenStorage(configured.token),
      syncClient: client,
    );
    await controller.initialize();
    final original = controller.tasks.firstWhere(
      (task) => task.id == 'seed-quick',
    );

    final oldSync = controller.syncNow();
    await waitUntil(() => client.calls.length == 1);
    const replacement = SyncSettings(
      serverUrl: 'https://replacement.example.test',
      token: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      deviceName: '替换设备',
      autoSync: true,
    );
    expect(await controller.saveSyncSettings(replacement), isTrue);
    client.calls.first.completer.complete(
      SyncResponse(
        tasks: [
          original.copyWith(
            title: '来自旧服务器的响应',
            updatedAt: original.updatedAt.add(const Duration(hours: 1)),
          ),
        ],
        serverTime: '2026-08-22T12:00:00.000Z',
      ),
    );
    expect(await oldSync, isTrue);

    await waitUntil(() => client.calls.length == 2);
    expect(client.calls.last.settings.serverUrl, replacement.serverUrl);
    expect(
      controller.tasks.firstWhere((task) => task.id == original.id).title,
      original.title,
    );
    client.calls.last.completer.complete(
      SyncResponse(
        tasks: client.calls.last.tasks,
        serverTime: '2026-08-22T12:00:01.000Z',
      ),
    );
    await waitUntil(() => controller.syncActivity == SyncActivity.success);
  });
}

Future<void> waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out while waiting for asynchronous sync');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class MemorySettingsStorage implements SyncSettingsStorageBase {
  MemorySettingsStorage([this.value]);

  String? value;
  bool failSave = false;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String value) async {
    if (failSave) throw StateError('settings save failed');
    this.value = value;
  }
}

class MemorySecureTokenStorage implements SecureTokenStorageBase {
  MemorySecureTokenStorage([this.value]);

  String? value;
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('secure read failed');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('secure write failed');
    this.value = value.trim().isEmpty ? null : value.trim();
  }
}

class ControlledSyncCall {
  ControlledSyncCall(this.settings, this.tasks);

  final SyncSettings settings;
  final List<TaskItem> tasks;
  final Completer<SyncResponse> completer = Completer<SyncResponse>();
}

class ControlledSyncClient implements SyncClientBase {
  final List<ControlledSyncCall> calls = [];

  @override
  String get defaultDeviceName => '受控测试设备';

  @override
  bool get isSupported => true;

  @override
  Future<SyncResponse> sync(
    SyncSettings settings,
    List<TaskItem> tasks,
    PomodoroState pomodoro,
  ) {
    final call = ControlledSyncCall(settings, List.unmodifiable(tasks));
    calls.add(call);
    return call.completer.future;
  }

  @override
  Future<void> testConnection(SyncSettings settings) async {}
}

class FakeSyncClient implements SyncClientBase {
  FakeSyncClient({this.onSync, this.failure});

  final SyncResponse Function(List<TaskItem> tasks)? onSync;
  final SyncException? failure;
  int syncCalls = 0;
  SyncSettings? lastSettings;
  List<TaskItem> lastTasks = const [];

  @override
  String get defaultDeviceName => '默认测试设备';

  @override
  bool get isSupported => true;

  @override
  Future<SyncResponse> sync(
    SyncSettings settings,
    List<TaskItem> tasks,
    PomodoroState pomodoro,
  ) async {
    syncCalls += 1;
    lastSettings = settings;
    lastTasks = List.unmodifiable(tasks);
    if (failure case final error?) throw error;
    return onSync?.call(tasks) ??
        SyncResponse(
          tasks: List.unmodifiable(tasks),
          serverTime: '2026-08-22T12:00:00.000Z',
        );
  }

  @override
  Future<void> testConnection(SyncSettings settings) async {
    if (failure case final error?) throw error;
  }
}

class LiveSyncClient implements SyncClientBase, SyncChangeClient {
  int revision = 1;
  int syncCalls = 0;
  PomodoroState remotePomodoro = PomodoroState.initial();
  Completer<SyncChange>? _waiter;

  bool get hasWaiter => _waiter != null;

  @override
  String get defaultDeviceName => '实时测试设备';

  @override
  bool get isSupported => true;

  @override
  Future<SyncResponse> sync(
    SyncSettings settings,
    List<TaskItem> tasks,
    PomodoroState pomodoro,
  ) async {
    syncCalls += 1;
    return SyncResponse(
      tasks: List.unmodifiable(tasks),
      pomodoro: remotePomodoro,
      serverTime: '2026-08-23T08:00:00.000Z',
      revision: revision,
    );
  }

  @override
  Future<void> testConnection(SyncSettings settings) async {}

  @override
  Future<SyncChange> waitForChanges(
    SyncSettings settings, {
    required int since,
  }) {
    if (revision > since) {
      return Future.value(SyncChange(revision: revision, changed: true));
    }
    final waiter = Completer<SyncChange>();
    _waiter = waiter;
    return waiter.future.whenComplete(() {
      if (identical(_waiter, waiter)) _waiter = null;
    });
  }

  void emitPomodoro(PomodoroState value) {
    remotePomodoro = value;
    revision += 1;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(SyncChange(revision: revision, changed: true));
    }
  }
}
