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

  Future<void> _openDurationSettings() async {
    final state = widget.controller.pomodoro;
    final values = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.36),
      builder: (context) => _DurationSettingsSheet(
        focusMinutes: state.focusMinutes,
        shortBreakMinutes: state.shortBreakMinutes,
        longBreakMinutes: state.longBreakMinutes,
      ),
    );
    if (!mounted || values == null) return;
    widget.controller.updatePomodoroDurations(
      focusMinutes: values[0],
      shortBreakMinutes: values[1],
      longBreakMinutes: values[2],
    );
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final state = widget.controller.pomodoro;
    final remainingSeconds = widget.controller.pomodoroRemainingSeconds;
    final remaining = Duration(seconds: remainingSeconds);
    final totalSeconds = state.configuredDurationFor(state.mode).inSeconds;
    final isRunning = state.status == PomodoroStatus.running;
    final isPaused = state.status == PomodoroStatus.paused;
    final modeLabel = switch (state.mode) {
      PomodoroMode.focus => isRunning ? '正在专注' : (isPaused ? '专注已暂停' : '准备专注'),
      PomodoroMode.shortBreak => isRunning ? '短暂休息' : '准备休息',
      PomodoroMode.longBreak => isRunning ? '充分休息' : '完成一轮',
    };

    if (qingxuIsDesktop) {
      return ColoredBox(
        color: palette.canvas,
        child: Column(
          children: [
            QingxuPageHeader(
              title: '番茄钟',
              subtitle: isRunning ? '计时状态正自动同步到其他设备' : '为眼前这一件事留出完整时间',
              trailing: _SyncDot(
                active: widget.controller.syncSettings.isConfigured,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(48, 10, 48, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: QingxuLayout.contentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          _ModePicker(
                            state: state,
                            onSelected: widget.controller.selectPomodoroMode,
                          ),
                          const SizedBox(height: 44),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Center(
                                  child: RepaintBoundary(
                                    child: _FocusDial(
                                      size: constraints.maxHeight < 610
                                          ? 218
                                          : 252,
                                      progress:
                                          (remainingSeconds / totalSeconds)
                                              .clamp(0, 1),
                                      time: _formatDuration(remaining),
                                      label: modeLabel,
                                      active: isRunning,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 250,
                                color: palette.border,
                              ),
                              const SizedBox(width: 54),
                              SizedBox(
                                width: 290,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isRunning ? '保持专注' : '准备开始',
                                      style: TextStyle(
                                        color: palette.ink,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isRunning
                                          ? '离开应用也不会中断，当前进度会继续同步。'
                                          : '选择时长后开始，清序会记住这台设备的偏好。',
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 12.5,
                                        height: 1.55,
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    _FocusActions(
                                      isRunning: isRunning,
                                      onToggle: _toggle,
                                      onReset: widget.controller.resetPomodoro,
                                      onSkip: widget.controller.skipPomodoro,
                                    ),
                                    const SizedBox(height: 28),
                                    _SessionSummary(
                                      completed: state.completedFocusSessions,
                                    ),
                                    const SizedBox(height: 18),
                                    TextButton.icon(
                                      onPressed: _openDurationSettings,
                                      icon: const Icon(
                                        Icons.tune_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('自定义计时时长'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
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
            title: '番茄钟',
            subtitle: isRunning ? '计时状态正自动同步到其他设备' : '一次只专注眼前这一件事',
            leading: widget.onMenu == null
                ? null
                : IconButton(
                    tooltip: '打开导航',
                    onPressed: widget.onMenu,
                    icon: const Icon(Icons.menu_rounded),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('pomodoro-duration-settings'),
                  tooltip: '自定义计时时长',
                  onPressed: _openDurationSettings,
                  icon: const Icon(Icons.tune_rounded, size: 21),
                ),
                const SizedBox(width: 8),
                _SyncDot(active: widget.controller.syncSettings.isConfigured),
              ],
            ),
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
                              progress: (remainingSeconds / totalSeconds).clamp(
                                0,
                                1,
                              ),
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
    final totalSeconds = duration.inSeconds.clamp(0, 999 * 60);
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
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _ModeButton(
                label: '专注 ${state.focusMinutes}',
                selected: state.mode == PomodoroMode.focus,
                onTap: () => onSelected(PomodoroMode.focus),
              ),
            ),
            Expanded(
              child: _ModeButton(
                label: '短休 ${state.shortBreakMinutes}',
                selected: state.mode == PomodoroMode.shortBreak,
                onTap: () => onSelected(PomodoroMode.shortBreak),
              ),
            ),
            Expanded(
              child: _ModeButton(
                label: '长休 ${state.longBreakMinutes}',
                selected: state.mode == PomodoroMode.longBreak,
                onTap: () => onSelected(PomodoroMode.longBreak),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationSettingsSheet extends StatefulWidget {
  const _DurationSettingsSheet({
    required this.focusMinutes,
    required this.shortBreakMinutes,
    required this.longBreakMinutes,
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  @override
  State<_DurationSettingsSheet> createState() => _DurationSettingsSheetState();
}

class _DurationSettingsSheetState extends State<_DurationSettingsSheet> {
  late int _focusMinutes = widget.focusMinutes;
  late int _shortBreakMinutes = widget.shortBreakMinutes;
  late int _longBreakMinutes = widget.longBreakMinutes;

  void _resetDefaults() {
    setState(() {
      _focusMinutes = PomodoroState.defaultFocusMinutes;
      _shortBreakMinutes = PomodoroState.defaultShortBreakMinutes;
      _longBreakMinutes = PomodoroState.defaultLongBreakMinutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: palette.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '计时时长',
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '保存后会从当前阶段的新时长重新开始，并同步到其他设备。',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _resetDefaults,
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _DurationStepper(
                    label: '专注',
                    detail: '1–180 分钟',
                    value: _focusMinutes,
                    minimum: 1,
                    maximum: 180,
                    onChanged: (value) => setState(() => _focusMinutes = value),
                  ),
                  const SizedBox(height: 10),
                  _DurationStepper(
                    label: '短休息',
                    detail: '1–60 分钟',
                    value: _shortBreakMinutes,
                    minimum: 1,
                    maximum: 60,
                    onChanged: (value) =>
                        setState(() => _shortBreakMinutes = value),
                  ),
                  const SizedBox(height: 10),
                  _DurationStepper(
                    label: '长休息',
                    detail: '1–120 分钟',
                    value: _longBreakMinutes,
                    minimum: 1,
                    maximum: 120,
                    onChanged: (value) =>
                        setState(() => _longBreakMinutes = value),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('save-pomodoro-durations'),
                      onPressed: () => Navigator.of(context).pop([
                        _focusMinutes,
                        _shortBreakMinutes,
                        _longBreakMinutes,
                      ]),
                      child: const Text('保存时长'),
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

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({
    required this.label,
    required this.detail,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final int value;
  final int minimum;
  final int maximum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '减少 1 分钟',
              onPressed: value > minimum ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$value 分钟',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              tooltip: '增加 1 分钟',
              onPressed: value < maximum ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
                      Text(
                        label,
                        style: TextStyle(fontSize: 13, color: palette.muted),
                      ),
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
                  color: index < completedInRound
                      ? palette.accent
                      : palette.border,
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
