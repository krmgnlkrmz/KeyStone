import BalanceCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = app.router
        ZStack {
            switch app.launchPhase {
            case .splash:
                SplashView(waitingForConsent: false)
            case .consent:
                ConsentGateView()
            case .trackingPrimer:
                ATTPrimerView()
            case .ready:
                NavigationStack(path: $router.path) {
                    MainMenuView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .map: LevelMapView()
                            case .endless: EndlessView()
                            }
                        }
                }
                .tint(Palette.accent)
                .transition(.opacity)
            }
            if let toast = app.toast, app.router.game == nil {
                VStack { ToastView(text: toast).padding(.top, 70); Spacer() }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(item: $router.game) { launch in
            GameContainerView(launch: launch)
                .environment(app)
                .preferredColorScheme(app.appearance.colorScheme)
        }
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .settings: SettingsView()
                case .daily: DailyLevelView()
                }
            }
            .environment(app)
            .preferredColorScheme(app.appearance.colorScheme)
        }
        .preferredColorScheme(app.appearance.colorScheme)
        .task { await app.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.sceneBecameActive() }
        }
        .onOpenURL { app.handle(url: $0) }
    }
}
