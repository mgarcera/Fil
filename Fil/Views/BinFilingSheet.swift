//
//  BinFilingSheet.swift
//  Fil
//
//  "File for me" — the whole flow, from asking Claude to writing the moves.
//

import SwiftUI
import SwiftData

/// What the sheet is presented with: the fils to file, decided by the caller (a selection if
/// there is one, otherwise the whole Bin). Identity so `.sheet(item:)` can drive it.
struct BinFilingProposal: Identifiable {
    let id = UUID()
    let notes: [Note]
    let folders: [Folder]
    let transactionID: String
}

/// A propose → review → commit tray, ported from Remindown's Copilot (Components/Copilot):
/// one card per item, each with its own destination, editable, and nothing written until you
/// commit. Its four states — loading, ready, nothing-fit, failed — are that component's state
/// machine; the first and last were the half I hadn't ported.
///
/// The sheet owns the request rather than receiving its result. That is what lets it open the
/// instant you tap: the rows are already known (they're your fils), so only the destinations
/// arrive late, and the presentation animation covers the first part of the wait. It also means
/// a second tap can't start a second call — the sheet is over the chip before you could.
struct BinFilingSheet: View {
    /// One loose fil and where it is proposed to go. `destination` is what the user edits.
    struct Proposal: Identifiable {
        let id: UUID
        let note: Note
        var destination: Folder?
        /// Where Claude put it, kept so the row can show when you have overridden the proposal.
        let proposed: Folder?
    }

    /// Proposals live beside the phase rather than inside `.ready`, so each row's picker can bind
    /// straight to `$proposals`. Threading a Binding through an enum payload needs a custom
    /// Binding extension, which is both harder to read and — on this toolchain — enough to crash
    /// the type checker outright.
    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let input: BinFilingProposal
    /// Called after the moves are written, so the caller can offer an undo.
    var onFiled: ([UUID: Folder?]) -> Void = { _ in }

    @State private var phase: Phase = .loading
    @State private var proposals: [Proposal] = []
    /// Bumped by Retry to re-key `.task`, which is what re-runs the request.
    @State private var attempt = 0

    /// A floor under the loading state. Without it a fast answer makes the skeletons strobe —
    /// a placeholder that appears and vanishes reads as a glitch, not as speed.
    private static let minimumLoading: Duration = .milliseconds(600)

    private var filedCount: Int { proposals.filter { $0.destination != nil }.count }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("File the Bin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Dismissing tears down `.task`, which cancels the URLSession request —
                        // a call you walked away from stops costing.
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if case .ready = phase {
                            Button(filedCount == 0 ? "File" : "File \(filedCount)") { commit() }
                                .disabled(filedCount == 0)
                        }
                    }
                }
        }
        .task(id: attempt) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingList
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't file", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { phase = .loading; attempt += 1 }
                    .buttonStyle(.borderedProminent)
            }
        case .ready:
            VStack(spacing: 0) {
                // Not a failure: the model is told that leaving a fil loose beats filing it
                // wrongly, so "none of these fit" is a real answer and gets said plainly.
                if filedCount == 0 {
                    Text("None of these matched a folder you already have. Pick one yourself, or leave them in the Bin.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                readyList
            }
        }
    }

    /// The rows are real from the first frame — same titles, same order — so only the folder
    /// chips resolve. The wait reads as filling in rather than loading.
    private var loadingList: some View {
        List {
            Section {
                ForEach(input.notes, id: \.uuid) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title(for: note))
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            // Width varies per row so the column doesn't read as a printed form.
                            SkeletonView(Capsule())
                                .frame(width: 70 + CGFloat(abs(note.uuid.hashValue) % 60), height: 13)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Reading your Bin…")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var readyList: some View {
        List {
            Section {
                ForEach($proposals) { $proposal in
                    row($proposal)
                }
            } footer: {
                Text("Anything left on \(Text("Leave in Bin").bold()) stays where it is.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ proposal: Binding<Proposal>) -> some View {
        let note = proposal.wrappedValue.note
        let overridden = proposal.wrappedValue.destination?.id != proposal.wrappedValue.proposed?.id

        return VStack(alignment: .leading, spacing: 8) {
            Text(title(for: note))
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // The destination picker — Copilot's onSelectList, with folders in place of lists.
                Menu {
                    ForEach(input.folders) { folder in
                        Button { proposal.wrappedValue.destination = folder } label: {
                            if folder.id == proposal.wrappedValue.destination?.id {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Text(folder.name)
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { proposal.wrappedValue.destination = nil } label: {
                        Label("Leave in Bin", systemImage: "tray")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(proposal.wrappedValue.destination?.name ?? "Leave in Bin")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(proposal.wrappedValue.destination == nil ? .secondary : .primary)
                }

                if overridden {
                    Text("edited")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func title(for note: Note) -> String {
        note.displayBadgeText.isEmpty ? note.title : note.displayBadgeText
    }

    // MARK: - The request

    private func load() async {
        let started = ContinuousClock.now
        let inputs = input.notes.map { note in
            FilClusterInput(
                id: note.uuid,
                text: String((note.transcript.isEmpty ? note.title : note.transcript).prefix(240)),
                keyword: note.displayBadgeText
            )
        }
        let choices = input.folders.map {
            ClaudeSurfacingService.FolderChoice(id: $0.id, name: $0.name, summary: $0.summary)
        }

        do {
            let filed = try await ClaudeSurfacingService.shared.fileIntoFolders(
                folders: choices, fils: inputs, transactionID: input.transactionID
            )
            // Hold the floor before showing anything, so a quick answer doesn't strobe.
            let elapsed = ContinuousClock.now - started
            if elapsed < Self.minimumLoading {
                try? await Task.sleep(for: Self.minimumLoading - elapsed)
            }
            guard !Task.isCancelled else { return }

            let notesByID = Dictionary(input.notes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
            let foldersByID = Dictionary(input.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let items = filed.compactMap { assignment -> Proposal? in
                guard let note = notesByID[assignment.filID] else { return nil }
                let destination = assignment.folderID.flatMap { foldersByID[$0] }
                return Proposal(id: assignment.filID, note: note, destination: destination, proposed: destination)
            }
            proposals = items
            withAnimation(.snappy) { phase = .ready }
        } catch is CancellationError {
            return   // the sheet went away; nothing to report to
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? ClaudeSurfacingService.SurfacingError)?.errorDescription
                ?? error.localizedDescription
            withAnimation(.snappy) { phase = .failed(message) }
        }
    }

    /// Write the moves, capturing each fil's previous folder first so the caller can undo the
    /// whole batch — this moves several fils at once, and a batch move should be reversible.
    private func commit() {
        var previous: [UUID: Folder?] = [:]
        for proposal in proposals where proposal.destination != nil {
            previous[proposal.note.uuid] = proposal.note.folder
            proposal.note.folder = proposal.destination
            proposal.note.sortIndex = 0
        }
        try? context.save()
        onFiled(previous)
        dismiss()
    }
}
