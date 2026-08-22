import 'package:flutter/material.dart';

@immutable
class QingxuPalette extends ThemeExtension<QingxuPalette> {
  const QingxuPalette({
    required this.accent,
    required this.accentSoft,
    required this.canvas,
    required this.surface,
    required this.sidebar,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.border,
    required this.success,
    required this.danger,
    required this.info,
  });

  static const light = QingxuPalette(
    accent: Color(0xFF53758F),
    accentSoft: Color(0xFFDCE8EE),
    canvas: Color(0xFFF0EEE7),
    surface: Color(0xFFFAF8F2),
    sidebar: Color(0xFFE8ECEB),
    ink: Color(0xFF263238),
    muted: Color(0xFF68777D),
    faint: Color(0xFF98A2A4),
    border: Color(0xFFDCE1DF),
    success: Color(0xFF628A73),
    danger: Color(0xFFB45F57),
    info: Color(0xFF53758F),
  );

  static const dark = QingxuPalette(
    accent: Color(0xFF6EAE86),
    accentSoft: Color(0xFF1D3528),
    canvas: Color(0xFF0C100E),
    surface: Color(0xFF121714),
    sidebar: Color(0xFF171E1A),
    ink: Color(0xFFE8EEE9),
    muted: Color(0xFFA6B1AA),
    faint: Color(0xFF748078),
    border: Color(0xFF29342E),
    success: Color(0xFF6EAE86),
    danger: Color(0xFFD17A70),
    info: Color(0xFF78A3B8),
  );

  static QingxuPalette of(BuildContext context) =>
      Theme.of(context).extension<QingxuPalette>() ?? light;

  final Color accent;
  final Color accentSoft;
  final Color canvas;
  final Color surface;
  final Color sidebar;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color border;
  final Color success;
  final Color danger;
  final Color info;

  @override
  QingxuPalette copyWith({
    Color? accent,
    Color? accentSoft,
    Color? canvas,
    Color? surface,
    Color? sidebar,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? border,
    Color? success,
    Color? danger,
    Color? info,
  }) => QingxuPalette(
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    sidebar: sidebar ?? this.sidebar,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    border: border ?? this.border,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    info: info ?? this.info,
  );

  @override
  QingxuPalette lerp(covariant QingxuPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color first, Color second) => Color.lerp(first, second, t)!;
    return QingxuPalette(
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      sidebar: mix(sidebar, other.sidebar),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      faint: mix(faint, other.faint),
      border: mix(border, other.border),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
    );
  }
}

abstract final class QingxuMotion {
  static const quick = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 220);
  static const emphasized = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}
