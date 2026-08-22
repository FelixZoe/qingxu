import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pomodoro_state.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({required this.controller, this.onMenu, super.key});

  final TaskController controller;
  final VoidCallback? onMenu;

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final completed = widget.controller.advancePomodoroIfNeeded();
      if (completed) unawaited(HapticFeedback.mediumImpact());
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PomodoroPage oldWidget) {
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

  void _toggle() {
    widget.controller.togglePomodoro();
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final state = widget.controller.pomodoro;
    final remainingSeconds = widget.controller.pomodoroRemainingSeconds;
    final remaining = Duration(seconds: remainingSeconds);
    final totalSeconds = PomodoroState.durationFor(state.mode).inSeconds;
    final isRunning = state.status == PomodoroStatus.running;
    final isPaused = state.status == PomodoroStatus.paused;
    final modeLabel = switch (state.mode) {
      PomodoroMode.focus => isRunning ? '正在专注' : (isPaused ? '专注已暂停' : '准备专注'),
      PomodoroMode.shortBreak => isRunning ? '短暂休息' : '准备休息',
      PomodoroMode.longBreak => isRunning ? '充分休息' : '完成一轮',
    };

    return ColoredBox(
      color: palette.canvas,
      child: Column(
        children: [
          QingxuPageHeader(
            title: '番茄钟',
            subtitle: isRunning ? '计时状态正自动同步到其他设备' : '一次只专注眼前这一件事',
            leading: widget.onMenu == null
                ? null
                : IconButton(
                    tooltip: '打开导航',
                    onPressed: widget.onMenu,
                    icon: const Icon(Icons.menu_rounded),
                  ),
            trailing: _SyncDot(active: widget.controller.syncSettings.isConfigured),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = constraints.maxHeight < 620;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    QingxuLayout.gutterFor(constraints.maxWidth),
                    compactHeight ? 4 : 18,
                    QingxuLayout.gutterFor(constraints.maxWidth),
                    28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        children: [
                          _ModePicker(
                            state: state,
                            onSelected: widget.controller.selectPomodoroMode,
                          ),
                          SizedBox(height: compactHeight ? 28 : 46),
                          RepaintBoundary(
                            child: _FocusDial(
                              size: compactHeight ? 210 : 246,
                              progress: (remainingSeconds / totalSeconds).clamp(0, 1),
                              time: _formatDuration(remaining),
                              label: modeLabel,
                              active: isRunning,
                            ),
                          ),
                          SizedBox(height: compactHeight ? 28 : 40),
                          _FocusActions(
                            isRunning: isRunning,
                            onToggle: _toggle,
                            onReset: widget.controller.resetPomodoro,
                            onSkip: widget.controller.skipPomodoro,
                          ),
                          SizedBox(height: compactHeight ? 26 : 38),
                          _SessionSummary(
                            completed: state.completedFocusSessions,
                          ),
                        ],
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

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 99 * 60);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.state, required this.onSelected});

  final PomodoroState state;
  final ValueChanged<PomodoroMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final selected = state.mode == PomodoroMode.focus
        ? PomodoroMode.focus
        : PomodoroMode.shortBreak;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              label: '专注 25 分钟',
              selected: selected == PomodoroMode.focus,
              onTap: () => onSelected(PomodoroMode.focus),
            ),
            _ModeButton(
              label: state.mode == PomodoroMode.longBreak ? '长休息 15 分钟' : '休息 5 分钟',
              selected: selected == PomodoroMode.shortBreak,
              onTap: () => onSelected(PomodoroMode.shortBreak),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return AnimatedContainer(
      duration: QingxuMotion.standard,
      curve: QingxuMotion.curve,
      decoration: BoxDecoration(
        color: selected ? palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? palette.accentStrong : palette.muted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusDial extends StatelessWidget {
  const _FocusDial({
    required this.size,
    required this.progress,
    required this.time,
    required this.label,
    required this.active,
  });

  final double size;
  final double progress;
  final String time;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: QingxuMotion.standard,
      curve: Curves.linear,
      builder: (context, animatedProgress, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DialPainter(
            progress: animatedProgress,
            trackColor: palette.border,
            progressColor: palette.accent,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  key: const ValueKey('pomodoro-time'),
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: size < 230 ? 50 : 58,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: QingxuMotion.standard,
                  child: Row(
                    key: ValueKey('$label-$active'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (active) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: palette.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                      ],
                      Text(label, style: TextStyle(fontSize: 13, color: palette.muted)),
                    ],
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

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      trackColor != oldDelegate.trackColor ||
      progressColor != oldDelegate.progressColor;
}

class _FocusActions extends StatelessWidget {
  const _FocusActions({
    required this.isRunning,
    required this.onToggle,
    required this.onReset,
    required this.onSkip,
  });

  final bool isRunning;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton.outlined(
        tooltip: '重置当前阶段',
        onPressed: onReset,
        icon: const Icon(Icons.restart_alt_rounded),
      ),
      const SizedBox(width: 14),
      FilledButton.icon(
        key: const ValueKey('pomodoro-toggle'),
        onPressed: onToggle,
        icon: AnimatedSwitcher(
          duration: QingxuMotion.quick,
          child: Icon(
            isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(isRunning),
          ),
        ),
        label: Text(isRunning ? '暂停' : '开始专注'),
      ),
      const SizedBox(width: 14),
      IconButton.outlined(
        tooltip: '跳过当前阶段',
        onPressed: onSkip,
        icon: const Icon(Icons.skip_next_rounded),
      ),
    ],
  );
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.completed});

  final int completed;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final completedInRound = completed % 4;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < 4; index++) ...[
              AnimatedContainer(
                duration: QingxuMotion.standard,
                width: index < completedInRound ? 26 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index < completedInRound ? palette.accent : palette.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              if (index != 3) const SizedBox(width: 7),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          completed == 0 ? '今天还没有完成专注时段' : '今天已完成 $completed 个专注时段',
          style: TextStyle(fontSize: 12.5, color: palette.muted),
        ),
      ],
    );
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Tooltip(
      message: active ? '多端同步已配置' : '尚未配置同步',
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: active ? palette.success : palette.faint,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
