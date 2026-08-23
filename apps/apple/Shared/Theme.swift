import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "跟随系统"
    case .light: "米白蓝"
    case .dark: "黑绿"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum QingxuPalette {
  static let background = Color.adaptive(
    light: (0.957, 0.945, 0.918),
    dark: (0.078, 0.078, 0.071)
  )
  static let surface = Color.adaptive(
    light: (0.984, 0.976, 0.957),
    dark: (0.110, 0.110, 0.098)
  )
  static let accent = Color.adaptive(
    light: (0.718, 0.400, 0.302),
    dark: (0.784, 0.529, 0.380)
  )
  static let ink = Color.adaptive(
    light: (0.133, 0.133, 0.122),
    dark: (0.949, 0.933, 0.902)
  )
  static let quiet = Color.adaptive(
    light: (0.435, 0.424, 0.396),
    dark: (0.655, 0.631, 0.596)
  )
  static let separator = Color.adaptive(
    light: (0.871, 0.847, 0.804),
    dark: (0.204, 0.196, 0.176)
  )
}

extension Color {
  static func adaptive(
    light: (Double, Double, Double),
    dark: (Double, Double, Double)
  ) -> Color {
    #if os(iOS)
    Color(UIColor { traits in
      let value = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
    })
    #else
    Color(NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      let value = isDark ? dark : light
      return NSColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
    })
    #endif
  }
}

private struct QingxuScreenBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(QingxuPalette.background.ignoresSafeArea())
      .tint(QingxuPalette.accent)
  }
}

extension View {
  func qingxuScreen() -> some View { modifier(QingxuScreenBackground()) }

  @ViewBuilder
  func qingxuFloatingSurface() -> some View {
    #if os(iOS)
    if #available(iOS 26.0, *) {
      self.glassEffect(.regular.interactive(), in: .circle)
    } else {
      self.background(.ultraThinMaterial, in: Circle())
    }
    #else
    self.background(.ultraThinMaterial, in: Circle())
    #endif
  }
}
