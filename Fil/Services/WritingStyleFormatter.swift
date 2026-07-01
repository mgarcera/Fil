import Foundation

enum WritingStyleFormatter {
    static func applyVisibleStyle(to text: String, userProfile: UserProfile?) -> String {
        guard let userProfile else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        var styled = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if userProfile.prefersLowercase {
            styled = styled.lowercased()
        }

        return styled
    }
}
