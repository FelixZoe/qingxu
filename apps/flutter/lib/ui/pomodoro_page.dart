import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum _PomodoroMode { focus, shortBreak }

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({this.onMenu, super.key});

  final VoidCallback? onMenu;

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  static const _focusDuration = Duration(minutes: 25);
  static const _breakDuration = Duration(minutes: 5);

  _PomodoroMode _mode = _PomodoroMode.focus;
  Duration _remaining = _focusDuration;
  Timer? _timer;
  int _completedFocusSessions = 0;

  Duration get _totalDuration =>
      _mode == _PomodoroMode.focus ? _focusDuration : _breakDuration;

  bool get _isRunning => _timer?.isActive ?? false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() {});
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining > const Duration(seconds: 1)) {
        setState(() => _remaining -= const Duration(seconds: 1));
        return;
      }

      _timer?.cancel();
      setState(() {
        if (_mode == _PomodoroMode.focus) _completedFocusSessions += 1;
        _mode = _mode == _PomodoroMode.focus
            ? _PomodoroMode.shortBreak
            : _PomodoroMode.focus;
        _remaining = _totalDuration;
      });
    });
    setState(() {});
  }

  void _reset() {
    _timer?.cancel();
    setState(() => _remaining = _totalDuration);
  }

  void _selectMode(_PomodoroMode mode) {
    _timer?.cancel();
    setState(() {
      _mode = mode;
      _remaining = _totalDuration;
    });
  }

  @override
  Widget build(BuildContext context) {
    final useCupertinoNavigation =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return ColoredBox(
      color: const Color(0xFFFBFAF7),
      child: Column(
        children: [
          if (useCupertinoNavigation)
            CupertinoNavigationBar(
              backgroundColor: const Color(0xF7FBFAF7),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFEAE7E0), width: 0.5),
              ),
              leading: widget.onMenu == null
                  ? null
                  : CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onMenu,
                      child: const Icon(CupertinoIcons.sidebar_left, size: 22),
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
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      SegmentedButton<_PomodoroMode>(
                        segments: const [
                          ButtonSegment(
                            value: _PomodoroMode.focus,
                            label: Text('专注 25 分钟'),
                          ),
                          ButtonSegment(
                            value: _PomodoroMode.shortBreak,
                            label: Text('休息 5 分钟'),
                          ),
                        ],
                        selected: {_mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) =>
                            _selectMode(selection.first),
                      ),
                      const SizedBox(height: 44),
                      SizedBox(
                        width: 250,
                        height: 250,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value:
                                  _remaining.inSeconds /
                                  _totalDuration.inSeconds,
                              strokeWidth: 9,
                              strokeCap: StrokeCap.round,
                              backgroundColor: const Color(0xFFEAE7E0),
                              color: const Color(0xFFE7B83F),
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatDuration(_remaining),
                                    key: const ValueKey('pomodoro-time'),
                                    style: const TextStyle(
                                      fontSize: 58,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -2,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _mode == _PomodoroMode.focus
                                        ? '保持专注'
                                        : '放松一下',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF85827A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 38),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _reset,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('重置'),
                          ),
                          const SizedBox(width: 14),
                          FilledButton.icon(
                            key: const ValueKey('pomodoro-toggle'),
                            onPressed: _toggleTimer,
                            icon: Icon(
                              _isRunning
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(_isRunning ? '暂停' : '开始'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      Text(
                        '今天已完成 $_completedFocusSessions 个专注时段',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF77736B),
                        ),
                      ),
                    ],
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
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({this.onMenu});

  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) => Container(
    height: 122,
    padding: const EdgeInsets.fromLTRB(34, 27, 32, 18),
    alignment: Alignment.bottomLeft,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFEAE7E0))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (onMenu != null) ...[
          IconButton(onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
          const SizedBox(width: 8),
        ],
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '专注工具',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF85827A),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 3),
            Text(
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
