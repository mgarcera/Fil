import Foundation

/// Single source of truth for Fil's external links.
///
/// Set `appStoreID` after the app record exists in App Store Connect. Nothing else needs to change.
///
/// Draft page content lives in the repo under `docs/legal/` and `docs/support/`.
enum FilLinks {
    static let privacyPolicy = URL(string: "https://rootcause.ltd/fil/privacy")!
    static let termsOfService = URL(string: "https://rootcause.ltd/fil/terms")!
    static let support = URL(string: "https://rootcause.ltd/fil/support")!

    /// Contact / feedback address (also the App Store Connect support contact).
    static let contactEmail = URL(string: "mailto:mason@garcera.us")!

    // TODO(launch): set the numeric App Store ID once the app record exists in App Store Connect.
    static let appStoreID = "0000000000"

    /// Deep link that opens Fil's App Store page straight to the "Write a Review" sheet.
    static var writeReview: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }
}
