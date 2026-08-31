import 'dart:convert';
import 'dart:io';

import 'package:binary_patch/binary_patch.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AndroidUpdateInfo {
  const AndroidUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.fullUrl,
    required this.fullSha256,
    required this.patchUrl,
    required this.patchSize,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri fullUrl;
  final String fullSha256;
  final Uri? patchUrl;
  final int? patchSize;

  bool get hasUpdate => _compareVersions(latestVersion, currentVersion) > 0;
  bool get hasPatch => patchUrl != null;
}

class AndroidUpdateService {
  AndroidUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const _channel = MethodChannel('one.darker.qingxu/android_update');
  static const _latestRelease =
      'https://api.github.com/repos/FelixZoe/qingxu/releases/latest';

  final http.Client _client;

  Future<AndroidUpdateInfo?> check() async {
    final package = await PackageInfo.fromPlatform();
    final response = await _client.get(
      Uri.parse(_latestRelease),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('检查更新失败（HTTP ${response.statusCode}）');
    }
    final release = jsonDecode(utf8.decode(response.bodyBytes));
    if (release is! Map || release['assets'] is! List) {
      throw StateError('Release 信息格式不正确');
    }
    final assets = (release['assets'] as List).whereType<Map>().toList();
    final manifestAsset = assets.where(
      (asset) => asset['name'] == 'qingxu-android-update.json',
    ).firstOrNull;
    if (manifestAsset == null) return null;
    final manifestResponse = await _client.get(
      Uri.parse(manifestAsset['browser_download_url'] as String),
    ).timeout(const Duration(seconds: 15));
    if (manifestResponse.statusCode != 200) {
      throw StateError('更新清单下载失败');
    }
    final manifest = jsonDecode(utf8.decode(manifestResponse.bodyBytes));
    if (manifest is! Map) throw StateError('更新清单格式不正确');
    final patches = manifest['patches'];
    Map? patch;
    if (patches is Map && patches[package.version] is Map) {
      patch = patches[package.version] as Map;
    }
    return AndroidUpdateInfo(
      currentVersion: package.version,
      latestVersion: manifest['latestVersion'] as String? ?? package.version,
      fullUrl: Uri.parse(manifest['fullUrl'] as String),
      fullSha256: manifest['fullSha256'] as String? ?? '',
      patchUrl: patch?['url'] is String ? Uri.parse(patch!['url'] as String) : null,
      patchSize: (patch?['size'] as num?)?.toInt(),
    );
  }

  Future<File> downloadAndPrepare(
    AndroidUpdateInfo info, {
    void Function(double value)? onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final output = File('${directory.path}/qingxu-${info.latestVersion}.apk');
    if (info.patchUrl != null) {
      try {
        final patch = File('${directory.path}/qingxu-${info.currentVersion}-${info.latestVersion}.bpatch');
        await _download(info.patchUrl!, patch, onProgress: onProgress);
        final oldPath = await _channel.invokeMethod<String>('sourceApkPath');
        if (oldPath == null || oldPath.isEmpty) throw StateError('无法读取当前安装包');
        await BinaryPatch.apply(
          oldFile: oldPath,
          patchFile: patch.path,
          outputFile: output.path,
          verifyChecksum: true,
        );
        if (await _validOutput(output, info.fullSha256)) return output;
      } on Object {
        if (await output.exists()) await output.delete();
      }
    }
    await _download(info.fullUrl, output, onProgress: onProgress);
    if (!await _validOutput(output, info.fullSha256)) {
      if (await output.exists()) await output.delete();
      throw StateError('安装包校验失败，请重新下载');
    }
    return output;
  }

  Future<bool> install(File apk) async =>
      await _channel.invokeMethod<bool>('installApk', {'path': apk.path}) ?? false;

  Future<void> _download(
    Uri uri,
    File destination, {
    void Function(double value)? onProgress,
  }) async {
    final request = http.Request('GET', uri);
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('更新下载失败（HTTP ${response.statusCode}）');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
  }

  Future<bool> _validOutput(File file, String expected) async {
    if (!await file.exists() || await file.length() < 1024) return false;
    if (expected.trim().isEmpty) return true;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected.trim().toLowerCase();
  }

  void dispose() => _client.close();
}

int _compareVersions(String left, String right) {
  final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  for (var index = 0; index < 3; index++) {
    final comparison = (index < a.length ? a[index] : 0)
        .compareTo(index < b.length ? b[index] : 0);
    if (comparison != 0) return comparison;
  }
  return 0;
}
