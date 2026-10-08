import BalanceCore
import SwiftUI

/// One map cell: number, state tag, cached mini silhouette, stars or lock.
struct LevelCellView: View {
    enum CellState: Equatable {
        case locked, open, next
        case done(Int)
    }

    @Environment(AppModel.self) private var app
    let level: Level
    let state: CellState

    var body: some View {
        Button(action: tap) {
            VStack {
                HStack {
                    Text(verbatim: "\(level.index)").font(.system(size: 15, weight: .heavy, design: .rounded))
                    Spacer()
                    tag
                }
                SilhouetteView(silhouette: app.silhouette(for: level), color: silhouetteColor, keyColor: keyColor, showFloor: true)
                    .frame(height: 76)
                    .drawingGroup()
                stars
            }
            .padding(10)
            .frame(height: 150)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(border, lineWidth: state == .next ? 1.5 : 1))
            .opacity(state == .locked ? 0.5 : 1)
        }
        .buttonStyle(PressPlain())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("level.\(level.index)")
    }

    @ViewBuilder private var tag: some View {
        switch state {
        case .done: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.jade)
        case .next: Text("map.play").font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Palette.accent)
        default: EmptyView()
        }
    }

    @ViewBuilder private var stars: some View {
        switch state {
        case .locked:
            Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(Palette.text3).frame(minHeight: 18)
        case let .done(n):
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < n ? "star.fill" : "star").foregroundStyle(i < n ? Palette.accent : Palette.text3)
                }
            }
            .font(.system(size: 13)).frame(minHeight: 18)
        case .open, .next:
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in Image(systemName: "star").foregroundStyle(Palette.text3) }
            }
            .font(.system(size: 13)).frame(minHeight: 18)
        }
    }

    private var background: Color { state == .next ? Palette.accentSoft : Palette.surface }
    private var border: Color { state == .next ? Palette.accent : Palette.line }
    private var silhouetteColor: Color {
        switch state {
        case .locked: return Palette.text3
        case .next, .open: return Palette.text
        case .done: return Palette.text2
        }
    }
    private var keyColor: Color { state == .locked ? Palette.text3 : Palette.accent }

    private var accessibilityText: String {
        let name = Copy.levelTitle(level, mode: .campaign)
        switch state {
        case .locked: return "\(name), \(String(localized: "a11y.locked"))"
        case .open, .next: return "\(name), \(String(localized: "a11y.notPlayed"))"
        case let .done(n): return "\(name), \(String(localized: "a11y.stars \(n)"))"
        }
    }

    private func tap() {
        if state == .locked {
            app.haptics.nope()
            app.showToast(String(localized: "map.lockedToast"))
        } else {
            app.play(level)
        }
    }
}
