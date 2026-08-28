import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pomodoro_state.dart';

final class IOSSystemFeatures {
  IOSSystemFeatures._();

  static const _channel = MethodChannel('one.darker.qingxu/system-features');

  static void update({
    required PomodoroState pomodoro,
    required int todayTaskCount,
    required List<String> todayTaskTitles,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    unawaited(
      _channel
          .invokeMethod<void>('updateSnapshot', {
            'pomodoro': pomodoro.toJson(),
            'todayTaskCount': todayTaskCount,
            'todayTaskTitles': todayTaskTitles,
          })
          .catchError((Object _) {}),
    );
  }
}
