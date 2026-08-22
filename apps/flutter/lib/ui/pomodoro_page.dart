import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
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
    final remaining = Duration(
      seconds: widget.controller.pomodoroRemainingSeconds,
    );
    final total = PomodoroState.durationFor(state.mode);
    final isRunning = state.status == PomodoroStatus.running;
    final useCupertinoNavigation =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final modeLabel = switch (state.mode) {
      PomodoroMode.focus => '保持专注',
      PomodoroMode.shortBreak => '短暂休息',
      PomodoroMode.longBreak => '完成一轮，充分休息',
    };

    return ColoredBox(
      color: palette.surface,
      child: Column(
        children: [
          if (useCupertinoNavigation)
            CupertinoNavigationBar(
              backgroundColor: palette.surface.withValues(alpha: 0.94),
              border: Border(
                bottom: BorderSide(color: palette.border, width: 0.5),
              ),
              middle: const Text('番茄钟'),
            )
          else
            _DesktopHeader(onMenu: widget.onMenu),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.canvas,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: palette.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                      child: Column(
                        children: [
                          SegmentedButton<PomodoroMode>(
                            segments: const [
                              ButtonSegment(
                                value: PomodoroMode.focus,
                                label: Text('专注 25 分钟'),
                              ),
                              ButtonSegment(
                                value: PomodoroMode.shortBreak,
                                label: Text('休息 5 分钟'),
                              ),
                            ],
                            selected: {
                              state.mode == PomodoroMode.longBreak
                                  ? PomodoroMode.shortBreak
                                  : state.mode,
                            },
                            showSelectedIcon: false,
                            onSelectionChanged: (selection) => widget.controller
                                .selectPomodoroMode(selection.first),
                          ),
                          const SizedBox(height: 40),
                          RepaintBoundary(
                            child: SizedBox(
                              width: 248,
                              height: 248,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(
                                      end:
                                          (remaining.inMilliseconds /
                                                  total.inMilliseconds)
                                              .clamp(0, 1),
                                    ),
                                    duration: QingxuMotion.standard,
                                    curve: Curves.linear,
                                    builder: (context, progress, _) =>
                                        CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 8,
                                          strokeCap: StrokeCap.round,
                                          backgroundColor: palette.border,
                                          color: palette.accent,
                                        ),
                                  ),
                                  Center(
                                    child: Semantics(
                                      liveRegion: true,
                                      label:
                                          '$modeLabel，剩余 ${_formatDuration(remaining)}',
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _formatDuration(remaining),
                                            key: const ValueKey(
                                              'pomodoro-time',
                                            ),
                                            style: TextStyle(
                                              fontSize: 58,
                                              height: 1,
                                              color: palette.ink,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -2,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          AnimatedSwitcher(
                                            duration: QingxuMotion.standard,
                                            child: Text(
                                              modeLabel,
                                              key: ValueKey(state.mode),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: palette.muted,
                                              ),
                                            ),
                                          ),
                                          if (isRunning) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              '已在所有设备自动同步',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: palette.success,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 34),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              IconButton.outlined(
                                tooltip: '重置当前阶段',
                                onPressed: widget.controller.resetPomodoro,
                                icon: const Icon(Icons.restart_alt_rounded),
                              ),
                              FilledButton.icon(
                                key: const ValueKey('pomodoro-toggle'),
                                onPressed: _toggle,
                                icon: AnimatedSwitcher(
                                  duration: QingxuMotion.quick,
                                  child: Icon(
                                    isRunning
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey(isRunning),
                                  ),
                                ),
                                label: Text(isRunning ? '暂停' : '开始专注'),
                              ),
                              IconButton.outlined(
                                tooltip: '跳过当前阶段',
                                onPressed: widget.controller.skipPomodoro,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          _RoundProgress(
                            completed: state.completedFocusSessions,
                            total: 4,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '已完成 ${state.completedFocusSessions} 个专注时段',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
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

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 99 * 60);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _RoundProgress extends StatelessWidget {
  const _RoundProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final completedInRound = completed % total;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < total; index++) ...[
          AnimatedContainer(
            duration: QingxuMotion.standard,
            width: index < completedInRound ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: index < completedInRound ? palette.accent : palette.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          if (index != total - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({this.onMenu});

  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Container(
      height: 122,
      padding: const EdgeInsets.fromLTRB(34, 27, 32, 18),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onMenu != null) ...[
            IconButton(onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
            const SizedBox(width: 8),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '专注工具',
                style: TextStyle(
                  fontSize: 11,
                  color: palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                '番茄钟',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
