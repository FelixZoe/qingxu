import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/task_controller.dart';

/// Keeps the native iOS tab selection and Flutter's task view in sync.
///
/// The channel is intentionally inactive on every other platform so Windows
/// and Web continue to use the Flutter navigation shell unchanged.
final class NativeNavigationBridge {
  NativeNavigationBridge._(this._controller);

  static const _channel = MethodChannel('one.darker.qingxu/navigation');
  static const _nativeTabs = <String>{'inbox', 'today', 'pomodoro', 'settings'};

  final TaskController _controller;
  String? _lastSyncedView;

  static void attach(TaskController controller) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    final bridge = NativeNavigationBridge._(controller);
    _channel.setMethodCallHandler(bridge._handleMethodCall);
    controller.addListener(bridge._syncNativeSelection);
    bridge._syncNativeSelection();
  }

  static void setThemeMode(ThemeMode mode) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    unawaited(
      _channel
          .invokeMethod<void>('setThemeMode', mode.name)
          .catchError((Object _) {}),
    );
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'selectTab') {
      throw MissingPluginException('Unknown navigation method: ${call.method}');
    }

    final view = call.arguments;
    if (view is! String || !_nativeTabs.contains(view)) {
      throw PlatformException(
        code: 'invalid_tab',
        message: 'Unsupported native tab: $view',
      );
    }

    _lastSyncedView = view;
    if (_controller.activeView != view || _controller.search.isNotEmpty) {
      _controller.selectView(view);
    }
  }

  void _syncNativeSelection() {
    final view = _controller.activeView;
    if (!_nativeTabs.contains(view) || view == _lastSyncedView) return;

    _lastSyncedView = view;
    unawaited(_channel.invokeMethod<void>('setSelectedTab', view));
  }
}
