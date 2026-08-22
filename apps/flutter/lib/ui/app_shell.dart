import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/task_controller.dart';
import 'sidebar.dart';
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
              final showEditor = widget.controller.selectedTask != null;
              if (compact) {
                return _CompactShell(
                  controller: widget.controller,
                  quickAddFocus: quickAddFocus,
                  searchFocus: searchFocus,
                );
              }
              return Center(
                child: Container(
                  width: constraints.maxWidth - 32,
                  height: constraints.maxHeight - 32,
                  constraints: const BoxConstraints(
                    maxWidth: 1440,
                    minHeight: 600,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFAF7),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x1A5A533F)),
                    boxShadow: const [
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
                        child: TaskListPane(
                          controller: widget.controller,
                          quickAddFocus: quickAddFocus,
                        ),
                      ),
                      if (showEditor)
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
    if (controller.selectedTask != null) {
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
    return Scaffold(
      drawer: Drawer(
        width: 270,
        child: SafeArea(
          child: Sidebar(controller: controller, searchFocus: searchFocus),
        ),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) => TaskListPane(
            controller: controller,
            quickAddFocus: quickAddFocus,
            onMenu: Scaffold.of(context).openDrawer,
          ),
        ),
      ),
    );
  }
}
