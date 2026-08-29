import 'dart:async';
import 'dart:io';
import 'dart:ui';

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
  static const _collapsedSize = Size(166, 52);
  static const _expandedSize = Size(166, 286);
  static const _settingsSize = Size(320, 480);

  Timer? _ticker;
  Timer? _expandTimer;
  Timer? _collapseTimer;
  Timer? _transitionTimer;
  bool _showSettings = false;
  bool _expanded = false;
  bool _pointerInside = false;
  bool _resizing = false;
  int _windowRequest = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    windowManager.addListener(this);
    tray.trayManager.addListener(this);
    unawaited(_initializeTray());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
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
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    _transitionTimer?.cancel();
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
        _pointerInside = false;
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
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    if (_expanded || _showSettings || !_pointerInside) return;
    final request = ++_windowRequest;
    _resizing = true;
    if (mounted) setState(() => _expanded = true);
    await _resize(_expandedSize);
    if (!mounted || request != _windowRequest) return;
    _transitionTimer?.cancel();
    _transitionTimer = Timer(const Duration(milliseconds: 220), () {
      _resizing = false;
      if (!_pointerInside) _scheduleCollapse();
    });
  }

  void _scheduleExpand() {
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    if (_expanded || _showSettings) return;
    _expandTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _pointerInside && !_showSettings) {
        unawaited(_expand());
      }
    });
  }

  void _scheduleCollapse() {
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    if (_showSettings || _resizing) return;
    _collapseTimer = Timer(const Duration(milliseconds: 680), () async {
      if (!mounted || _showSettings || _pointerInside || _resizing) return;
      final request = ++_windowRequest;
      _resizing = true;
      setState(() => _expanded = false);
      if (mounted &&
          request == _windowRequest &&
          !_showSettings &&
          !_pointerInside) {
        await _resize(_collapsedSize);
      }
      _transitionTimer?.cancel();
      _transitionTimer = Timer(const Duration(milliseconds: 180), () {
        _resizing = false;
      });
    });
  }

  Future<void> _openSettings() async {
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    _transitionTimer?.cancel();
    _resizing = false;
    ++_windowRequest;
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
    _transitionTimer?.cancel();
    ++_windowRequest;
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

  void _addTask(String title) {
    if (title.trim().isEmpty) return;
    widget.controller.selectView('today');
    widget.controller.addTask(title.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        onEnter: (_) {
          _pointerInside = true;
          _scheduleExpand();
        },
        onExit: (_) {
          _pointerInside = false;
          _scheduleCollapse();
        },
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
                child: RepaintBoundary(
                  child: _TimerCapsule(
                    controller: widget.controller,
                    expanded: false,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RepaintBoundary(
                      child: _TimerCapsule(
                        controller: widget.controller,
                        expanded: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TodayPanel(
                      controller: widget.controller,
                      tasks: _todayTasks,
                      onAdd: _addTask,
                      height: 222,
                      maxTasks: 5,
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

class _TodayPanel extends StatefulWidget {
  const _TodayPanel({
    required this.controller,
    required this.tasks,
    required this.onAdd,
    this.height = 224,
    this.maxTasks = 4,
  });

  final TaskController controller;
  final List<TaskItem> tasks;
  final ValueChanged<String> onAdd;
  final double height;
  final int maxTasks;

  @override
  State<_TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<_TodayPanel> {
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  void _beginAdding() {
    setState(() => _adding = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _quickAddFocus.requestFocus();
    });
  }

  void _cancelAdding() {
    _quickAddController.clear();
    setState(() => _adding = false);
  }

  void _submit() {
    final value = _quickAddController.text.trim();
    if (value.isEmpty) {
      _cancelAdding();
      return;
    }
    widget.onAdd(value);
    _quickAddController.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final visible = widget.tasks
        .take(_adding ? widget.maxTasks - 1 : widget.maxTasks)
        .toList();
    return _FrostedSurface(
      key: const ValueKey('windows-today-panel'),
      height: widget.height,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              _SyncDot(activity: widget.controller.syncActivity),
              const SizedBox(width: 6),
              Text(
                '${widget.tasks.length}',
                style: TextStyle(color: palette.faint, fontSize: 10.5),
              ),
              const SizedBox(width: 3),
              _HoverButton(
                tooltip: '新增今日任务',
                icon: Icons.add_rounded,
                onPressed: _beginAdding,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: visible.isEmpty && !_adding
                ? Center(
                    child: Text(
                      '今天很清静',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.vertical,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      if (_adding)
                        _QuickAddRow(
                          controller: _quickAddController,
                          focusNode: _quickAddFocus,
                          onSubmitted: _submit,
                          onCancel: _cancelAdding,
                        ),
                      for (final task in visible)
                        _TodayTaskRow(
                          controller: widget.controller,
                          task: task,
                        ),
                      if (widget.tasks.length > visible.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '还有 ${widget.tasks.length - visible.length} 项',
                            textAlign: TextAlign.center,
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => controller.toggleTask(task),
        child: SizedBox(
          height: 35,
          child: Row(
            children: [
              const SizedBox(width: 4),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.faint, width: 1.2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAddRow extends StatelessWidget {
  const _QuickAddRow({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return SizedBox(
      height: 35,
      child: TextField(
        key: const ValueKey('windows-quick-add'),
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.done,
        style: TextStyle(color: palette.ink, fontSize: 12),
        onSubmitted: (_) => onSubmitted(),
        decoration: InputDecoration(
          hintText: '添加今天的任务',
          hintStyle: TextStyle(color: palette.faint, fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: 30,
            height: 30,
          ),
          suffixIcon: IconButton(
            tooltip: '取消',
            padding: EdgeInsets.zero,
            onPressed: onCancel,
            icon: Icon(Icons.close_rounded, size: 15, color: palette.faint),
          ),
        ),
      ),
    );
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.activity});

  final SyncActivity activity;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final (color, label) = switch (activity) {
      SyncActivity.success => (palette.success, '同步完成'),
      SyncActivity.syncing || SyncActivity.testing => (palette.accent, '正在同步'),
      SyncActivity.error => (palette.danger, '同步异常'),
      SyncActivity.idle => (palette.faint, '等待同步'),
      SyncActivity.unconfigured => (palette.border, '仅保存在本地'),
    };
    return Tooltip(
      message: label,
      child: AnimatedContainer(
        duration: QingxuMotion.quick,
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
      child: _FrostedSurface(
        key: const ValueKey('windows-timer-capsule'),
        width: expanded ? 154 : 158,
        height: 44,
        radius: 22,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(6, 5, 9, 5),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.2,
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
                      size: 16,
                      color: palette.accentStrong,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
                        fontSize: 8.5,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatSeconds(remaining),
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 18,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.35,
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
            width: 28,
            height: 28,
            child: Icon(icon, size: 15, color: palette.accentStrong),
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
    padding: const EdgeInsets.all(5),
    child: _FrostedSurface(
      radius: 20,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          SyncSettingsPage(
            controller: controller,
            embedded: true,
            themeMode: themeMode,
            onThemeModeChanged: onThemeModeChanged,
          ),
          Positioned(
            top: 8,
            right: 7,
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

class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({
    required this.child,
    this.width,
    this.height,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    super.key,
  });

  final Widget child;
  final double? width;
  final double? height;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: palette.surfaceRaised.withValues(
              alpha: dark ? 0.70 : 0.74,
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: palette.border.withValues(alpha: dark ? 0.62 : 0.54),
            ),
            boxShadow: shadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: dark ? 0.11 : 0.045,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : const [],
          ),
          child: child,
        ),
      ),
    );
  }
}
