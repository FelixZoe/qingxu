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

  // Editorial paper, charcoal ink, and a restrained terracotta accent.
  static const light = QingxuPalette(
    accent: Color(0xFFB7664D),
    accentStrong: Color(0xFF8B4331),
    accentSoft: Color(0xFFF0DED5),
    canvas: Color(0xFFF4F1EA),
    surface: Color(0xFFFBF9F4),
    surfaceRaised: Color(0xFFFFFFFF),
    sidebar: Color(0xFFECE7DD),
    ink: Color(0xFF22221F),
    muted: Color(0xFF6F6C65),
    faint: Color(0xFF9A958B),
    border: Color(0xFFDED8CD),
    success: Color(0xFF60796B),
    danger: Color(0xFFB4544D),
    info: Color(0xFF8A6B5A),
  );

  // Warm graphite keeps dark mode neutral; copper is reserved for action.
  static const dark = QingxuPalette(
    accent: Color(0xFFC88761),
    accentStrong: Color(0xFFE0A982),
    accentSoft: Color(0xFF3A2A22),
    canvas: Color(0xFF141412),
    surface: Color(0xFF1C1C19),
    surfaceRaised: Color(0xFF24231F),
    sidebar: Color(0xFF181816),
    ink: Color(0xFFF2EEE6),
    muted: Color(0xFFA7A198),
    faint: Color(0xFF77736C),
    border: Color(0xFF34322D),
    success: Color(0xFF7E9B88),
    danger: Color(0xFFD07B70),
    info: Color(0xFF9B8C7C),
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
        padding: EdgeInsets.fromLTRB(gutter, 30, gutter, 24),
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
                      fontSize: constraints.maxWidth < 700 ? 34 : 40,
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
