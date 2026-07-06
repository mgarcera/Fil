import Foundation

/// Single source of truth for Fil's external links.
///
/// The web pages aren't hosted yet. Once they're live, replace the three placeholder URLs
/// below with the real hosted addresses, and set `appStoreID` after the app record exists in
/// App Store Connect. Nothing else in the app needs to change.
///
/// Draft page content lives in the repo under `docs/legal/` and `docs/support/`.
enum FilLinks {
    // TODO(launch): replace with the real hosted URLs.
    static let privacyPolicy = URL(string: "https://fil.example.com/privacy")!
    static let termsOfService = URL(string: "https://fil.example.com/terms")!
    static let support = URL(string: "https://fil.example.com/support")!

    /// Contact / feedback address (also the App Store Connect support contact).
    static let contactEmail = URL(string: "mailto:mason@garcera.us")!

    // TODO(launch): set the numeric App Store ID once the app record exists in App Store Connect.
    static let appStoreID = "0000000000"

    /// Deep link that opens Fil's App Store page straight to the "Write a Review" sheet.
    static var writeReview: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }
}
