//
//  BinFilingSheet.swift
//  Fil
//
//  "File the Bin" — review Claude's proposals before anything moves.
//

import SwiftUI
import SwiftData

/// Identity wrapper so the tray can be presented with `.sheet(item:)` — the proposals themselves
/// are a value type and carry no identity of their own.
struct BinFilingProposal: Identifiable {
    let id = UUID()
    let items: [BinFilingSheet.Proposal]
}

/// A propose → review → commit tray, ported from Remindown's Copilot (Components/Copilot):
/// one card per item, each with its own destination, editable and removable, and nothing is
/// written until you commit.
///
/// That shape is the whole safety story here. Shake is easy to trigger by accident and this
/// moves every loose fil at once, so the gesture opens *this* — a proposal you can read — and
/// the only irreversible step is a button you pressed on purpose.
///
/// The model is told that "leave it loose" beats a wrong guess, so an all-unfiled result is a
/// legitimate answer and gets its own empty state rather than an error.
struct BinFilingSheet: View {
    /// One loose fil and where it is proposed to go. `destination` is what the user edits.
    struct Proposal: Identifiable {
        let id: UUID
        let note: Note
        var destination: Folder?
        /// Where Claude put it, kept so the row can show when you have overridden the proposal.
        let proposed: Folder?
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let folders: [Folder]
    @State var proposals: [Proposal]
    /// Called after the moves are written, so the caller can offer an undo.
    var onFiled: ([UUID: Folder?]) -> Void = { _ in }

    private var filedCount: Int { proposals.filter { $0.destination != nil }.count }

    var body: some View {
        NavigationStack {
            Group {
                if proposals.isEmpty {
                    ContentUnavailableView(
                        "Nothing to file",
                        systemImage: "tray",
                        description: Text("Your Bin is empty.")
                    )
                } else if filedCount == 0 {
                    // Not a failure: the model is instructed to prefer loose over wrong.
                    ContentUnavailableView(
                        "Nothing fit",
                        systemImage: "tray",
                        description: Text("None of these matched a folder you already have. Pick one yourself, or leave them in the Bin.")
                    )
                    .overlay(alignment: .bottom) { list.frame(maxHeight: .infinity) }
                } else {
                    list
                }
            }
            .navigationTitle("File the Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(filedCount == 0 ? "File" : "File \(filedCount)") { commit() }
                        .disabled(filedCount == 0)
                }
            }
        }
    }

    private var list: some View {
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
            Text(note.displayBadgeText.isEmpty ? note.title : note.displayBadgeText)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // The destination picker — Copilot's onSelectList, with folders in place of lists.
                Menu {
                    ForEach(folders) { folder in
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

    /// Write the moves. Captures each fil's previous folder first so the caller can undo the
    /// whole batch — the gesture that opened this is the system's undo gesture, so the feature
    /// owes the user one of its own.
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
