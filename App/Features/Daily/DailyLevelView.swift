import BalanceCore
import SwiftUI

/// Daily Level sheet: today's structure, streak, this week, Play.
struct DailyLevelView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Kicker(text: Text(verbatim: Copy.longDate(app.todayKey)))
                Spacer()
                Button { dismiss() } label: { Text("daily.done").font(.body.weight(.semibold)) }
                    .tint(Palette.accent)
                    .frame(minHeight: 44)
            }
            Text("daily.title").font(Typo.title1).padding(.top, -8)
            ZStack(alignment: .bottom) {
                BlueprintGrid().clipShape(RoundedRectangle(cornerRadius: 22))
                if let level = app.dailyLevel {
                    SilhouetteView(silhouette: app.silhouette(for: level), color: Palette.text2, keyColor: Palette.accent)
                        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 22)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.line, lineWidth: 1))

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("daily.streak \(app.displayStreak)").font(.body.weight(.semibold))
                    Spacer()
                    Text(app.dailySolvedToday ? "daily.solved" : "daily.notSolved")
                        .font(.footnote).foregroundStyle(app.dailySolvedToday ? Palette.jade : Palette.text2)
                }
                WeekStrip(todayKey: app.todayKey, solved: Set(app.progress.dailyKeys))
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))

            Spacer(minLength: 0)
            Button { app.playDaily() } label: {
                Label {
                    if app.dailySolvedToday { Text("daily.playAgain") }
                    else { Text("daily.play \(app.dailyLevel?.goal.normalizedThresholds.first ?? 0)") }
                } icon: { Image(systemName: "play.fill") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("daily.play")
            .disabled(app.dailyLevel == nil)
            Text("daily.footer").font(.footnote).foregroundStyle(Palette.text3).frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 12, trailing: 20))
        .keystoneSheet()
    }
}

private struct WeekStrip: View {
    let todayKey: String
    let solved: Set<String>

    var body: some View {
        let keys = StreakRules.weekKeys(containing: todayKey)
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                let isSolved = solved.contains(key)
                let isToday = key == todayKey
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isSolved ? Palette.jadeSoft : .clear)
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isSolved ? Palette.jade : (isToday ? Palette.accent : Palette.line2),
                                          style: StrokeStyle(lineWidth: isToday && !isSolved ? 1.5 : 1, dash: isSolved || isToday ? [] : [3, 3]))
                        if isSolved {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.jade)
                        } else if isToday {
                            KeystoneGlyph().fill(Palette.accent).frame(width: 14, height: 14)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 36)
                    Text(weekdayLetter(key)).font(.caption2).foregroundStyle(Palette.text3)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Copy.shortDate(key)))
                .accessibilityValue(Text(isSolved ? "daily.solved" : "daily.notSolved"))
            }
        }
    }

    private func weekdayLetter(_ key: String) -> String {
        Copy.date(forKey: key)?.formatted(.dateTime.weekday(.narrow)) ?? ""
    }
}
