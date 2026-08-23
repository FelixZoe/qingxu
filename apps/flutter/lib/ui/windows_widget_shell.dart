import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../models/pomodoro_state.dart';
import '../models/task_item.dart';
import '../state/task_controller.dart';
import 'design_system.dart';
import 'sync_settings_page.dart';

class WindowsWidgetShell extends StatefulWidget {
  const WindowsWidgetShell({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final TaskController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<WindowsWidgetShell> createState() => _WindowsWidgetShellState();
}

class _WindowsWidgetShellState extends State<WindowsWidgetShell>
    with tray.TrayListener, WindowListener {
  static const _collapsedSize = Size(196, 72);
  static const _expandedSize = Size(286, 296);
  static const _settingsSize = Size(360, 560);

  Timer? _ticker;
  Timer? _collapseTimer;
  bool _showSettings = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    windowManager.addListener(this);
    tray.trayManager.addListener(this);
    unawaited(_initializeTray());
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      widget.controller.advancePomodoroIfNeeded();
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant WindowsWidgetShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _collapseTimer?.cancel();
    widget.controller.removeListener(_refresh);
    windowManager.removeListener(this);
    tray.trayManager.removeListener(this);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeTray() async {
    final separator = Platform.pathSeparator;
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final iconPath = [
      executableDirectory,
      'data',
      'flutter_assets',
      'assets',
      'branding',
      'qingxu-tray.ico',
    ].join(separator);
    try {
      await tray.trayManager.setIcon(iconPath);
      await tray.trayManager.setToolTip('清序 · 今日待办与番茄钟');
      await tray.trayManager.setContextMenu(
        tray.Menu(
          items: [
            tray.MenuItem(key: 'toggle_window', label: '显示 / 隐藏悬浮窗'),
            tray.MenuItem(key: 'settings', label: '设置'),
            tray.MenuItem.separator(),
            tray.MenuItem(key: 'exit', label: '退出清序'),
          ],
        ),
      );
    } on Object {
      // The floating widget remains usable if Explorer is restarting.
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_toggleWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(tray.trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle_window':
        unawaited(_toggleWindow());
      case 'settings':
        unawaited(_openSettings());
      case 'exit':
        unawaited(_exitApplication());
    }
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  Future<void> _toggleWindow() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
      return;
    }
    if (mounted) {
      setState(() {
        _showSettings = false;
        _expanded = false;
      });
    }
    await _resize(_collapsedSize);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApplication() async {
    windowManager.removeListener(this);
    await tray.trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _resize(Size size) async {
    await windowManager.setSize(size);
    await windowManager.setAlignment(Alignment.topRight);
  }

  Future<void> _expand() async {
    _collapseTimer?.cancel();
    if (_expanded || _showSettings) return;
    await _resize(_expandedSize);
    if (mounted) setState(() => _expanded = true);
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    if (_showSettings) return;
    _collapseTimer = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted || _showSettings) return;
      setState(() => _expanded = false);
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (mounted && !_showSettings) await _resize(_collapsedSize);
    });
  }

  Future<void> _openSettings() async {
    _collapseTimer?.cancel();
    await windowManager.show();
    await _resize(_settingsSize);
    if (mounted) {
      setState(() {
        _showSettings = true;
        _expanded = false;
      });
    }
    await windowManager.focus();
  }

  Future<void> _closeSettings() async {
    if (mounted) {
      setState(() {
        _showSettings = false;
        _expanded = false;
      });
    }
    await _resize(_collapsedSize);
  }

  List<TaskItem> get _todayTasks {
    final now = DateTime.now();
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final tasks = widget.controller.tasks.where((task) {
      if (!task.isOpen || task.deletedAt != null) return false;
      final start = task.startAt?.toLocal();
      return start != null && start.isBefore(tomorrow);
    }).toList();
    tasks.sort((a, b) {
      final aTime = a.startAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.startAt?.millisecondsSinceEpoch ?? 0;
      return aTime == bTime
          ? a.order.compareTo(b.order)
          : aTime.compareTo(bTime);
    });
    return tasks;
  }

  Future<void> _addTask() async {
    final title = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.14),
      builder: (context) => const _WidgetAddDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    widget.controller.selectView('today');
    widget.controller.addTask(title.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        onEnter: (_) => unawaited(_expand()),
        onExit: (_) => _scheduleCollapse(),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
            if (_showSettings)
              _FloatingSettings(
                controller: widget.controller,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
                onClose: () => unawaited(_closeSettings()),
              )
            else if (!_expanded)
              Center(
                child: _TimerCapsule(
                  controller: widget.controller,
                  expanded: false,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                child: Column(
                  children: [
                    _TimerCapsule(
                      controller: widget.controller,
                      expanded: true,
                    ),
                    const SizedBox(height: 8),
                    _TodayPanel(
                      controller: widget.controller,
                      tasks: _todayTasks,
                      onAdd: _addTask,
                      height: 202,
                      maxTasks: 3,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({
    required this.controller,
    required this.tasks,
    required this.onAdd,
    this.height = 224,
    this.maxTasks = 4,
  });

  final TaskController controller;
  final List<TaskItem> tasks;
  final VoidCallback onAdd;
  final double height;
  final int maxTasks;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final visible = tasks.take(maxTasks).toList();
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(18, 15, 14, 12),
      decoration: _floatingDecoration(context, radius: 22),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今日待办',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _todayLabel(),
                    style: TextStyle(color: palette.faint, fontSize: 10.5),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${tasks.length}',
                style: TextStyle(color: palette.faint, fontSize: 11),
              ),
              const SizedBox(width: 3),
              _HoverButton(
                tooltip: '新增今日任务',
                icon: Icons.add_rounded,
                onPressed: onAdd,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      '今天没有待办',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  )
                : Column(
                    children: [
                      for (final task in visible)
                        _TodayTaskRow(controller: controller, task: task),
                      if (tasks.length > visible.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '还有 ${tasks.length - visible.length} 项',
                            style: TextStyle(
                              color: palette.faint,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _todayLabel() {
    final now = DateTime.now();
    return '${now.month} 月 ${now.day} 日';
  }
}

class _TodayTaskRow extends StatelessWidget {
  const _TodayTaskRow({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return SizedBox(
      height: 35,
      child: Row(
        children: [
          InkResponse(
            radius: 18,
            onTap: () => controller.toggleTask(task),
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.faint, width: 1.2),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.ink, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerCapsule extends StatelessWidget {
  const _TimerCapsule({required this.controller, required this.expanded});

  final TaskController controller;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final state = controller.pomodoro;
    final remaining = controller.pomodoroRemainingSeconds;
    final total = state.configuredDurationFor(state.mode).inSeconds;
    final running = state.status == PomodoroStatus.running;
    final progress = total == 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    final mode = switch (state.mode) {
      PomodoroMode.focus => '专注',
      PomodoroMode.shortBreak => '短休',
      PomodoroMode.longBreak => '长休',
    };

    return DragToMoveArea(
      child: Container(
        width: expanded ? 270 : 188,
        height: 62,
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: _floatingDecoration(context, radius: 31, shadow: false),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: palette.border.withValues(alpha: 0.72),
                    valueColor: AlwaysStoppedAnimation(palette.accent),
                  ),
                  IconButton(
                    tooltip: running ? '暂停' : '开始',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.togglePomodoro,
                    icon: Icon(
                      running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20,
                      color: palette.accentStrong,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopupMenuButton<PomodoroMode>(
                    tooltip: '切换计时模式',
                    initialValue: state.mode,
                    onSelected: controller.selectPomodoroMode,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: PomodoroMode.focus,
                        child: Text('专注'),
                      ),
                      PopupMenuItem(
                        value: PomodoroMode.shortBreak,
                        child: Text('短休'),
                      ),
                      PopupMenuItem(
                        value: PomodoroMode.longBreak,
                        child: Text('长休'),
                      ),
                    ],
                    child: Text(
                      mode,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatSeconds(remaining),
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 23,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (expanded)
              _OrbButton(
                tooltip: '重置',
                icon: Icons.replay_rounded,
                onPressed: controller.resetPomodoro,
              ),
          ],
        ),
      ),
    );
  }

  static String _formatSeconds(int value) {
    final minutes = (value ~/ 60).toString().padLeft(2, '0');
    final seconds = (value % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _OrbButton extends StatelessWidget {
  const _OrbButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.accentSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: palette.accentStrong),
          ),
        ),
      ),
    );
  }
}

class _HoverButton extends StatelessWidget {
  const _HoverButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: palette.surface.withValues(alpha: 0.74),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: palette.muted),
    );
  }
}

class _FloatingSettings extends StatelessWidget {
  const _FloatingSettings({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onClose,
  });

  final TaskController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(9),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          SyncSettingsPage(
            controller: controller,
            embedded: true,
            themeMode: themeMode,
            onThemeModeChanged: onThemeModeChanged,
          ),
          Positioned(
            top: 12,
            right: 10,
            child: _HoverButton(
              tooltip: '返回悬浮窗',
              icon: Icons.close_rounded,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    ),
  );
}

class _WidgetAddDialog extends StatefulWidget {
  const _WidgetAddDialog();

  @override
  State<_WidgetAddDialog> createState() => _WidgetAddDialogState();
}

class _WidgetAddDialogState extends State<_WidgetAddDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加到今天'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: '要做什么？'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('添加')),
    ],
  );
}

BoxDecoration _floatingDecoration(
  BuildContext context, {
  double? radius,
  BoxShape shape = BoxShape.rectangle,
  bool shadow = true,
}) {
  final palette = QingxuPalette.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    shape: shape,
    color: palette.surfaceRaised.withValues(alpha: dark ? 0.92 : 0.94),
    borderRadius: shape == BoxShape.rectangle
        ? BorderRadius.circular(radius ?? 20)
        : null,
    border: Border.all(
      color: palette.border.withValues(alpha: dark ? 0.9 : 0.72),
    ),
    boxShadow: shadow
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ]
        : const [],
  );
}
