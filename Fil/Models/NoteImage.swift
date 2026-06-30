import Foundation
import SwiftData

@Model
final class NoteImage {
    @Attribute(.unique) var id: UUID = UUID()
    var order: Int
    @Attribute(.externalStorage) var data: Data
    var note: Note?

    init(data: Data, order: Int = 0, note: Note? = nil) {
        self.data = data
        self.order = order
        self.note = note
    }
}
