import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:forui/forui.dart';

import 'services/native_navigation.dart';
import 'services/theme_mode_storage.dart';
import 'services/theme_mode_storage_base.dart';
import 'state/task_controller.dart';
import 'ui/app_shell.dart';
import 'ui/design_system.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = TaskController();
  NativeNavigationBridge.attach(controller);
  runApp(
    QingxuApp(controller: controller, initialization: controller.initialize()),
  );
}

class QingxuApp extends StatefulWidget {
  const QingxuApp({
    required this.controller,
    required this.initialization,
    this.themeModeStorage,
    super.key,
  });

  final TaskController controller;
  final Future<void> initialization;
  final ThemeModeStorageBase? themeModeStorage;

  @override
  State<QingxuApp> createState() => _QingxuAppState();
}

class _QingxuAppState extends State<QingxuApp> {
  late final ThemeModeStorageBase _themeModeStorage;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _themeModeStorage = widget.themeModeStorage ?? ThemeModeStorage();
    unawaited(_restoreThemeMode());
  }

  Future<void> _restoreThemeMode() async {
    final stored = await _themeModeStorage.load();
    final mode = ThemeMode.values
        .where((value) => value.name == stored)
        .firstOrNull;
    if (mode != null && mounted) {
      setState(() => _themeMode = mode);
      NativeNavigationBridge.setThemeMode(mode);
    }
  }

  void _setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    NativeNavigationBridge.setThemeMode(mode);
    unawaited(_themeModeStorage.save(mode.name).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final touch = const <TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    }.contains(defaultTargetPlatform);
    return MaterialApp(
      title: '清序',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        ...FLocalizations.localizationsDelegates,
      ],
      theme: _buildTheme(Brightness.light, touch),
      darkTheme: _buildTheme(Brightness.dark, touch),
      themeMode: _themeMode,
      themeAnimationDuration: QingxuMotion.emphasized,
      themeAnimationCurve: QingxuMotion.curve,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final foruiTheme = dark
            ? (touch ? FTheme.neutral.dark.touch : FTheme.neutral.dark.desktop)
            : (touch
                  ? FTheme.neutral.light.touch
                  : FTheme.neutral.light.desktop);
        return FTheme(
          data: foruiTheme,
          child: FToaster(child: FTooltipGroup(child: child!)),
        );
      },
      home: FutureBuilder<void>(
        future: widget.initialization,
        builder: (context, snapshot) => AnimatedSwitcher(
          duration: QingxuMotion.standard,
          switchInCurve: QingxuMotion.curve,
          child: snapshot.connectionState == ConnectionState.done
              ? snapshot.hasError
                    ? _StartupError(error: snapshot.error)
                    : AppShell(
                        key: const ValueKey('app-shell'),
                        controller: widget.controller,
                        themeMode: _themeMode,
                        onThemeModeChanged: _setThemeMode,
                      )
              : const _StartupView(key: ValueKey('startup')),
        ),
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness, bool touch) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? QingxuPalette.dark : QingxuPalette.light;
  final (fontFamily, fontFallback) = _platformFonts();
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  final textTheme = base.textTheme.apply(
    bodyColor: palette.ink,
    displayColor: palette.ink,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
  );
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
        surface: palette.surface,
      ).copyWith(
        primary: palette.accent,
        secondary: palette.success,
        primaryContainer: palette.accentSoft,
        onPrimaryContainer: palette.accentStrong,
        surfaceContainer: palette.surface,
        surfaceContainerHigh: palette.surfaceRaised,
        onSurface: palette.ink,
        outline: palette.border,
        error: palette.danger,
      );
  return base.copyWith(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.canvas,
    canvasColor: palette.canvas,
    cardColor: palette.surface,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    dividerColor: palette.border,
    extensions: [palette],
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: touch
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: palette.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.accent, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accentStrong,
        foregroundColor: Colors.white,
        disabledBackgroundColor: palette.border,
        disabledForegroundColor: palette.faint,
        elevation: 0,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accentStrong,
        minimumSize: const Size(0, 46),
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.muted,
        highlightColor: palette.accentSoft,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : palette.border,
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.canvas,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? palette.accentStrong
              : palette.muted,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
    ),
  );
}

(String?, List<String>?) _platformFonts() {
  if (kIsWeb) return (null, null);
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => (
      'Segoe UI Variable',
      const ['Microsoft YaHei UI', 'Microsoft YaHei'],
    ),
    TargetPlatform.iOS ||
    TargetPlatform.macOS => ('.AppleSystemUIFont', const ['PingFang SC']),
    _ => (null, const ['Noto Sans CJK SC', 'Noto Sans SC']),
  };
}

class _StartupView extends StatelessWidget {
  const _StartupView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
              child: const SizedBox(
                width: 54,
                height: 54,
                child: Icon(Icons.check_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '清序',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: palette.danger,
                size: 38,
              ),
              const SizedBox(height: 14),
              const Text(
                '本地数据加载失败',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
