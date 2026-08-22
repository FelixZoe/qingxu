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
    light: (0.969, 0.957, 0.925),
    dark: (0.020, 0.047, 0.037)
  )
  static let surface = Color.adaptive(
    light: (0.996, 0.992, 0.973),
    dark: (0.047, 0.094, 0.074)
  )
  static let accent = Color.adaptive(
    light: (0.275, 0.451, 0.588),
    dark: (0.365, 0.714, 0.529)
  )
  static let quiet = Color.adaptive(
    light: (0.412, 0.451, 0.471),
    dark: (0.615, 0.694, 0.647)
  )
  static let separator = Color.adaptive(
    light: (0.827, 0.816, 0.780),
    dark: (0.118, 0.204, 0.165)
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
