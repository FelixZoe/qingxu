import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sync_settings.dart';
import '../state/task_controller.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({required this.controller, super.key});

  final TaskController controller;

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  late final TextEditingController _serverController;
  late final TextEditingController _tokenController;
  late final TextEditingController _deviceController;
  late bool _autoSync;
  bool _hideToken = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.syncSettings;
    _serverController = TextEditingController(text: settings.serverUrl);
    _tokenController = TextEditingController(text: settings.token);
    _deviceController = TextEditingController(text: settings.deviceName);
    _autoSync = settings.autoSync;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  SyncSettings get _candidate => SyncSettings(
    serverUrl: _serverController.text,
    token: _tokenController.text,
    deviceName: _deviceController.text,
    autoSync: _autoSync,
  );

  Future<bool> _save() async {
    setState(() => _saving = true);
    final succeeded = await widget.controller.saveSyncSettings(_candidate);
    if (mounted) setState(() => _saving = false);
    return succeeded;
  }

  Future<void> _testConnection() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.controller.testSyncConnection(_candidate);
  }

  Future<void> _syncNow() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (await _save()) await widget.controller.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      appBar: AppBar(
        title: const Text('同步设置'),
        backgroundColor: const Color(0xFFFBFAF7),
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusCard(controller: widget.controller),
                  const SizedBox(height: 18),
                  _SettingsCard(
                    children: [
                      TextField(
                        controller: _serverController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'https://sync.example.com',
                          helperText: '填写同步服务根地址，不要添加 /v1/sync',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _tokenController,
                        obscureText: _hideToken,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: 64,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-F]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: '同步密钥',
                          helperText: '填写服务器生成的 64 位十六进制密钥',
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            tooltip: _hideToken ? '显示密钥' : '隐藏密钥',
                            onPressed: () =>
                                setState(() => _hideToken = !_hideToken),
                            icon: Icon(
                              _hideToken
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _deviceController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '设备名',
                          helperText: '每台设备使用不同名称，例如「Felix 的 iPhone」',
                          prefixIcon: Icon(Icons.devices_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动同步'),
                        subtitle: const Text('启动时同步；本地修改后约 1 秒自动同步'),
                        value: _autoSync,
                        onChanged: (value) => setState(() => _autoSync = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) {
                      final busy = widget.controller.isSyncBusy || _saving;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy ? null : _testConnection,
                            icon: const Icon(Icons.wifi_tethering_outlined),
                            label: const Text('测试连接'),
                          ),
                          FilledButton.icon(
                            onPressed: busy ? null : _syncNow,
                            icon: const Icon(Icons.sync_rounded),
                            label: const Text('立即同步'),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '同步设置和密钥只保存在当前设备，不会写入项目源码或上传到 GitHub。网络失败时，本地任务仍可正常使用。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF77736B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFBFAF7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E1DA)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(children: children),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final (icon, color) = switch (controller.syncActivity) {
        SyncActivity.testing ||
        SyncActivity.syncing => (Icons.sync_rounded, const Color(0xFF4F78A6)),
        SyncActivity.success => (
          Icons.cloud_done_outlined,
          const Color(0xFF54845A),
        ),
        SyncActivity.error => (
          Icons.cloud_off_outlined,
          const Color(0xFFB45A4D),
        ),
        SyncActivity.idle => (
          Icons.cloud_queue_outlined,
          const Color(0xFF77736B),
        ),
        SyncActivity.unconfigured => (
          Icons.cloud_outlined,
          const Color(0xFF99958C),
        ),
      };
      return DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.syncMessage,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (controller.lastSyncedAt case final syncedAt?) ...[
                      const SizedBox(height: 3),
                      Text(
                        '上次同步：${_formatTime(syncedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF77736B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (controller.isSyncBusy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
