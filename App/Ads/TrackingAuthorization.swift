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
        return await withCheckedContinuation { (continuation: CheckedContinuation<ATTrackingManager.AuthorizationStatus, Never>) in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
