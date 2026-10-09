import SwiftUI
import UIKit

/// Settings (a sheet everywhere): Game, Purchases, Privacy, Player Data, About.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmReset = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $app.appearance) {
                        Text("settings.appearance.system").tag(AppearancePreference.system)
                        Text("settings.appearance.light").tag(AppearancePreference.light)
                        Text("settings.appearance.dark").tag(AppearancePreference.dark)
                    } label: {
                        SettingsLabel(icon: "circle.lefthalf.filled", title: "settings.appearance")
                    }
                    toggle("speaker.wave.2", "settings.sound", \.sound)
                    toggle("music.note", "settings.music", \.music)
                    toggle("waveform", "settings.haptics", \.haptics)
                    toggle("arrow.left.to.line", "settings.leftHand", \.leftHanded)
                    LabeledContent {
                        Text(reduceMotion ? "settings.on" : "settings.off").foregroundStyle(Palette.text2)
                    } label: {
                        SettingsLabel(icon: "figure.walk.motion", title: "settings.reduceMotion")
                    }
                } header: {
                    Text("settings.game")
                } footer: {
                    Text("settings.leftHand.footer")
                }

                Section {
                    if app.store.adsRemoved {
                        LabeledContent {
                            Text("settings.purchased").foregroundStyle(Palette.jade)
                        } label: {
                            SettingsLabel(icon: "checkmark", title: "settings.adsRemoved", tint: Palette.jade, soft: Palette.jadeSoft)
                        }
                    } else {
                        Button { Task { await app.store.purchase() } } label: {
                            LabeledContent {
                                if app.store.state == .purchasing {
                                    ProgressView()
                                } else if let price = app.store.displayPrice {
                                    Text(verbatim: price).font(.body.weight(.semibold)).foregroundStyle(Palette.accent)
                                }
                            } label: {
                                SettingsLabel(icon: "rectangle.slash", title: "settings.removeAds")
                            }
                        }
                        .disabled(app.store.state == .purchasing || app.store.state == .pending)
                        if app.store.state == .pending {
                            LabeledContent {
                                Text("settings.pending").foregroundStyle(Palette.text2)
                            } label: {
                                SettingsLabel(icon: "hourglass", title: "settings.removeAds")
                            }
                        }
                    }
                    Button {
                        Task {
                            let owned = await app.store.restore()
                            app.showToast(owned ? String(localized: "settings.restored") : String(localized: "settings.nothingToRestore"))
                        }
                    } label: {
                        HStack {
                            SettingsLabel(icon: "arrow.counterclockwise", title: "settings.restore", titleColor: Palette.accent)
                            Spacer()
                            if app.store.restoring { ProgressView() }
                        }
                    }
                    .disabled(app.store.restoring)
                } header: {
                    Text("settings.purchases")
                } footer: {
                    if app.store.state == .pending { Text("settings.pending.footer") }
                    else if app.store.state == .failed { Text("settings.failed") }
                }

                Section("settings.privacy") {
                    if app.ads.privacyOptionsRequired {
                        Button { Task { await app.ads.presentPrivacyOptions() } } label: {
                            HStack {
                                SettingsLabel(icon: "hand.raised", title: "settings.privacySettings", titleColor: Palette.text)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.text3)
                            }
                        }
                    }
                    Button {
                        if let url = AppConfig.privacyPolicyURL { openURL(url) }
                        else { app.showToast(String(localized: "settings.privacyPolicy.missing")) }
                    } label: {
                        HStack {
                            SettingsLabel(icon: "checkmark.shield", title: "settings.privacyPolicy", titleColor: Palette.text)
                            Spacer()
                            Image(systemName: "arrow.up.right.square").foregroundStyle(Palette.text3)
                        }
                    }
                }

                Section("settings.playerData") {
                    Button(role: .destructive) { confirmReset = true } label: {
                        SettingsLabel(icon: "trash", title: "settings.reset", tint: Palette.text2, soft: Palette.surface2, titleColor: Palette.text)
                    }
                }

                Section("settings.about") {
                    LabeledContent {
                        Text(verbatim: AppConfig.versionString).foregroundStyle(Palette.text2)
                    } label: {
                        SettingsLabel(icon: "info.circle", title: "settings.version")
                    }
                    if let support = AppConfig.supportURL {
                        Button { openURL(support) } label: {
                            SettingsLabel(icon: "envelope", title: "settings.support", titleColor: Palette.text)
                        }
                    }
                    if app.achievements.isAuthenticated {
                        Button { app.achievements.showDashboard() } label: {
                            SettingsLabel(icon: "trophy", title: "menu.gameCenter", titleColor: Palette.text)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("common.done").bold() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { BannerSlot() }
            .alert(Text("reset.alert.title"), isPresented: $confirmReset) {
                Button(role: .cancel) {} label: { Text("common.cancel") }
                Button(role: .destructive) { app.resetProgress() } label: { Text("reset.alert.confirm") }
            } message: {
                Text("reset.alert.body")
            }
        }
        .tint(Palette.accent)
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ icon: String, _ title: LocalizedStringKey, _ key: WritableKeyPath<ProgressStore.Settings, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { app.progress.settings[keyPath: key] },
            set: { v in
                app.progress.update { $0[keyPath: key] = v }
                app.applySettings()
            })) {
            SettingsLabel(icon: icon, title: title)
        }
        .tint(Palette.jade)
    }
}

/// 29 pt rounded icon tile + title, as in the design.
struct SettingsLabel: View {
    /// The icon tile grows with the text so a large-text row stays in proportion.
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 29
    let icon: String
    let title: LocalizedStringKey
    var tint: Color = Palette.accent
    var soft: Color = Palette.accentSoft
    var titleColor: Color = Palette.text

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .scaledFont(15, weight: .medium, relativeTo: .body)
                .foregroundStyle(tint)
                .frame(width: tile, height: tile)
                .background(soft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title).foregroundStyle(titleColor)
        }
    }
}
