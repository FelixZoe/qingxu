import 'package:flutter/material.dart';

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

  // Porcelain ivory with a restrained mineral blue. Warmth is kept subtle so
  // large areas stay clean instead of reading as yellow or aged paper.
  static const light = QingxuPalette(
    accent: Color(0xFF5B7D92),
    accentStrong: Color(0xFF365D74),
    accentSoft: Color(0xFFE3ECF0),
    canvas: Color(0xFFF5F5F1),
    surface: Color(0xFFFCFCF9),
    surfaceRaised: Color(0xFFFFFFFF),
    sidebar: Color(0xFFEDF1F2),
    ink: Color(0xFF18262D),
    muted: Color(0xFF68767C),
    faint: Color(0xFF96A0A3),
    border: Color(0xFFE0E5E4),
    success: Color(0xFF547B67),
    danger: Color(0xFFB55F59),
    info: Color(0xFF5B7D92),
  );

  // Neutral graphite surfaces with forest green reserved for interaction and
  // progress. This avoids the previous all-over green cast in dark mode.
  static const dark = QingxuPalette(
    accent: Color(0xFF73A385),
    accentStrong: Color(0xFF9AC3A7),
    accentSoft: Color(0xFF203029),
    canvas: Color(0xFF0E100F),
    surface: Color(0xFF151816),
    surfaceRaised: Color(0xFF1B1F1C),
    sidebar: Color(0xFF121614),
    ink: Color(0xFFEEF1EF),
    muted: Color(0xFFA4ACA7),
    faint: Color(0xFF727A75),
    border: Color(0xFF2B312D),
    success: Color(0xFF73A385),
    danger: Color(0xFFD27B72),
    info: Color(0xFF7DA4B6),
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
  static const desktopGutter = 40.0;
  static const contentMaxWidth = 720.0;
  static const sectionRadius = 20.0;

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
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 18),
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
                      fontSize: constraints.maxWidth < 700 ? 30 : 34,
                      height: 1.08,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 13,
                      height: 1.3,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: palette.border.withValues(alpha: dark ? 0.9 : 0.75),
        ),
        boxShadow: dark
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
