import Foundation
import SwiftData

struct AttachmentEntry: Codable, Equatable {
    enum Kind: String, Codable {
        case image, recording, link, textNote, linkedNote, pdf, video
    }

    var id: UUID = UUID()
    var kind: Kind
    var imageData: Data?
    var text: String?
    var linkedNoteID: String?
    var faviconData: Data?
    var pdfData: Data?
    var pdfName: String?
    var noteTitle: String?
    var linkCaption: String?

    static func image(_ data: Data) -> AttachmentEntry {
        AttachmentEntry(kind: .image, imageData: data)
    }

    static func recording(path: String) -> AttachmentEntry {
        AttachmentEntry(kind: .recording, text: path)
    }

    static func link(url: String, caption: String? = nil) -> AttachmentEntry {
        AttachmentEntry(kind: .link, text: url, linkCaption: caption)
    }

    static func note(_ text: String = "") -> AttachmentEntry {
        AttachmentEntry(kind: .textNote, text: text)
    }

    static func linkedNote(id: UUID, title: String) -> AttachmentEntry {
        AttachmentEntry(kind: .linkedNote, text: title, linkedNoteID: id.uuidString)
    }

    static func pdf(data: Data, name: String) -> AttachmentEntry {
        AttachmentEntry(kind: .pdf, pdfData: data, pdfName: name)
    }

    /// Video files are large, so — like audio recordings — we store a file PATH in `text`
    /// (a filename in the app's documents directory), never the bytes.
    static func video(path: String) -> AttachmentEntry {
        AttachmentEntry(kind: .video, text: path)
    }
}

@Model
final class KeywordAttachment {
    var keyword: String
    var entries: [AttachmentEntry] = []
    var note: Note?

    init(keyword: String, note: Note) {
        self.keyword = keyword
        self.note = note
    }
}
