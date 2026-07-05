import Foundation
import SwiftData

@Model
final class UserProfile {
    var createdAt: Date
    var updatedAt: Date

    init(
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
