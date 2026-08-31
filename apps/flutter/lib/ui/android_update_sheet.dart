import 'dart:io';

import 'package:flutter/material.dart';

import '../services/android_update_service.dart';
import 'design_system.dart';

Future<void> showAndroidUpdateSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AndroidUpdateSheet(),
    );

class _AndroidUpdateSheet extends StatefulWidget {
  const _AndroidUpdateSheet();

  @override
  State<_AndroidUpdateSheet> createState() => _AndroidUpdateSheetState();
}

class _AndroidUpdateSheetState extends State<_AndroidUpdateSheet> {
  final _service = AndroidUpdateService();
  AndroidUpdateInfo? _info;
  File? _apk;
  double _progress = 0;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _service.check();
      if (mounted) setState(() => _info = info);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null || _busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      final apk = await _service.downloadAndPrepare(
        info,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) setState(() => _apk = apk);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final info = _info;
    return Material(
      color: palette.surfaceRaised,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('应用更新', style: TextStyle(color: palette.ink, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_busy && info == null)
              const LinearProgressIndicator()
            else if (_error != null)
              Text(_error!, style: TextStyle(color: palette.danger, height: 1.5))
            else if (info == null)
              const Text('当前 Release 暂无 Android 更新清单。')
            else if (!info.hasUpdate)
              Text('当前已是最新版 ${info.currentVersion}。')
            else ...[
              Text(
                '${info.currentVersion} → ${info.latestVersion}',
                style: TextStyle(color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                info.hasPatch
                    ? '优先下载增量包，校验或合成失败时自动改用完整 APK。'
                    : '本次使用完整 APK 更新。',
                style: TextStyle(color: palette.muted, height: 1.45),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              ],
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : _apk != null
                    ? () => _service.install(_apk!)
                    : info?.hasUpdate == true
                    ? _download
                    : _check,
                child: Text(
                  _busy
                      ? '处理中…'
                      : _apk != null
                      ? '安装更新'
                      : info?.hasUpdate == true
                      ? '下载更新'
                      : '重新检查',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _clean(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('StateError: ', '');
