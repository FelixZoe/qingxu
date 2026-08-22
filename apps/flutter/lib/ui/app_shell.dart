import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/task_controller.dart';
import 'design_system.dart';
import 'pomodoro_page.dart';
import 'sidebar.dart';
import 'sync_settings_page.dart';
import 'task_editor.dart';
import 'task_list.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final TaskController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final quickAddFocus = FocusNode();
  final searchFocus = FocusNode();

  @override
  void dispose() {
    quickAddFocus.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            quickAddFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            quickAddFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final palette = QingxuPalette.of(context);
              final compact = constraints.maxWidth < 760;
              final useNativeIosTabs =
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
              final useAndroidTabs =
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
              final useFullBleedDesktop =
                  !kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.macOS);
              final showEditor = widget.controller.selectedTask != null;
              if (compact || useNativeIosTabs || useAndroidTabs) {
                return _CompactShell(
                  controller: widget.controller,
                  quickAddFocus: quickAddFocus,
                  searchFocus: searchFocus,
                  themeMode: widget.themeMode,
                  onThemeModeChanged: widget.onThemeModeChanged,
                );
              }
              return Center(
                child: Container(
                  width: useFullBleedDesktop
                      ? constraints.maxWidth
                      : constraints.maxWidth - 32,
                  height: useFullBleedDesktop
                      ? constraints.maxHeight
                      : constraints.maxHeight - 32,
                  constraints: useFullBleedDesktop
                      ? const BoxConstraints()
                      : const BoxConstraints(maxWidth: 1440, minHeight: 600),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: useFullBleedDesktop
                        ? BorderRadius.zero
                        : BorderRadius.circular(18),
                    border: useFullBleedDesktop
                        ? null
                        : Border.all(color: palette.border),
                    boxShadow: useFullBleedDesktop
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x14504A38),
                              blurRadius: 55,
                              offset: Offset(0, 18),
                            ),
                          ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 252,
                        child: Sidebar(
                          controller: widget.controller,
                          searchFocus: searchFocus,
                        ),
                      ),
                      Expanded(
                        child: _Workspace(
                          controller: widget.controller,
                          quickAddFocus: quickAddFocus,
                          themeMode: widget.themeMode,
                          onThemeModeChanged: widget.onThemeModeChanged,
                        ),
                      ),
                      if (showEditor && _viewIndex(widget.controller) == 0)
                        SizedBox(
                          width: constraints.maxWidth < 1080 ? 300 : 350,
                          child: TaskEditor(
                            key: ValueKey(widget.controller.selectedTask!.id),
                            controller: widget.controller,
                            task: widget.controller.selectedTask!,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.controller,
    required this.quickAddFocus,
    required this.searchFocus,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final TaskController controller;
  final FocusNode quickAddFocus;
  final FocusNode searchFocus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    if (controller.selectedTask != null && _viewIndex(controller) == 0) {
      return Scaffold(
        body: SafeArea(
          child: TaskEditor(
            key: ValueKey(controller.selectedTask!.id),
            controller: controller,
            task: controller.selectedTask!,
          ),
        ),
      );
    }
    final useNativeIosTabs =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final useAndroidTabs =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final useMobileTabs = useNativeIosTabs || useAndroidTabs;
    return Builder(
      builder: (context) => Scaffold(
        drawer: useMobileTabs
            ? null
            : Drawer(
                width: 270,
                child: SafeArea(
                  child: Sidebar(
                    controller: controller,
                    searchFocus: searchFocus,
                  ),
                ),
              ),
        body: SafeArea(
          child: Builder(
            builder: (context) => _Workspace(
              controller: controller,
              quickAddFocus: quickAddFocus,
              themeMode: themeMode,
              onThemeModeChanged: onThemeModeChanged,
              onMenu: useMobileTabs ? null : Scaffold.of(context).openDrawer,
            ),
          ),
        ),
        bottomNavigationBar: useAndroidTabs
            ? NavigationBar(
                selectedIndex: _navigationIndex(controller),
                onDestinationSelected: (index) =>
                    controller.selectView(_navigationViews[index]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.inbox_outlined),
                    selectedIcon: Icon(Icons.inbox_rounded),
                    label: '收集箱',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.light_mode_outlined),
                    selectedIcon: Icon(Icons.light_mode_rounded),
                    label: '今天',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    selectedIcon: Icon(Icons.timer_rounded),
                    label: '番茄钟',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '设置',
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.controller,
    required this.quickAddFocus,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.onMenu,
  });

  final TaskController controller;
  final FocusNode quickAddFocus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final selected = _viewIndex(controller);
    final pages = <Widget>[
      TaskListPane(
        controller: controller,
        quickAddFocus: quickAddFocus,
        onMenu: onMenu,
      ),
      PomodoroPage(controller: controller, onMenu: onMenu),
      SyncSettingsPage(
        controller: controller,
        embedded: true,
        onMenu: onMenu,
        themeMode: themeMode,
        onThemeModeChanged: onThemeModeChanged,
      ),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < pages.length; index++)
          AnimatedOpacity(
            opacity: index == selected ? 1 : 0,
            duration: QingxuMotion.standard,
            curve: QingxuMotion.curve,
            child: IgnorePointer(
              ignoring: index != selected,
              child: TickerMode(
                enabled: index == selected,
                child: pages[index],
              ),
            ),
          ),
      ],
    );
  }
}

int _viewIndex(TaskController controller) => switch (controller.activeView) {
  'pomodoro' => 1,
  'settings' => 2,
  _ => 0,
};

const _navigationViews = ['inbox', 'today', 'pomodoro', 'settings'];

int _navigationIndex(TaskController controller) {
  final index = _navigationViews.indexOf(controller.activeView);
  return index < 0 ? 1 : index;
}
