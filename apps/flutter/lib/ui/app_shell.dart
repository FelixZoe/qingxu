import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/task_controller.dart';
import 'pomodoro_page.dart';
import 'sidebar.dart';
import 'sync_settings_page.dart';
import 'task_editor.dart';
import 'task_list.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.controller, super.key});

  final TaskController controller;

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
              final compact = constraints.maxWidth < 760;
              final useNativeIosTabs =
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
              final useFullBleedWindows =
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
              final showEditor = widget.controller.selectedTask != null;
              if (compact || useNativeIosTabs) {
                return _CompactShell(
                  controller: widget.controller,
                  quickAddFocus: quickAddFocus,
                  searchFocus: searchFocus,
                );
              }
              return Center(
                child: Container(
                  width: useFullBleedWindows
                      ? constraints.maxWidth
                      : constraints.maxWidth - 32,
                  height: useFullBleedWindows
                      ? constraints.maxHeight
                      : constraints.maxHeight - 32,
                  constraints: useFullBleedWindows
                      ? const BoxConstraints()
                      : const BoxConstraints(maxWidth: 1440, minHeight: 600),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFAF7),
                    borderRadius: useFullBleedWindows
                        ? BorderRadius.zero
                        : BorderRadius.circular(18),
                    border: useFullBleedWindows
                        ? null
                        : Border.all(color: const Color(0x1A5A533F)),
                    boxShadow: useFullBleedWindows
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
  });

  final TaskController controller;
  final FocusNode quickAddFocus;
  final FocusNode searchFocus;

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
    return Builder(
      builder: (context) => Scaffold(
        drawer: useNativeIosTabs
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
              onMenu: useNativeIosTabs ? null : Scaffold.of(context).openDrawer,
            ),
          ),
        ),
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.controller,
    required this.quickAddFocus,
    this.onMenu,
  });

  final TaskController controller;
  final FocusNode quickAddFocus;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: _viewIndex(controller),
    children: [
      TaskListPane(
        controller: controller,
        quickAddFocus: quickAddFocus,
        onMenu: onMenu,
      ),
      PomodoroPage(onMenu: onMenu),
      SyncSettingsPage(controller: controller, embedded: true, onMenu: onMenu),
    ],
  );
}

int _viewIndex(TaskController controller) => switch (controller.activeView) {
  'pomodoro' => 1,
  'settings' => 2,
  _ => 0,
};
