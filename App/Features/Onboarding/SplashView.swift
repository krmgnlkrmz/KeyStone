import BalanceCore
import SwiftUI

/// Splash: structure art, wordmark, a thin loader. Stays while consent info is gathered.
struct SplashView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let waitingForConsent: Bool
    @State private var slide = false

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 40) {
                if let level = app.catalog.curated.dropFirst(4).first {
                    SilhouetteView(silhouette: app.silhouette(for: level), color: Palette.text3, keyColor: Palette.accent)
                        .frame(width: 240, height: 304)
                } else {
                    KeystoneGlyph().fill(Palette.accent).frame(width: 80, height: 80).shadow(color: Palette.accent.opacity(0.6), radius: 14)
                }
                VStack(spacing: 10) {
                    Text("app.name").scaledFont(40, weight: .bold, relativeTo: .largeTitle).tracking(-0.6)
                    Text("splash.tagline").scaledFont(11, design: .monospaced, relativeTo: .caption2).tracking(3).foregroundStyle(Palette.text3)
                }
            }
            .padding(.bottom, 30)
            VStack(spacing: 14) {
                Spacer()
                Capsule().fill(Palette.line).frame(width: 88, height: 2)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Palette.accent).frame(width: 34, height: 2)
                            .offset(x: reduceMotion ? 27 : (slide ? 88 : -34))
                    }
                    .clipShape(Capsule())
                if waitingForConsent {
                    Text("consent.waiting").font(.footnote).foregroundStyle(Palette.text3).transition(.opacity)
                }
            }
            .padding(.bottom, 110)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { slide = true }
        }
        .accessibilityElement(children: .combine)
    }
}
