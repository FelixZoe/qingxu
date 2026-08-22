import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:forui/forui.dart';

import 'state/task_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = TaskController();
  await controller.initialize();
  runApp(QingxuApp(controller: controller));
}

class QingxuApp extends StatelessWidget {
  const QingxuApp({required this.controller, super.key});

  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE7B83F);
    final touch = const <TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    }.contains(defaultTargetPlatform);
    final foruiTheme = touch
        ? FTheme.neutral.light.touch
        : FTheme.neutral.light.desktop;
    final materialTheme = foruiTheme.toApproximateMaterialTheme();

    return MaterialApp(
      title: '清序',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        ...FLocalizations.localizationsDelegates,
      ],
      theme: materialTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: const Color(0xFFFBFAF7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0EFEA),
        splashFactory: NoSplash.splashFactory,
        visualDensity: VisualDensity.standard,
      ),
      builder: (context, child) => FTheme(
        data: foruiTheme,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: AppShell(controller: controller),
    );
  }
}
