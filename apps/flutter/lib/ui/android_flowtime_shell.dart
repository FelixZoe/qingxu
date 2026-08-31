import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task_item.dart';
import '../services/personal_hub_store.dart';
import '../state/task_controller.dart';
import 'android_ai_sheet.dart';
import 'android_rss_page.dart';
import 'android_schedule_page.dart';
import 'android_update_sheet.dart';
import 'design_system.dart';
import 'pomodoro_page.dart';
import 'sync_settings_page.dart';
import 'task_editor.dart';

/// Android presentation adapted from the user's FlowTime project.
///
/// Qingxu keeps its own controller, persistence, sync and timer model. The
/// visual shell, breathing rhythm, glass navigation and task cards follow the
/// FlowTime Android implementation so the two apps feel deliberately related.
class AndroidFlowtimeShell extends StatefulWidget {
  const AndroidFlowtimeShell({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final TaskController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AndroidFlowtimeShell> createState() => _AndroidFlowtimeShellState();
}

class _AndroidFlowtimeShellState extends State<AndroidFlowtimeShell> {
  final _personalHub = PersonalHubStore();
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _personalHub.initialize(syncSettings: widget.controller.syncSettings);
  }

  @override
  void dispose() {
    _personalHub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final brightness = Theme.of(context).brightness;
        final palette = brightness == Brightness.dark
            ? _FlowtimeAndroidColors.darkPalette
            : _FlowtimeAndroidColors.lightPalette;
        final theme = _flowtimeTheme(Theme.of(context), palette);
        return Theme(
          data: theme,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: _buildContent(palette),
          ),
        );
      },
    );
  }

  Widget _buildContent(QingxuPalette palette) {
    if (widget.controller.selectedTask != null &&
        _pageIndex(widget.controller) == 0) {
      return Scaffold(
        backgroundColor: palette.canvas,
        body: SafeArea(
          bottom: false,
          child: TaskEditor(
            key: ValueKey(widget.controller.selectedTask!.id),
            controller: widget.controller,
            task: widget.controller.selectedTask!,
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        final messenger = ScaffoldMessenger.of(context);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text('再按一次退出应用'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            ),
          );
      },
      child: Scaffold(
        backgroundColor: palette.canvas,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _pageIndex(widget.controller),
            children: [
              AndroidSchedulePage(
                controller: widget.controller,
                store: _personalHub,
                onOpenAI: () => showAndroidAISheet(
                  context,
                  store: _personalHub,
                  controller: widget.controller,
                ),
              ),
              PomodoroPage(controller: widget.controller),
              AndroidRSSPage(
                store: _personalHub,
                controller: widget.controller,
              ),
              SyncSettingsPage(
                controller: widget.controller,
                embedded: true,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
                onAISettings: () => showAndroidAISettingsSheet(
                  context,
                  store: _personalHub,
                  controller: widget.controller,
                ),
                aiDetail: _personalHub.aiSettings.provider.label,
                onWeatherSettings: () => showAndroidWeatherSettingsSheet(
                  context,
                  store: _personalHub,
                ),
                weatherDetail: _personalHub.weather == null
                    ? '每日一句与天气'
                    : '${_personalHub.weather!.city} ${_personalHub.weather!.temperature}°',
                onCheckUpdates: () => showAndroidUpdateSheet(context),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _FlowtimeNavigationBar(
          activeView: widget.controller.activeView,
          onSelected: widget.controller.selectView,
        ),
      ),
    );
  }
}

class _FlowtimeTaskPage extends StatefulWidget {
  const _FlowtimeTaskPage({
    required this.controller,
    required this.quickAddFocus,
  });

  final TaskController controller;
  final FocusNode quickAddFocus;

  @override
  State<_FlowtimeTaskPage> createState() => _FlowtimeTaskPageState();
}

class _FlowtimeTaskPageState extends State<_FlowtimeTaskPage> {
  bool _adding = false;

  Future<void> _openQuickAdd() async {
    if (_adding) return;
    _adding = true;
    try {
      final title = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (_) => const _FlowtimeQuickAddSheet(),
      );
      if (!mounted || title == null || title.trim().isEmpty) return;
      final task = widget.controller.addTask(title);
      if (task == null) return;
      final destination = widget.controller.activeView == 'today'
          ? '今天'
          : '收集箱';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已添加到$destination'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: '编辑',
              onPressed: () => widget.controller.selectTask(task.id),
            ),
          ),
        );
    } finally {
      _adding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final tasks = widget.controller.visibleTasks;
    final title = widget.controller.activeView == 'today' ? '今天' : '收集箱';
    final subtitle = widget.controller.activeView == 'today'
        ? '安排今天，留出真正专注的时间'
        : '先收下来，再决定什么时候做';

    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        children: [
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 32,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _FlowtimeTaskCount(count: tasks.length),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              if (tasks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FlowtimeEmptyState(view: widget.controller.activeView),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 126),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: EdgeInsets.only(
                          bottom: index == tasks.length - 1 ? 0 : 14,
                        ),
                        child: _FlowtimeTaskCard(
                          controller: widget.controller,
                          task: tasks[index],
                        ),
                      ),
                      childCount: tasks.length,
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 22,
            child: Focus(
              focusNode: widget.quickAddFocus,
              onFocusChange: (focused) {
                if (!focused) return;
                widget.quickAddFocus.unfocus();
                _openQuickAdd();
              },
              child: FloatingActionButton(
                key: const ValueKey('android-flowtime-quick-add'),
                onPressed: _openQuickAdd,
                elevation: 0,
                highlightElevation: 0,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowtimeTaskCard extends StatelessWidget {
  const _FlowtimeTaskCard({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final completed = task.status == TaskStatus.completed;
    return Dismissible(
      key: ValueKey('android-flowtime-task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.danger,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
        ),
      ),
      onDismissed: (_) {
        controller.deleteTask(task);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('任务已删除'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () => controller.restoreTask(task),
              ),
            ),
          );
      },
      child: Material(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => controller.selectTask(task.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: completed ? '标记为未完成' : '标记为已完成',
                  child: InkResponse(
                    onTap: () => controller.toggleTask(task),
                    radius: 24,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: completed ? palette.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: completed ? palette.accent : palette.faint,
                          width: 1.7,
                        ),
                      ),
                      child: completed
                          ? const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: completed ? palette.muted : palette.ink,
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                      if (task.notes.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          task.notes.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: palette.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowtimeQuickAddSheet extends StatefulWidget {
  const _FlowtimeQuickAddSheet();

  @override
  State<_FlowtimeQuickAddSheet> createState() =>
      _FlowtimeQuickAddSheetState();
}

class _FlowtimeQuickAddSheetState extends State<_FlowtimeQuickAddSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, keyboard + 12),
      child: Material(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '新增任务',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(hintText: '要做什么？'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => FilledButton(
                    onPressed: value.text.trim().isEmpty ? null : _submit,
                    child: const Text('添加任务'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowtimeTaskCount extends StatelessWidget {
  const _FlowtimeTaskCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$count 项',
        style: TextStyle(
          color: palette.accentStrong,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FlowtimeEmptyState extends StatelessWidget {
  const _FlowtimeEmptyState({required this.view});

  final String view;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              view == 'today'
                  ? Icons.wb_sunny_outlined
                  : Icons.inbox_outlined,
              size: 34,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            view == 'today' ? '今天没有任务' : '收集箱是空的',
            style: TextStyle(
              color: palette.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            view == 'today' ? '留一点时间给自己' : '想到什么，就先记下来',
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _FlowtimeNavigationBar extends StatelessWidget {
  const _FlowtimeNavigationBar({
    required this.activeView,
    required this.onSelected,
  });

  final String activeView;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final content = Container(
      height: 70,
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1E1E22).withValues(alpha: 0.68)
            : const Color(0xFFF9F9F9).withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.58),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.10),
            blurRadius: 30,
            offset: const Offset(0, 8),
            spreadRadius: -5,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            _FlowtimeNavItem(
              icon: Icons.event_note_outlined,
              activeIcon: Icons.event_note_rounded,
              label: '日程',
              active: activeView == 'today',
              onTap: () => onSelected('today'),
            ),
            _FlowtimeNavItem(
              icon: Icons.timer_outlined,
              activeIcon: Icons.timer_rounded,
              label: '番茄钟',
              active: activeView == 'pomodoro',
              onTap: () => onSelected('pomodoro'),
            ),
            _FlowtimeNavItem(
              icon: Icons.rss_feed_outlined,
              activeIcon: Icons.rss_feed_rounded,
              label: 'RSS',
              active: activeView == 'rss',
              onTap: () => onSelected('rss'),
            ),
            _FlowtimeNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: '设置',
              active: activeView == 'settings',
              onTap: () => onSelected('settings'),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.paddingOf(context).bottom + 14,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: content,
        ),
      ),
    );
  }
}

class _FlowtimeNavItem extends StatelessWidget {
  const _FlowtimeNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? palette.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  active ? activeIcon : icon,
                  size: 21,
                  color: active ? palette.accent : palette.muted,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: active ? palette.accent : palette.muted,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ThemeData _flowtimeTheme(ThemeData base, QingxuPalette palette) {
  final dark = base.brightness == Brightness.dark;
  return base.copyWith(
    scaffoldBackgroundColor: palette.canvas,
    canvasColor: palette.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: palette.accent,
      onPrimary: Colors.white,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: palette.accentStrong,
      surface: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceRaised,
      onSurface: palette.ink,
      outline: palette.border,
      error: palette.danger,
    ),
    cardTheme: CardThemeData(
      color: palette.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: palette.ink,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: Colors.white,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark
          ? _FlowtimeAndroidColors.darkSurfaceAlt
          : _FlowtimeAndroidColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 0.5,
      space: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(16),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.accent, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [palette],
  );
}

abstract final class _FlowtimeAndroidColors {
  static const primary = Color(0xFF007AFF);
  static const background = Color(0xFFFAFAFA);
  static const surface = Color(0xFFF2F2F7);
  static const card = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE5E5EA);
  static const textPrimary = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF8E8E93);
  static const textTertiary = Color(0xFFC7C7CC);
  static const darkBackground = Color(0xFF121214);
  static const darkSurface = Color(0xFF1E1E22);
  static const darkSurfaceAlt = Color(0xFF2A2A2E);
  static const darkDivider = Color(0xFF3A3A3E);
  static const darkTextPrimary = Color(0xFFF0F0F5);
  static const darkTextSecondary = Color(0xFF98989D);
  static const darkTextTertiary = Color(0xFF6C6C72);

  static const lightPalette = QingxuPalette(
    accent: primary,
    accentStrong: Color(0xFF005FCC),
    accentSoft: Color(0x1F007AFF),
    canvas: background,
    surface: surface,
    surfaceRaised: card,
    sidebar: surface,
    ink: textPrimary,
    muted: textSecondary,
    faint: textTertiary,
    border: divider,
    success: Color(0xFF34C759),
    danger: Color(0xFFFF3B30),
    info: primary,
  );

  static const darkPalette = QingxuPalette(
    accent: Color(0xFF0A84FF),
    accentStrong: Color(0xFF64B5FF),
    accentSoft: Color(0x2E0A84FF),
    canvas: darkBackground,
    surface: darkSurface,
    surfaceRaised: darkSurface,
    sidebar: darkSurface,
    ink: darkTextPrimary,
    muted: darkTextSecondary,
    faint: darkTextTertiary,
    border: darkDivider,
    success: Color(0xFF30D158),
    danger: Color(0xFFFF453A),
    info: Color(0xFF0A84FF),
  );
}

int _pageIndex(TaskController controller) => switch (controller.activeView) {
  'pomodoro' => 1,
  'rss' => 2,
  'settings' => 3,
  _ => 0,
};
