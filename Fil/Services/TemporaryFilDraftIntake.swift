import Foundation

enum TemporaryFilDraftIntake {
    static func text(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "fil" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host()?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "draft" || path == "draft" else { return nil }

        let queryText = components?.queryItems?.first(where: { $0.name == "text" })?.value
        let queryURL = components?.queryItems?.first(where: { $0.name == "url" })?.value
        let queryTitle = components?.queryItems?.first(where: { $0.name == "title" })?.value

        let parts = [queryTitle, queryText ?? queryURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
