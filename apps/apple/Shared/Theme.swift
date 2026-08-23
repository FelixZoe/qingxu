import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "跟随系统"
    case .light: "明亮"
    case .dark: "深色"
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
  /// 雾蓝石墨：冷瓷白与深蓝石墨组成的低刺激工作界面。
  static let background = Color.adaptive(
    lightHex: 0xF5F7FA,
    darkHex: 0x10141A
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xEDF1F5,
    darkHex: 0x161C24
  )
  static let surface = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x1C2430
  )
  static let accent = Color.adaptive(
    lightHex: 0x5278A5,
    darkHex: 0x86A9D1
  )
  static let selected = Color.adaptive(
    lightHex: 0xE1EAF4,
    darkHex: 0x21334A
  )
  static let ink = Color.adaptive(
    lightHex: 0x17212B,
    darkHex: 0xEDF2F7
  )
  static let quiet = Color.adaptive(
    lightHex: 0x667381,
    darkHex: 0x9DAAB8
  )
  static let separator = Color.adaptive(
    lightHex: 0xDDE3E9,
    darkHex: 0x293440
  )
  static let success = Color.adaptive(
    lightHex: 0x557967,
    darkHex: 0x83AA95
  )
  static let danger = Color.adaptive(
    lightHex: 0xB65359,
    darkHex: 0xD57D83
  )
}

extension Color {
  static func adaptive(
    lightHex: UInt32,
    darkHex: UInt32
  ) -> Color {
    #if os(iOS)
    Color(UIColor { traits in
      UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
    })
    #else
    Color(NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(hex: isDark ? darkHex : lightHex)
    })
    #endif
  }
}

#if os(iOS)
private extension UIColor {
  convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
#else
private extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
#endif

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
