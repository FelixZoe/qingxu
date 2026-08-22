import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
    return MaterialApp(
      title: '清序',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: const Color(0xFFFBFAF7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0EFEA),
        fontFamilyFallback: const ['Segoe UI', 'PingFang SC', 'Microsoft YaHei'],
        splashFactory: NoSplash.splashFactory,
        visualDensity: VisualDensity.standard,
      ),
      home: AppShell(controller: controller),
    );
  }
}
