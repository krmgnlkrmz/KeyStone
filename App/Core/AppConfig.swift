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
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || isUITest
    }

    /// Launched by the UI smoke test / screenshot run: no consent, no ads, in-memory store,
    /// piece accessibility elements always on so the test can tap pieces.
    static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") }

    /// When the kernel started this process, for the cold-start measurement (process start to the menu,
    /// so dyld and runtime setup count too). Nil if the kernel does not say.
    static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()

    /// Hidden elements that report internals to UI tests (strut requests, launch time). Off for the
    /// accessibility audit, which would rightly flag them.
    static var exposesTestProbes: Bool { isUITest && ProcessInfo.processInfo.arguments.contains("-testProbes") }

    /// UI test stand-in for a full-screen ad over the game (interstitial, rewarded): see GameContainerView.
    static var coversFirstLevel: Bool { isUITest && ProcessInfo.processInfo.arguments.contains("-coverProbe") }

    /// UI tests can pre-complete the first N curated levels to show a populated map.
    static var uiTestSeedLevels: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-seedLevels"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }
}
