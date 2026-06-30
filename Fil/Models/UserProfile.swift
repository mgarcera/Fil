import Foundation
import SwiftData

@Model
final class UserProfile {
    var prefersLowercase: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        prefersLowercase: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.prefersLowercase = prefersLowercase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
