import Foundation

/// Single source of truth for Fil's external links.
///
/// Set `appStoreID` after the app record exists in App Store Connect. Nothing else needs to change.
///
/// Draft page content lives in the repo under `docs/legal/` and `docs/support/`.
enum FilLinks {
    static let website = URL(string: "https://rootcause.ltd/fil")!
    static let privacyPolicy = URL(string: "https://rootcause.ltd/fil/privacy")!
    static let termsOfService = URL(string: "https://rootcause.ltd/fil/terms")!
    static let support = URL(string: "https://rootcause.ltd/fil/support")!

    /// Contact / feedback address (also the App Store Connect support contact).
    static let contactEmail = URL(string: "mailto:mason@smidgecraft.com")!

    /// Fil's App Store record ID (App Store Connect → App Information → Apple ID).
    static let appStoreID = "6790072250"

    /// Deep link that opens Fil's App Store page straight to the "Write a Review" sheet.
    static var writeReview: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }
}
