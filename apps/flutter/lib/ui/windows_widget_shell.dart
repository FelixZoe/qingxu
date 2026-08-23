import 'dart:async';

import 'package:flutter/material.dart';
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

class _WindowsWidgetShellState extends State<WindowsWidgetShell> {
  static const _collapsedSize = Size(184, 184);
  static const _expandedSize = Size(308, 438);
  static const _settingsSize = Size(360, 560);

  Timer? _ticker;
  Timer? _collapseTimer;
  bool _showSettings = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
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
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    await _resize(_settingsSize);
    if (mounted) setState(() => _showSettings = true);
  }

  Future<void> _closeSettings() async {
    if (mounted) {
      setState(() {
        _showSettings = false;
        _expanded = true;
      });
    }
    await _resize(_expandedSize);
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
                child: _TimerOrb(
                  controller: widget.controller,
                  size: 164,
                  expanded: false,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                child: Column(
                  children: [
                    _FloatingHandle(
                      controller: widget.controller,
                      onSettings: () => unawaited(_openSettings()),
                    ),
                    const SizedBox(height: 6),
                    _TodayPanel(
                      controller: widget.controller,
                      tasks: _todayTasks,
                      onAdd: _addTask,
                      height: 158,
                      maxTasks: 3,
                    ),
                    const Spacer(),
                    _TimerOrb(
                      controller: widget.controller,
                      size: 194,
                      expanded: true,
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

class _FloatingHandle extends StatelessWidget {
  const _FloatingHandle({required this.controller, required this.onSettings});

  final TaskController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: controller.syncSettings.isConfigured
                          ? palette.success
                          : palette.faint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '清序',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _HoverButton(
            tooltip: '设置',
            icon: Icons.tune_rounded,
            onPressed: onSettings,
          ),
          _HoverButton(
            tooltip: '关闭',
            icon: Icons.close_rounded,
            onPressed: windowManager.close,
          ),
        ],
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

class _TimerOrb extends StatelessWidget {
  const _TimerOrb({
    required this.controller,
    required this.size,
    required this.expanded,
  });

  final TaskController controller;
  final double size;
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

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(expanded ? 10 : 8),
      decoration: _floatingDecoration(context, shape: BoxShape.circle),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            strokeCap: StrokeCap.round,
            backgroundColor: palette.border.withValues(alpha: 0.72),
            valueColor: AlwaysStoppedAnimation(palette.accent),
          ),
          Padding(
            padding: EdgeInsets.all(expanded ? 16 : 13),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surface.withValues(alpha: 0.72),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (expanded)
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
                        style: TextStyle(color: palette.muted, fontSize: 10.5),
                      ),
                    ),
                  if (expanded) const SizedBox(height: 2),
                  Text(
                    _formatSeconds(remaining),
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: expanded ? 31 : 29,
                      height: 1.1,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (expanded) const SizedBox(height: 7),
                  if (expanded)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OrbButton(
                          tooltip: running ? '暂停' : '开始',
                          icon: running
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          primary: true,
                          onPressed: controller.togglePomodoro,
                        ),
                        const SizedBox(width: 8),
                        _OrbButton(
                          tooltip: '重置',
                          icon: Icons.replay_rounded,
                          onPressed: controller.resetPomodoro,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
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
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary ? palette.accentStrong : palette.accentSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 18,
              color: primary ? Colors.white : palette.accentStrong,
            ),
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
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.28 : 0.12),
        blurRadius: 26,
        offset: const Offset(0, 10),
      ),
    ],
  );
}
