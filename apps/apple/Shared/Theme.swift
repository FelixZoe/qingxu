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
  /// 参考 FlowTime 的系统层级，收敛为一套低饱和冷白、深墨和单一蓝色强调。
  static let background = Color.adaptive(
    lightHex: 0xFAFAFA,
    darkHex: 0x121214
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xF2F2F7,
    darkHex: 0x18181B
  )
  static let surface = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x1E1E22
  )
  static let elevatedSurface = Color.adaptive(
    lightHex: 0xF7F7F9,
    darkHex: 0x2A2A2E
  )
  static let accent = Color.adaptive(
    lightHex: 0x3478F6,
    darkHex: 0x6D9EFF
  )
  static let onAccent = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x0B1324
  )
  static let selected = Color.adaptive(
    lightHex: 0xE9EFFD,
    darkHex: 0x26324B
  )
  static let ink = Color.adaptive(
    lightHex: 0x1C1C1E,
    darkHex: 0xF0F0F5
  )
  static let quiet = Color.adaptive(
    lightHex: 0x73737A,
    darkHex: 0x98989D
  )
  static let faint = Color.adaptive(
    lightHex: 0xA8A8AE,
    darkHex: 0x6C6C72
  )
  static let separator = Color.adaptive(
    lightHex: 0xE5E5EA,
    darkHex: 0x3A3A3E
  )
  static let success = Color.adaptive(
    lightHex: 0x2E7D64,
    darkHex: 0x65BFA1
  )
  static let warning = Color.adaptive(
    lightHex: 0x7A6640,
    darkHex: 0xC9AE72
  )
  static let danger = Color.adaptive(
    lightHex: 0xA3484F,
    darkHex: 0xD9898F
  )
  static let scrim = Color.adaptive(
    lightHex: 0x161925,
    darkHex: 0x000000
  )

  static let canvasGradient = LinearGradient(
    colors: [background, background],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let actionGradient = LinearGradient(
    colors: [accent, accent.opacity(0.90)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}

enum QingxuType {
  static let screenTitle = Font.system(size: 34, weight: .bold)
  static let sectionTitle = Font.system(size: 20, weight: .semibold)
  static let rowTitle = Font.system(size: 18, weight: .medium)
  static let rowTitleCompleted = Font.system(size: 18, weight: .regular)
  static let body = Font.system(size: 16, weight: .regular)
  static let metadata = Font.system(size: 13, weight: .regular)
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
      .background(QingxuPalette.canvasGradient.ignoresSafeArea())
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
