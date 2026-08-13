import SwiftUI

// Shared fil-card language. The folder interior and the search results both render fils as full-width
// cards inside typed sections; these are the single source of truth for that look. Call sites keep
// their own chrome (swipe / select / tap in the folder List; tap-to-play + context menu in search).

// MARK: - Section header

/// A type-container header: an icon + serif label + a count chip.
struct FilSectionHeader: View {
    let label: String
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Text(label).font(Theme.instrumentSerif(22)).foregroundStyle(Theme.primaryText)
            Text("\(count)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
            Spacer()
        }
    }
}

// MARK: - Cards

/// A full-width fil card: the rich marker (photo thumb / fil blob) on the left, light text over the
/// fil's gradient wash. Plain notes and photos caption their date; typed fils keep their identity.
struct FilCard: View {
    let note: Note

    var body: some View {
        let isPlainNote = !(note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty)
        let showsDate = isPlainNote || note.isImageFil
        let main = FilCardText.content(note)
        HStack(alignment: .top, spacing: 14) {
            FilCardRich(note: note)
            VStack(alignment: .leading, spacing: 3) {
                // A captionless photo has no words — show only its date below the thumbnail.
                if !main.isEmpty {
                    Text(FilCardText.highlighted(note, base: main))
                        .font(Theme.fredoka(15, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(30)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let caption = showsDate
                    ? note.timestamp.formatted(date: .abbreviated, time: .omitted)
                    : FilCardText.caption(note)
                if !caption.isEmpty {
                    Text(caption).font(Theme.fredoka(12, weight: .light)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .filCardChrome(note)
    }
}

/// A fil's to-dos as a note-style card: the rich marker + the fil's thought, then each to-do as a
/// checkbox row. Toggling a row calls `onToggle` with the to-do's index.
struct FilTodoCard: View {
    let note: Note
    let onToggle: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FilCardRich(note: note)
            VStack(alignment: .leading, spacing: 8) {
                // The fil's own thought, so the user sees what they typed above its to-dos.
                let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    Text(body)
                        .font(Theme.fredoka(15, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(30)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(note.todoRowItems, id: \.id) { item in
                    Button { onToggle(item.index) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            TodoStatusCircle(isCompleted: item.done, onColor: true)
                            Text(item.text)
                                .font(Theme.fredoka(15, weight: .light))
                                .foregroundStyle(.white)
                                .strikethrough(item.done, color: .white.opacity(0.5))
                                .opacity(item.done ? 0.6 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .filCardChrome(note)
    }
}

// MARK: - Shared building blocks

/// The row's leading rich component. Photo thumbnails stretch to the card's height; the fil blob and
/// link / voice markers stay fixed squares, top-aligned beside long text.
struct FilCardRich: View {
    let note: Note

    var body: some View {
        if note.isImageFil {
            FilCardPhotoThumb(note: note)
                .frame(width: 52)
                .frame(minHeight: 52, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Group {
                if note.isLinkFil || !note.audioFilePath.isEmpty {
                    NoteCardView(note: note, cardHeight: 48)
                } else {
                    NoteBlobShape(seed: note.blobShapeSeed)
                        .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                }
            }
            .frame(width: 48, height: 48)
        }
    }
}

private struct FilCardPhotoThumb: View {
    let note: Note

    var body: some View {
        if let data = note.sortedImageFilImages.first?.data, let image = Image(data: data) {
            image.resizable().scaledToFill()
        } else {
            Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed)
        }
    }
}

/// The Full Screen player's exact wash: a plain diagonal 2-color gradient, zoomed and blurred into a
/// soft low-contrast field, darkened so light text stays legible. Clipped to the card by the chrome.
private struct FilCardWash: View {
    let note: Note

    var body: some View {
        LinearGradient(colors: [Color(hex: note.gradientStartHex), Color(hex: note.gradientEndHex)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .scaleEffect(3.5)
            .overlay(Color.black.opacity(0.44))
    }
}

private extension View {
    /// The shared card chrome: padding, the gradient wash background, the 30pt clip, and the hairline.
    func filCardChrome(_ note: Note) -> some View {
        self
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { FilCardWash(note: note) }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Card text

/// The card's text derivations, shared so the folder interior and search read identically.
enum FilCardText {
    /// A card's main text: plain notes and photos show their own words (no generated title); other
    /// typed fils (links, voice) show their identity.
    static func content(_ note: Note) -> String {
        if note.isImageFil { return note.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
        if note.isLinkFil || !note.audioFilePath.isEmpty { return title(note) }
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? title(note) : body
    }

    /// A fil's title: its first-line title if it has one, else its type badge.
    static func title(_ note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? note.displayBadgeText : trimmed
    }

    /// The identity caption for typed fils: a link's domain, a voice fil's duration, or — for a plain
    /// note — a preview of the note's own text.
    static func caption(_ note: Note) -> String {
        if note.isLinkFil { return note.sourceDomain ?? "link" }
        if !note.audioFilePath.isEmpty { return note.duration.clockLabel }
        let body = note.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return body.isEmpty ? "note" : body
    }

    /// The card's main text with its filament keywords lit — same treatment as the reading view
    /// (Fredoka medium in the fil's lighter gradient color), so highlights read on the card too.
    static func highlighted(_ note: Note, base: String) -> AttributedString {
        var attributed = AttributedString(base)
        let keywords = note.attachments.map(\.keyword)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !keywords.isEmpty else { return attributed }

        let color = Color(hex: Theme.lighterHex(note.gradientStartHex, note.gradientEndHex))
        for keyword in keywords {
            var start = attributed.startIndex
            while start < attributed.endIndex,
                  let range = attributed[start...].range(of: keyword, options: .caseInsensitive) {
                attributed[range].font = Theme.fredoka(15, weight: .medium)
                attributed[range].foregroundColor = color
                start = range.upperBound
            }
        }
        return attributed
    }
}
