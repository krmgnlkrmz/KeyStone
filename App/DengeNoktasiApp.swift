import SwiftUI

@main
struct DengeNoktasiApp: App {
    @State private var app = AppModel(inMemoryStore: AppConfig.isRunningTests)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}
