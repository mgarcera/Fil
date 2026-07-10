import SwiftUI
import SwiftData

/// TEMPORARY prototype — the "blank canvas" home direction (2026-07-10, see
/// docs/features/blank-canvas-home.md): the home is empty; you tap to capture a thought and
/// (later) long-press to surface past fils by a query. Phase 1 here is capture only:
///
///   blank → tap → creation blob + centered field → type → fil forms → blank
///
/// Reached via the temporary ▦ button in the ContentView header. Delete both when promoted.
/// Creation mirrors ContentView.saveGeneratedNote (title generation + gradient + insert); kept
/// self-contained so the prototype stays isolated from the current home.
struct BlankCanvasPrototype: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case idle, composing, creating }

    @State private var phase: Phase = .idle
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCanvasTap() }

            switch phase {
            case .idle:      idleHint
            case .composing: composer
            case .creating:  creatingBlob
            }

            closeButton
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: phase)
    }

    // MARK: - States

    /// The one affordance on an otherwise blank canvas — the whole discoverability of the home.
    private var idleHint: some View {
        AnimatedGradientRevealText(text: "tap anywhere to begin", maxDuration: 1.2, settledOpacity: 0.35)
            .font(Theme.dmSans(16, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .allowsHitTesting(false)
    }

    /// Centered writing surface: a calm blob focal point above a centered field. Return commits.
    private var composer: some View {
        VStack(spacing: 24) {
            CreatingFilBlobView()
                .frame(width: 76, height: 76)
                .opacity(0.9)

            TextField("", text: $text, axis: .vertical)
                .font(Theme.dmSans(20, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1...6)
                .focused($fieldFocused)
                .submitLabel(.return)
                .padding(.horizontal, 32)
                .overlay(alignment: .center) {
                    if text.isEmpty {
                        Text("let a thought be")
                            .font(Theme.dmSans(20, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .allowsHitTesting(false)
                    }
                }
                .onSubmit { Task { await createFil() } }

            Button(action: { Task { await createFil() } }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 40, height: 40)
                    .background(Theme.primaryText, in: Circle())
                    .opacity(hasText ? 1 : 0.3)
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
        }
        .padding(.bottom, 80)
        .transition(.opacity)
    }

    private var creatingBlob: some View {
        CreatingFilBlobView()
            .frame(width: 130, height: 130)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button("close") { dismiss() }
                    .font(Theme.dmSans(14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Logic

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func onCanvasTap() {
        switch phase {
        case .idle:
            phase = .composing
            fieldFocused = true
        case .composing:
            // Tapping the canvas while composing dismisses the keyboard; if nothing was written,
            // fall back to blank so the canvas is never stuck in an empty composing state.
            fieldFocused = false
            if !hasText { phase = .idle }
        case .creating:
            break
        }
    }

    private func createFil() async {
        let thought = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty else { return }

        text = ""
        fieldFocused = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .creating }
        SoundscapeManager.shared.startMeshDuringProcessSound()

        let title = await ArticleGenerationService.shared.generateTitle(from: thought)
        let gradient = Theme.randomGradientPair()
        let note = Note(
            title: title,
            transcript: thought,
            keyword: title,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        modelContext.insert(note)
        modelContext.saveOrLog()

        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound()

        // Let the blob breathe for a beat as the fil "forms", then return to the blank canvas.
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .idle }
    }
}
