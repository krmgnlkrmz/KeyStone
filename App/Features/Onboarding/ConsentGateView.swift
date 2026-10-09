import SwiftUI

/// Shown behind Google's consent form while UMP decides; never blocks the game on errors.
struct ConsentGateView: View {
    var body: some View {
        SplashView(waitingForConsent: true)
    }
}
