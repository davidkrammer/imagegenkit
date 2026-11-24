import Foundation

/// The terms of use, accepted once before the app can be used (David's rule for all apps, 2026-11-22).
/// Raise `version` together with the version on strics.at/imagegenkit/terms when they change in a way that matters:
/// the consent screen then shows again.
enum TermsConsent {
    static let version = 1
    static let url = URL(string: "https://strics.at/imagegenkit/terms")!
    static let privacyURL = URL(string: "https://strics.at/privacy")!

    private static let versionKey = "termsVersion"
    private static let dateKey = "termsAcceptedAt"

    static var accepted: Bool {
        #if DEBUG
        // `-skipTerms YES` (screenshots and UI tests only).
        if UserDefaults.standard.bool(forKey: "skipTerms") { return true }
        #endif
        return UserDefaults.standard.integer(forKey: versionKey) >= version
    }

    static var acceptedAt: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    static func accept() {
        UserDefaults.standard.set(version, forKey: versionKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}
