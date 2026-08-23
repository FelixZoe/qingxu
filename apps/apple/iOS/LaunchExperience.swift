import SwiftUI

struct QingxuLaunchExperience: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let onFinished: () -> Void

  @State private var hasStarted = false
  @State private var markVisible = false
  @State private var lineVisible = false
  @State private var leaving = false
  @State private var overlayOpacity = 1.0

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        QingxuPalette.background

        VStack(spacing: 22) {
          Image("QingxuLaunchMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 124, height: 124)
            .foregroundStyle(QingxuPalette.ink)

          Capsule()
            .fill(QingxuPalette.separator)
            .frame(width: 36, height: 1)
            .scaleEffect(x: lineVisible ? 1 : 0, anchor: .center)
            .opacity(lineVisible ? 1 : 0)
        }
        .scaleEffect(markVisible ? 1 : 0.985)
        .opacity(markVisible ? 1 : 0)
        .blur(radius: markVisible ? 0 : 5)
        .offset(y: -proxy.size.height * 0.055 + (leaving ? -10 : 0))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .opacity(overlayOpacity)
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .task { await playOnce() }
  }

  @MainActor
  private func playOnce() async {
    guard !hasStarted else { return }
    hasStarted = true

    if reduceMotion {
      markVisible = true
      lineVisible = true
      try? await Task.sleep(nanoseconds: 140_000_000)
      withAnimation(.easeOut(duration: 0.18)) { overlayOpacity = 0 }
      try? await Task.sleep(nanoseconds: 190_000_000)
      onFinished()
      return
    }

    try? await Task.sleep(nanoseconds: 70_000_000)
    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.48)) {
      markVisible = true
    }
    try? await Task.sleep(nanoseconds: 350_000_000)

    withAnimation(.easeOut(duration: 0.3)) {
      lineVisible = true
    }
    try? await Task.sleep(nanoseconds: 360_000_000)

    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.42)) {
      leaving = true
      overlayOpacity = 0
    }
    try? await Task.sleep(nanoseconds: 430_000_000)
    onFinished()
  }
}
