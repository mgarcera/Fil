#if DEBUG
import SwiftUI
import PhotosUI
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// A folder's own photograph, treated so it can always be read on.
///
/// **Why the treatment is automatic and not a slider.** A gradient's luminance is ours to choose;
/// a user's photograph is not. The same folder page puts white text straight on this ground, and a
/// bright beach shot would leave it at about 1.5:1. So the treatment measures the image and veils
/// it until white clears 7:1 — a dark photograph gets almost no veil, a bright one gets a heavy
/// one, and neither can produce an unreadable folder. A slider would let someone do exactly that.
///
/// **Stored outside SwiftData while this is a study.** `Folder` would want
/// `@Attribute(.externalStorage) var coverImageData: Data?` if this ships, the same pattern
/// `Note.imageData` and `NoteImage.data` already use. A file per folder keeps the schema untouched
/// and the prototype trivially removable.
enum FolderCoverStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SandboxFolderCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func url(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    static func load(_ id: UUID) -> Data? { try? Data(contentsOf: url(id)) }

    static func clear(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
        prepared.removeValue(forKey: id)
    }

    /// Decoded image and solved veil, kept per folder.
    ///
    /// **This cache is the reason the composer's spring does not stutter over a cover.** A SwiftUI `View` is a struct that is
    /// re-initialised on every render pass of its parent, so anything done in `init` is done per
    /// FRAME, not per appearance. `FolderCoverGround.init` was decoding a 900px JPEG and running a
    /// 24-round bisection over an 8x8 thumbnail, on the main thread, for every frame of the
    /// composer's spring — which is why only folders WITH a photograph flashed. Main-thread only, which
    /// is where SwiftUI initialises views.
    private static var prepared: [UUID: (image: UIImage?, veil: Double)] = [:]

    static func prepare(_ data: Data, for id: UUID) -> (image: UIImage?, veil: Double) {
        if let hit = prepared[id] { return hit }
        let made = (UIImage(data: data), veil(for: data))
        prepared[id] = made
        return made
    }

    /// Downsampled to 900 on the long edge before it is stored. The image is blurred past
    /// recognition on screen, so full resolution is bytes nobody sees — the same reasoning, and the
    /// same ImageIO call, as `PhotoStackHero.downsampled(_:)` in FilFullScreenPlayer.swift.
    static func save(_ data: Data, for id: UUID) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.82) else { return }
        try? jpeg.write(to: url(id))
        prepared.removeValue(forKey: id)
    }

    /// The black veil this image needs so white text on it clears 7:1.
    ///
    /// Measured, not guessed: the image is reduced to 8x8, averaged, and the veil solved for by
    /// bisection against the same contrast formula the gradient's luminance floor uses. Capped at
    /// 0.82 so a white-on-white photograph becomes very dark rather than pure black.
    static func veil(for data: Data) -> Double {
        guard let mean = meanColour(data) else { return 0.45 }
        var lo = 0.0, hi = 0.82
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if contrastWithWhite(mean.map { $0 * (1 - mid) }) >= 7 { hi = mid } else { lo = mid }
        }
        return hi
    }

    /// 8x8 is enough: the image is blurred to a wash anyway, so what matters is its overall level
    /// rather than anything in it.
    private static func meanColour(_ data: Data) -> [Double]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 8,
              ] as CFDictionary)
        else { return nil }

        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var totals = [0.0, 0.0, 0.0]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            totals[0] += Double(pixels[i]) / 255
            totals[1] += Double(pixels[i + 1]) / 255
            totals[2] += Double(pixels[i + 2]) / 255
        }
        return totals.map { $0 / Double(w * h) }
    }

    private static func contrastWithWhite(_ rgb: [Double]) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])
        return 1.05 / (l + 0.05)
    }
}

/// The ground a folder with a photograph gets: the image blurred past recognition, veiled to
/// whatever its own brightness requires, and grained with the app's own paper.
struct FolderCoverGround: View {
    let data: Data
    private let veil: Double
    private let image: UIImage?

    /// Both values come from `FolderCoverStore.prepare`, which memoises them per folder. Doing the
    /// decode here directly would do it on every render pass — see the note on that cache.
    init(data: Data, id: UUID) {
        self.data = data
        (image, veil) = FolderCoverStore.prepare(data, for: id)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Scaled up before the blur so the blur never reaches an edge and shows it —
                    // the same move BlurredFilBackground makes with a fil's gradient.
                    .scaleEffect(1.5)
                    .blur(radius: 48)
            }
            Color.black.opacity(veil)
            Image("PaperNoise")
                .resizable(resizingMode: .tile)
                .blendMode(.multiply)
                .opacity(0.07)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
#endif
