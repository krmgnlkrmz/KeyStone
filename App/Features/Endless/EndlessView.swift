import BalanceCore
import SwiftUI

/// Endless: a short loading beat, then the next level from the player's walk through the verified pool.
/// Copy is deliberately truthful: levels come from an offline-verified pool, not generated on device.
struct EndlessView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false
    @State private var launched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 24).fill(Palette.surface)
                RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line, lineWidth: 1)
                if let level = app.endlessLevel() {
                    SilhouetteView(silhouette: app.silhouette(for: level), color: Palette.line2, keyColor: Palette.line2)
                        .opacity(shimmer ? 1 : 0.4)
                        .padding(.horizontal, 30).padding(.vertical, 30)
                }
            }
            .frame(height: 420)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.text2)
                    Text("endless.building \(app.endlessNumber)").font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text("endless.body").font(.subheadline).foregroundStyle(Palette.text2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            Spacer()
        }
        .background(ScreenBackground(grid: false))
        .navigationTitle(Text("endless.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { shimmer = true }
            }
        }
        .task {
            launched = false
            try? await Task.sleep(for: .milliseconds(700))
            guard !launched, app.router.game == nil else { return }
            launched = true
            app.playEndless()
        }
        .onChange(of: app.router.game == nil) { _, closed in
            // Coming back from the game: return to the menu instead of auto-starting again.
            if closed { app.router.path.removeAll { $0 == .endless } }
        }
    }
}
