import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Fil/Info.plist as an exported type conforming to public.zip-archive.
    static let filbox = UTType(exportedAs: "com.smidgecraft.Fil.filbox")
}

/// The export/import pair, at the bottom of Settings → About.
///
/// It sits in About rather than anywhere more prominent because this is not a feature people browse
/// for. It is the thing they look for at one specific anxious moment, and About is where you look
/// when the question is "is my stuff safe".
struct FilBoxSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var exportTask: Task<Void, Never>?
    @State private var progress: FilBoxExporter.Progress?
    @State private var exportedURL: URL?
    @State private var showImporter = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Getting a new phone, or want a copy you keep yourself? Export everything as a single file you can store anywhere: fils, folders, photos, recordings, files.")
                .font(Theme.dmSans(13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                HStack(spacing: 12) {
                    ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        .tint(.white)
                    Text("\(progress.completed) of \(progress.total)")
                        .font(Theme.dmSans(12))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                    Button("Stop") { exportTask?.cancel() }
                        .font(Theme.dmSans(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else if let exportedURL {
                ShareLink(item: exportedURL) {
                    rowLabel("Share your backup", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            } else {
                Button { startExport() } label: {
                    rowLabel("Export a backup", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.plain)
            }

            Text("It's a zip renamed .filbox and it'll open years from now. Import it on any iPhone with Fil to bring everything back. Or you could unzip it on your computer to read them in your file browser.")
                .font(Theme.dmSans(13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Button { showImporter = true } label: {
                rowLabel("Import a backup", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.plain)

            if let message {
                Text(message)
                    .font(Theme.dmSans(12))
                    .foregroundStyle(isError ? Color.red.opacity(0.9) : .white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.filbox, .zip]) { result in
            handleImport(result)
        }
    }

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(Theme.fredoka(16, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Export

    private func startExport() {
        message = nil
        exportedURL = nil
        let container = modelContext.container

        exportTask = Task {
            let exporter = FilBoxExporter(modelContainer: container)
            do {
                let url = try await exporter.export { update in
                    await MainActor.run { progress = update }
                }
                await MainActor.run {
                    progress = nil
                    exportedURL = url
                    isError = false
                    message = "Your backup is ready."
                }
            } catch is CancellationError {
                await MainActor.run {
                    progress = nil
                    isError = false
                    message = "Export stopped. Nothing was changed."
                }
            } catch {
                await MainActor.run {
                    progress = nil
                    isError = true
                    message = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let outcome = try FilBoxImporter.run(url: url, context: modelContext)
            isError = false
            message = outcome.summarySentence
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}
