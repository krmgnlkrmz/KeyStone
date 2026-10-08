import AppTrackingTransparency

/// App Tracking Transparency, asked once after UMP and after our one-screen primer.
@MainActor
enum TrackingAuthorization {
    static var needsPrompt: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .notDetermined
    }

    static var isAuthorized: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .authorized
    }

    @discardableResult
    static func request() async -> ATTrackingManager.AuthorizationStatus {
        guard needsPrompt else { return ATTrackingManager.trackingAuthorizationStatus }
        // The completion-handler variant calls back on a background queue; the async one is safe here.
        return await ATTrackingManager.requestTrackingAuthorization()
    }
}
