import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get qingxuIsDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

@immutable
class QingxuPalette extends ThemeExtension<QingxuPalette> {
  const QingxuPalette({
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.sidebar,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.border,
    required this.success,
    required this.danger,
    required this.info,
  });

  // Cool porcelain and slate blue: quiet enough for long desktop sessions.
  static const light = QingxuPalette(
    accent: Color(0xFF5278A5),
    accentStrong: Color(0xFF315A89),
    accentSoft: Color(0xFFE2EAF3),
    canvas: Color(0xFFF4F6F8),
    surface: Color(0xFFFAFBFC),
    surfaceRaised: Color(0xFFFFFFFF),
    sidebar: Color(0xFFEBEFF4),
    ink: Color(0xFF18222D),
    muted: Color(0xFF64717F),
    faint: Color(0xFF929DA8),
    border: Color(0xFFDCE2E8),
    success: Color(0xFF507866),
    danger: Color(0xFFB65359),
    info: Color(0xFF5278A5),
  );

  // Deep blue graphite with no green cast and no pure-black slabs.
  static const dark = QingxuPalette(
    accent: Color(0xFF87A9CF),
    accentStrong: Color(0xFFAEC7E2),
    accentSoft: Color(0xFF203249),
    canvas: Color(0xFF10151B),
    surface: Color(0xFF151B22),
    surfaceRaised: Color(0xFF1B232D),
    sidebar: Color(0xFF121922),
    ink: Color(0xFFEDF2F6),
    muted: Color(0xFF9AA7B4),
    faint: Color(0xFF687583),
    border: Color(0xFF293440),
    success: Color(0xFF80A993),
    danger: Color(0xFFD57D83),
    info: Color(0xFF87A9CF),
  );

  static QingxuPalette of(BuildContext context) =>
      Theme.of(context).extension<QingxuPalette>() ?? light;

  final Color accent;
  final Color accentStrong;
  final Color accentSoft;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
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
    Color? accentStrong,
    Color? accentSoft,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
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
    accentStrong: accentStrong ?? this.accentStrong,
    accentSoft: accentSoft ?? this.accentSoft,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
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
      accentStrong: mix(accentStrong, other.accentStrong),
      accentSoft: mix(accentSoft, other.accentSoft),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
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
  static const quick = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 220);
  static const emphasized = Duration(milliseconds: 360);
  static const curve = Curves.easeOutCubic;
}

abstract final class QingxuLayout {
  static const mobileGutter = 20.0;
  static const desktopGutter = 48.0;
  static const contentMaxWidth = 840.0;
  static const sectionRadius = 16.0;

  static double gutterFor(double width) =>
      width < 700 ? mobileGutter : desktopGutter;
}

class QingxuPageHeader extends StatelessWidget {
  const QingxuPageHeader({
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final palette = QingxuPalette.of(context);
      final gutter = QingxuLayout.gutterFor(constraints.maxWidth);
      final desktop = qingxuIsDesktop && constraints.maxWidth >= 760;
      final android =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          desktop ? 42 : (android ? 28 : 30),
          gutter,
          desktop ? 28 : (android ? 30 : 24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: desktop
                          ? 34
                          : (android
                                ? 32
                                : (constraints.maxWidth < 700 ? 34 : 40)),
                      height: 1.12,
                      fontWeight: android ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: android ? -0.8 : (desktop ? -0.7 : -1.1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: android ? 15 : 13,
                      height: android ? 1.35 : 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      );
    },
  );
}

class QingxuSurface extends StatelessWidget {
  const QingxuSurface({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = QingxuLayout.sectionRadius,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final android =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: android ? palette.surfaceRaised : palette.surface,
        borderRadius: BorderRadius.circular(android ? 20 : radius),
        border: android
            ? null
            : Border.all(
                color: palette.border.withValues(alpha: dark ? 0.9 : 0.75),
              ),
        boxShadow: dark || android
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A26343B),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
