import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sync_settings.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

enum _SettingsSection { overview, appearance, sync }

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.embedded = false,
    this.onMenu,
    super.key,
  });

  final TaskController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool embedded;
  final VoidCallback? onMenu;

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
  _SettingsSection _section = _SettingsSection.overview;

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
    FocusManager.instance.primaryFocus?.unfocus();
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
    if (await _save()) await widget.controller.syncNow();
  }

  @override
  Widget build(BuildContext context) => switch (_section) {
    _SettingsSection.overview => _buildOverview(context),
    _SettingsSection.appearance => _buildAppearance(context),
    _SettingsSection.sync => _buildSync(context),
  };

  Widget _buildOverview(BuildContext context) {
    final configured = widget.controller.syncSettings.isConfigured;
    final syncDetail = configured
        ? Uri.tryParse(widget.controller.syncSettings.serverUrl)?.host ?? '已配置'
        : '尚未配置';
    final appearanceDetail = switch (widget.themeMode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
    return _settingsPage(
      context,
      title: '设置',
      subtitle: '管理这台设备的外观与数据连接',
      children: [
        const _SectionLabel(title: '偏好'),
        const SizedBox(height: 9),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: '外观',
              subtitle: appearanceDetail,
              onTap: () =>
                  setState(() => _section = _SettingsSection.appearance),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionLabel(title: '数据'),
        const SizedBox(height: 9),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: configured
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_outlined,
              title: '自托管同步',
              subtitle: syncDetail,
              statusColor: configured
                  ? QingxuPalette.of(context).success
                  : QingxuPalette.of(context).faint,
              onTap: () => setState(() => _section = _SettingsSection.sync),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          configured ? '任务、番茄钟和计时设置会自动同步。' : '应用可以完全离线使用；需要跨设备时再配置服务器。',
          style: TextStyle(
            color: QingxuPalette.of(context).muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildAppearance(BuildContext context) => _settingsPage(
    context,
    title: '外观',
    subtitle: '选择清序在这台设备上的显示方式',
    showBack: true,
    children: [
      const _SectionLabel(title: '主题'),
      const SizedBox(height: 9),
      _AppearanceSection(
        themeMode: widget.themeMode,
        onChanged: widget.onThemeModeChanged,
      ),
      const SizedBox(height: 16),
      Text(
        '跟随系统会根据设备的日间与夜间模式自动切换。外观属于设备偏好，不会同步到其他设备。',
        style: TextStyle(
          color: QingxuPalette.of(context).muted,
          fontSize: 12,
          height: 1.55,
        ),
      ),
    ],
  );

  Widget _buildSync(BuildContext context) => _settingsPage(
    context,
    title: '自托管同步',
    subtitle: '连接你自己的清序同步服务器',
    showBack: true,
    trailing: FilledButton(
      onPressed: _saving || !widget.controller.syncSupported ? null : _save,
      child: Text(_saving ? '保存中…' : '保存'),
    ),
    children: [
      const _SectionLabel(title: '同步状态'),
      const SizedBox(height: 9),
      _SyncStatus(controller: widget.controller),
      if (widget.controller.syncSupported) ...[
        const SizedBox(height: 26),
        const _SectionLabel(title: '服务器'),
        const SizedBox(height: 9),
        QingxuSurface(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            children: [
              _Field(
                label: '服务器地址',
                helper: '填写根地址，不需要添加 /v1/sync',
                child: TextField(
                  controller: _serverController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    hintText: 'https://todo.darker.one',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
              ),
              _Field(
                label: '同步密钥',
                helper: '服务器生成的 64 位十六进制密钥',
                child: TextField(
                  controller: _tokenController,
                  obscureText: _hideToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 64,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '输入同步密钥',
                    counterText: '',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      tooltip: _hideToken ? '显示密钥' : '隐藏密钥',
                      onPressed: () => setState(() => _hideToken = !_hideToken),
                      icon: Icon(
                        _hideToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ),
              _Field(
                label: '设备名称',
                helper: '便于识别，例如「Felix 的 iPhone」',
                child: TextField(
                  controller: _deviceController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: '这台设备的名称',
                    prefixIcon: Icon(Icons.devices_outlined),
                  ),
                ),
              ),
              _SettingSwitch(
                title: '自动同步',
                subtitle: '启动时同步，本地修改后约 0.1 秒上传',
                value: _autoSync,
                onChanged: (value) => setState(() => _autoSync = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final busy = widget.controller.isSyncBusy || _saving;
            return Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _testConnection,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : _syncNow,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('立即同步'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
      const SizedBox(height: 18),
      Text(
        widget.controller.syncSupported
            ? '密钥仅保存在当前设备。断网时可以继续使用，恢复网络后自动合并全部数据。'
            : '当前平台仅使用本地数据。',
        style: TextStyle(
          fontSize: 12,
          height: 1.55,
          color: QingxuPalette.of(context).muted,
        ),
      ),
    ],
  );

  Widget _settingsPage(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool showBack = false,
    Widget? trailing,
  }) {
    final palette = QingxuPalette.of(context);
    if (widget.embedded) {
      return ColoredBox(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      tooltip: '返回设置',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => _section = _SettingsSection.overview);
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    )
                  else
                    const SizedBox(width: 8),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing,
                  ],
                  const SizedBox(width: 38),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border.withValues(alpha: 0.7)),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: palette.canvas,
      child: Column(
        children: [
          QingxuPageHeader(
            title: title,
            subtitle: subtitle,
            leading: showBack
                ? IconButton(
                    tooltip: '返回设置',
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _section = _SettingsSection.overview);
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : widget.onMenu == null
                ? null
                : IconButton(
                    tooltip: '打开导航',
                    onPressed: widget.onMenu,
                    icon: const Icon(Icons.menu_rounded),
                  ),
            trailing: trailing,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter = QingxuLayout.gutterFor(constraints.maxWidth);
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 44),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: QingxuLayout.contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    if (qingxuIsDesktop) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.border),
            bottom: BorderSide(color: palette.border),
          ),
        ),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                Divider(height: 1, indent: 48, color: palette.border),
            ],
          ],
        ),
      );
    }
    return QingxuSurface(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(QingxuLayout.sectionRadius),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                Divider(height: 1, indent: 66, color: palette.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.statusColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final color = statusColor ?? palette.accent;
    final desktop = qingxuIsDesktop;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 4 : 14,
            desktop ? 16 : 13,
            desktop ? 4 : 12,
            desktop ? 16 : 13,
          ),
          child: Row(
            children: [
              Container(
                width: desktop ? 34 : 40,
                height: desktop ? 34 : 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: desktop ? 0.08 : 0.12),
                  borderRadius: BorderRadius.circular(desktop ? 9 : 12),
                ),
                child: Icon(icon, size: desktop ? 18 : 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: palette.faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Text(
      title,
      style: TextStyle(
        color: palette.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.themeMode, required this.onChanged});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => QingxuSurface(
    padding: const EdgeInsets.all(6),
    child: Row(
      children: [
        _ThemeChoice(
          icon: Icons.brightness_auto_rounded,
          label: '跟随系统',
          selected: themeMode == ThemeMode.system,
          onTap: () => onChanged(ThemeMode.system),
        ),
        _ThemeChoice(
          icon: Icons.light_mode_rounded,
          label: '明亮',
          selected: themeMode == ThemeMode.light,
          onTap: () => onChanged(ThemeMode.light),
        ),
        _ThemeChoice(
          icon: Icons.dark_mode_rounded,
          label: '深色',
          selected: themeMode == ThemeMode.dark,
          onTap: () => onChanged(ThemeMode.dark),
        ),
      ],
    ),
  );
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Expanded(
      child: AnimatedContainer(
        duration: QingxuMotion.standard,
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? palette.accentStrong : palette.muted,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? palette.accentStrong : palette.muted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final palette = QingxuPalette.of(context);
      final (icon, color) = switch (controller.syncActivity) {
        SyncActivity.testing ||
        SyncActivity.syncing => (Icons.sync_rounded, palette.info),
        SyncActivity.success => (Icons.cloud_done_outlined, palette.success),
        SyncActivity.error => (Icons.cloud_off_outlined, palette.danger),
        SyncActivity.idle => (Icons.cloud_queue_outlined, palette.success),
        SyncActivity.unconfigured => (Icons.cloud_outlined, palette.faint),
      };
      return QingxuSurface(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.syncMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    controller.lastSyncedAt == null
                        ? '任务与番茄钟均会自动同步'
                        : '上次同步 ${_formatTime(controller.lastSyncedAt!)}',
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ),
            ),
            if (controller.isSyncBusy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
          ],
        ),
      );
    },
  );

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.helper,
    required this.child,
  });

  final String label;
  final String helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 6),
          Text(helper, style: TextStyle(fontSize: 11.5, color: palette.muted)),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 12, 0, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
