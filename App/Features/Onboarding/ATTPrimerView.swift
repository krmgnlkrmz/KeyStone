import SwiftUI

/// One screen, two lines, Continue — shown before the system tracking prompt. Either answer is fine.
struct ATTPrimerView: View {
    @Environment(AppModel.self) private var app
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack {
                if let level = app.catalog.curated.dropFirst(4).first {
                    SilhouetteView(silhouette: app.silhouette(for: level), color: Palette.text3, keyColor: Palette.accent)
                        .frame(width: 190, height: 240)
                        .padding(.top, 90)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 48, height: 48)
                    .background(Palette.accentSoft, in: Circle())
                Text("att.title").font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 6) {
                    Text("att.body1")
                    Text("att.body2")
                }
                .font(.body)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    busy = true
                    Task { await app.trackingPrimerContinue() }
                } label: { Text("common.continue") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
            }
            .padding(EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
