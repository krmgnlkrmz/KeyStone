/// Carries a loaded SDK ad from its load completion back into the main-actor function awaiting it.
/// The SDK calls load completions on the main thread and the ad is only touched on the main actor;
/// the wrapper exists because the SDK's ad classes are not annotated `Sendable`.
struct AdHandoff<Ad: AnyObject>: @unchecked Sendable {
    let ad: Ad?
}
