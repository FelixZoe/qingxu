import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/models/sync_settings.dart';
import 'package:qingxu/models/task_item.dart';
import 'package:qingxu/services/sync_client_io.dart';

void main() {
  const token =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('connection check uses public health then authenticated ping', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = () async {
      var count = 0;
      await for (final request in server.take(2)) {
        count += 1;
        if (count == 1) {
          expect(request.uri.path, '/health');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            isNull,
          );
        } else {
          expect(request.uri.path, '/v1/ping');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer $token',
          );
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"ok":true}');
        await request.response.close();
      }
    }();

    await SyncClient().testConnection(
      SyncSettings(
        serverUrl: 'http://127.0.0.1:${server.port}',
        token: token,
        deviceName: 'Windows 测试机',
      ),
    );
    await handled;
  });

  test('sync sends the agreed bearer and JSON contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final task = _task();
    final handled = () async {
      final request = await server.first;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/sync');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer $token',
      );
      final decoded = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      expect(decoded['deviceId'], 'Windows 测试机');
      expect(decoded['tasks'], hasLength(1));
      expect((decoded['tasks'] as List).single['id'], task.id);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'tasks': [task.toJson()],
            'serverTime': '2026-08-22T12:00:00.000Z',
          }),
        );
      await request.response.close();
    }();

    final response = await SyncClient().sync(
      SyncSettings(
        serverUrl: 'http://127.0.0.1:${server.port}',
        token: token,
        deviceName: 'Windows 测试机',
      ),
      [task],
    );
    await handled;

    expect(response.tasks.single.id, task.id);
    expect(response.serverTime, '2026-08-22T12:00:00.000Z');
  });
}

TaskItem _task() {
  final timestamp = DateTime.utc(2026, 8, 22, 12);
  return TaskItem(
    id: 'task-contract',
    title: '验证同步协议',
    notes: '',
    status: TaskStatus.open,
    projectId: null,
    startAt: null,
    deadlineAt: null,
    completedAt: null,
    order: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
    deletedAt: null,
  );
}
