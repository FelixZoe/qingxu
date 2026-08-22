import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/sync_settings.dart';
import '../models/task_item.dart';
import 'sync_client_base.dart';

class SyncClient implements SyncClientBase {
  static const _timeout = Duration(seconds: 10);

  @override
  bool get isSupported => Platform.isWindows || Platform.isIOS;

  @override
  String get defaultDeviceName {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) return host;
    return Platform.isIOS ? '我的 iPhone' : '我的 Windows 设备';
  }

  @override
  Future<void> testConnection(SyncSettings settings) async {
    _requireConfiguration(settings);
    final client = _newClient();
    try {
      final request = await client
          .getUrl(_endpoint(settings.serverUrl, '/health'))
          .timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      await response.drain<void>().timeout(_timeout);
      _requireSuccess(response.statusCode, '服务器健康检查失败');

      final pingRequest = await client
          .getUrl(_endpoint(settings.serverUrl, '/v1/ping'))
          .timeout(_timeout);
      pingRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${settings.token}',
      );
      final pingResponse = await pingRequest.close().timeout(_timeout);
      await pingResponse.drain<void>().timeout(_timeout);
      _requireSuccess(pingResponse.statusCode, '同步身份验证失败');
    } on SyncException {
      rethrow;
    } on TimeoutException {
      throw const SyncException('连接超时，请检查服务器地址和网络');
    } on FormatException {
      throw const SyncException('服务器地址格式不正确');
    } on SocketException {
      throw const SyncException('无法连接服务器，请检查地址、DNS 和端口');
    } on HandshakeException {
      throw const SyncException('HTTPS 证书校验失败');
    } catch (error) {
      throw SyncException('连接失败：${_safeError(error)}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<SyncResponse> sync(SyncSettings settings, List<TaskItem> tasks) async {
    _requireConfiguration(settings);
    final client = _newClient();
    try {
      final request = await client
          .postUrl(_endpoint(settings.serverUrl, '/v1/sync'))
          .timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${settings.token}',
      );
      request.write(
        jsonEncode({
          'deviceId': settings.deviceName,
          'tasks': tasks.map((task) => task.toJson()).toList(),
        }),
      );

      final response = await request.close().timeout(_timeout);
      final body = await utf8.decoder.bind(response).join().timeout(_timeout);
      _requireSuccess(response.statusCode, '同步请求失败', body: body);

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const SyncException('服务器返回了无法识别的数据');
      }
      final values = decoded['tasks'];
      final serverTime = decoded['serverTime'];
      if (values is! List || serverTime is! String) {
        throw const SyncException('服务器同步响应缺少 tasks 或 serverTime');
      }

      final remoteTasks = <TaskItem>[];
      for (final value in values) {
        if (value is! Map) {
          throw const SyncException('服务器返回了无效的任务数据');
        }
        remoteTasks.add(TaskItem.fromJson(Map<String, Object?>.from(value)));
      }
      return SyncResponse(tasks: remoteTasks, serverTime: serverTime);
    } on SyncException {
      rethrow;
    } on TimeoutException {
      throw const SyncException('同步超时，本地数据未受影响');
    } on FormatException {
      throw const SyncException('服务器返回的数据格式不正确');
    } on SocketException {
      throw const SyncException('无法连接同步服务器，本地数据未受影响');
    } on HandshakeException {
      throw const SyncException('HTTPS 证书校验失败');
    } catch (error) {
      throw SyncException('同步失败：${_safeError(error)}');
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _newClient() => HttpClient()..connectionTimeout = _timeout;

  Uri _endpoint(String rawBaseUrl, String endpointPath) {
    var value = rawBaseUrl.trim();
    if (!value.contains('://')) value = 'https://$value';
    final base = Uri.parse(value);
    if (!base.hasScheme || base.host.isEmpty) {
      throw const FormatException('Invalid server URL');
    }
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(
      path: '$basePath$endpointPath',
      query: null,
      fragment: null,
    );
  }

  void _requireConfiguration(SyncSettings settings) {
    if (!settings.isConfigured) {
      throw SyncException(settings.validationMessage ?? '同步设置不完整');
    }
  }

  void _requireSuccess(int statusCode, String fallback, {String? body}) {
    if (statusCode >= 200 && statusCode < 300) return;
    if (statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.forbidden) {
      throw const SyncException('同步密钥无效或无权限');
    }
    final trimmed = body?.trim() ?? '';
    final safeBody = trimmed.length <= 160
        ? trimmed
        : '${trimmed.substring(0, 160)}…';
    final suffix = safeBody.isEmpty ? '' : '：$safeBody';
    throw SyncException('$fallback（HTTP $statusCode）$suffix');
  }

  String _safeError(Object error) {
    final message = error.toString();
    return message.length <= 160 ? message : '${message.substring(0, 160)}…';
  }
}
