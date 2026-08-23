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
import 'windows_widget_shell.dart';

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
    final useWindowsWidget =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
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
        child: useWindowsWidget
            ? WindowsWidgetShell(
                controller: widget.controller,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
              )
            : AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final palette = QingxuPalette.of(context);
                    final compact = constraints.maxWidth < 760;
                    final useNativeIosTabs =
                        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
                    final useAndroidTabs =
                        !kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android;
                    if (compact || useNativeIosTabs || useAndroidTabs) {
                      return _CompactShell(
                        controller: widget.controller,
                        quickAddFocus: quickAddFocus,
                        searchFocus: searchFocus,
                        themeMode: widget.themeMode,
                        onThemeModeChanged: widget.onThemeModeChanged,
                      );
                    }
                    return _DesktopShell(
                      controller: widget.controller,
                      quickAddFocus: quickAddFocus,
                      searchFocus: searchFocus,
                      themeMode: widget.themeMode,
                      onThemeModeChanged: widget.onThemeModeChanged,
                      palette: palette,
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.controller,
    required this.quickAddFocus,
    required this.searchFocus,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.palette,
  });

  final TaskController controller;
  final FocusNode quickAddFocus;
  final FocusNode searchFocus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final QingxuPalette palette;

  @override
  Widget build(BuildContext context) {
    final task = controller.selectedTask;
    final showEditor = task != null && _viewIndex(controller) == 0;
    return ColoredBox(
      color: palette.surface,
      child: Row(
        children: [
          SizedBox(
            width: 264,
            child: Sidebar(controller: controller, searchFocus: searchFocus),
          ),
          VerticalDivider(width: 1, thickness: 1, color: palette.border),
          Expanded(
            child: _Workspace(
              controller: controller,
              quickAddFocus: quickAddFocus,
              themeMode: themeMode,
              onThemeModeChanged: onThemeModeChanged,
            ),
          ),
          AnimatedContainer(
            duration: QingxuMotion.standard,
            curve: QingxuMotion.curve,
            width: showEditor ? 382 : 0,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              border: showEditor
                  ? Border(left: BorderSide(color: palette.border))
                  : null,
            ),
            child: showEditor
                ? SizedBox(
                    width: 382,
                    child: TaskEditor(
                      key: ValueKey(task.id),
                      controller: controller,
                      task: task,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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
        backgroundColor: QingxuPalette.of(context).canvas,
        body: SafeArea(
          bottom: false,
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
    final useCompactWindowsTabs =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final useBottomTabs =
        useNativeIosTabs || useAndroidTabs || useCompactWindowsTabs;
    return Builder(
      builder: (context) => Scaffold(
        backgroundColor: QingxuPalette.of(context).canvas,
        drawer: useBottomTabs
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
          bottom: false,
          child: Builder(
            builder: (context) => _Workspace(
              controller: controller,
              quickAddFocus: quickAddFocus,
              themeMode: themeMode,
              onThemeModeChanged: onThemeModeChanged,
              onMenu: useBottomTabs ? null : Scaffold.of(context).openDrawer,
            ),
          ),
        ),
        bottomNavigationBar: (useAndroidTabs || useCompactWindowsTabs)
            ? NavigationBar(
                height: 72,
                elevation: 0,
                backgroundColor: QingxuPalette.of(context).canvas,
                surfaceTintColor: Colors.transparent,
                indicatorColor: QingxuPalette.of(context).accentSoft,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
