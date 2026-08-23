import 'dart:async';

import 'package:flutter/material.dart';

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
  Timer? _ticker;
  bool _showSettings = false;

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
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
      builder: (context) => const _WidgetAddDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    widget.controller.selectView('today');
    widget.controller.addTask(title.trim());
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    if (_showSettings) {
      return ColoredBox(
        color: palette.canvas,
        child: Stack(
          children: [
            SyncSettingsPage(
              controller: widget.controller,
              embedded: true,
              themeMode: widget.themeMode,
              onThemeModeChanged: widget.onThemeModeChanged,
            ),
            Positioned(
              top: 14,
              right: 12,
              child: IconButton(
                tooltip: '返回小组件',
                onPressed: () => setState(() => _showSettings = false),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      );
    }

    final tasks = _todayTasks;
    return ColoredBox(
      color: palette.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WidgetHeader(
                controller: widget.controller,
                onSettings: () => setState(() => _showSettings = true),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '今日待办',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${tasks.length} 项',
                    style: TextStyle(color: palette.faint, fontSize: 11),
                  ),
                  const SizedBox(width: 5),
                  IconButton(
                    tooltip: '新增今日任务',
                    visualDensity: VisualDensity.compact,
                    onPressed: _addTask,
                    icon: Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: palette.accentStrong,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Expanded(
                child: tasks.isEmpty
                    ? _WidgetEmptyState(onAdd: _addTask)
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: tasks.length,
                        itemBuilder: (context, index) => _TodayTaskRow(
                          controller: widget.controller,
                          task: tasks[index],
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              _MiniPomodoro(controller: widget.controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetHeader extends StatelessWidget {
  const _WidgetHeader({required this.controller, required this.onSettings});

  final TaskController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset(
            dark
                ? 'assets/branding/qingxu-icon-master-white.png'
                : 'assets/branding/qingxu-icon-master-black.png',
            width: 28,
            height: 28,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${now.month} 月 ${now.day} 日  ${weekdays[now.weekday - 1]}',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                controller.syncSettings.isConfigured ? '已连接并自动同步' : '当前仅保存在本地',
                style: TextStyle(color: palette.faint, fontSize: 10.5),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '设置',
          visualDensity: VisualDensity.compact,
          onPressed: onSettings,
          icon: Icon(Icons.tune_rounded, size: 18, color: palette.muted),
        ),
      ],
    );
  }
}

class _TodayTaskRow extends StatelessWidget {
  const _TodayTaskRow({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final local = task.startAt?.toLocal();
    final time = local == null
        ? null
        : '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          InkResponse(
            radius: 20,
            onTap: () => controller.toggleTask(task),
            child: Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.faint, width: 1.3),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.ink, fontSize: 12.5),
            ),
          ),
          if (time != null)
            Text(time, style: TextStyle(color: palette.faint, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _WidgetEmptyState extends StatelessWidget {
  const _WidgetEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: palette.faint,
            size: 27,
          ),
          const SizedBox(height: 9),
          Text('今天已经清空', style: TextStyle(color: palette.muted, fontSize: 12)),
          const SizedBox(height: 5),
          TextButton(onPressed: onAdd, child: const Text('添加一项')),
        ],
      ),
    );
  }
}

class _MiniPomodoro extends StatelessWidget {
  const _MiniPomodoro({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final state = controller.pomodoro;
    final remaining = controller.pomodoroRemainingSeconds;
    final total = state.configuredDurationFor(state.mode).inSeconds;
    final running = state.status == PomodoroStatus.running;
    final mode = switch (state.mode) {
      PomodoroMode.focus => '专注',
      PomodoroMode.shortBreak => '短休',
      PomodoroMode.longBreak => '长休',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 13),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode,
                      style: TextStyle(color: palette.muted, fontSize: 10.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSeconds(remaining),
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: running ? '暂停' : '开始',
                style: IconButton.styleFrom(
                  backgroundColor: palette.accentStrong,
                  foregroundColor: Colors.white,
                ),
                onPressed: controller.togglePomodoro,
                icon: Icon(
                  running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                tooltip: '重置',
                onPressed: controller.resetPomodoro,
                icon: const Icon(Icons.replay_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (remaining / total).clamp(0, 1),
              minHeight: 3,
              backgroundColor: palette.border,
              valueColor: AlwaysStoppedAnimation(palette.accent),
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
