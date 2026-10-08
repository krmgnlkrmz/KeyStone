import Foundation

/// Values that differ per build configuration. They come from Config/*.xcconfig through Info.plist,
/// so no ad unit ID, bundle ID or address is written in Swift source (§11.17).
enum AppConfig {
    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static var appGroupIdentifier: String { string("DNAppGroupIdentifier") }
    static var removeAdsProductID: String { string("DNRemoveAdsProductID") }
    static var supportEmail: String { string("DNSupportEmail") }
    static var urlScheme: String { string("DNURLScheme") }

    static var privacyPolicyURL: URL? {
        let raw = string("DNPrivacyPolicyURL")
        guard !raw.contains("PLACEHOLDER"), let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }

    static var supportURL: URL? {
        let mail = supportEmail
        guard !mail.contains("PLACEHOLDER"), mail.contains("@") else { return nil }
        return URL(string: "mailto:\(mail)")
    }

    enum AdUnit {
        static var banner: String { string("DNAdUnitBanner") }
        static var interstitial: String { string("DNAdUnitInterstitial") }
        static var rewarded: String { string("DNAdUnitRewarded") }
    }

    static var versionString: String {
        let v = string("CFBundleShortVersionString"), b = string("CFBundleVersion")
        return "\(v) (\(b))"
    }

    /// Game Center achievement IDs are derived from the bundle ID at runtime.
    static func achievementID(_ suffix: String) -> String {
        "\(Bundle.main.bundleIdentifier ?? "app").ach.\(suffix)"
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
