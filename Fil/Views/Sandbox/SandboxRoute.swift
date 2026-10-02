#if DEBUG
import SwiftUI
import SwiftData

/// The design sandbox: one route, mounted from Settings under `#if DEBUG`, that renders whichever
/// study is active against the app's own fonts, colours, components and data.
///
/// **Why it lives in the app.** A variant judged in a mock-up is a verdict on the mock-up. In here
/// `Theme`, `PinnedFolderHero`, `BlobShape` and the real `@Query` results are already in scope, so
/// a study cannot accidentally be reviewing a copy of Fil.
///
/// **The route is the asset; a study is disposable.** This file is built once and kept. Each study
/// is a fresh file holding one component's variants, deleted whole when its verdict lands — the
/// losing variants go to `archive/<date>-<slug>/` first, because a diff records what the winner
/// became and never what the losers looked like.
///
/// It ships in Debug only. Nothing here is reachable in a Release build, so a study left mounted
/// cannot reach TestFlight.
struct SandboxRoute: View {
    @Environment(\.dismiss) private var dismiss
    /// The real scheme, read HERE because this is the last place it is true: the studies force
    /// dark for their glass and force light back inside each bubble, so nothing below can ask.
    @Environment(\.colorScheme) private var systemScheme

    @State private var study: Study = .pagedHome
    @State private var variant: String = ""
    /// A second, independent axis. Two open questions at once is the normal case in a refinement
    /// loop, and folding them into one key gives you nine combinations and no way to read a
    /// verdict.
    @State private var variantB: String = ""
    @State private var forcedScheme: ColorScheme?
    @State private var stressed = false

    enum Study: String, CaseIterable, Identifiable {
        case pagedHome = "Paged home"
        var id: String { rawValue }

        /// Axis one: free.
        ///
        /// The reference Mason brought on 2026-09-28 has no plates at all — white text directly on
        /// a dark ground — and ours is the inverse. "mixed" splits it: prose on the ground, objects
        /// on a plate.
        var variants: [(key: String, label: String)] {
            switch self {
            case .pagedHome:
                // Bubbles settled as glass on 2026-10-01. The axis now carries how a thought's
                // filaments show: its attached keywords lit inside the text, as FilCard does,
                // or as chips beneath it.
                // Settled 2026-10-01: the summary's voice is casual lowercase texting, no
                // greetings. Warm lost. (Lit words settled the same day as a yellow band.)
                []
            }
        }

        /// Axis two: free. Last carried the cover setups (settled 2026-09-30: Editorial's
        /// structure with Plate's face — the losers are in archive/2026-09-28-paged-home/), and
        /// before that the composer (settled 09-29, archive/2026-09-29-nest-composer/).
        var variantsB: [(key: String, label: String)] {
            switch self {
            case .pagedHome:
                // Settled 2026-10-01: the dock and back control stay glass — "glass looks best"
                // against paper bubbles. Paper and line art lost.
                []
            }
        }
    }

    var body: some View {
        // Read here, above the ignoring: this is the only place the home indicator's inset is
        // still visible. The pager ignores it so pages run full height, and the composer adds it
        // back on its own.
        GeometryReader { geo in
        ZStack(alignment: .bottom) {
            Group {
                switch study {
                case .pagedHome:
                    PagedHomeStudy(variant: variant, line: variantB, stressed: stressed)
                }
            }
            // `.container` only. The bare form also ignores the KEYBOARD region, and that is
            // what broke the composer: nothing below here could be raised by the keyboard, so
            // the study reconstructed the lift by hand from a notification, through three
            // container layers, and it came out as height rather than translation.
            //
            // All container edges, so pages are full height and stack with no seam. Respecting
            // the bottom made every page 34pt short and the outer gradient showed in the gap
            // under a cover. The composer gets the inset back through `homeInset`.
            .ignoresSafeArea(.container)

            controls
        }
        .preferredColorScheme(forcedScheme)
        .environment(\.homeInset, geo.safeAreaInsets.bottom)
        // Which way the paper prints. The sun/moon utility already here is the override, so both
        // printings can be judged without a trip to Settings; nil means follow the phone.
        .environment(\.paperScheme, forcedScheme ?? systemScheme)
        }
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .onChange(of: study) { _, new in
            variant = new.variants.first?.key ?? ""
            variantB = new.variantsB.first?.key ?? ""
        }
    }

    /// Pinned to the BOTTOM on a blurred capsule, above the home indicator — the top is where the
    /// cover's title and the nest's back control live now (moved 2026-09-30). Originally pinned to the top because a study whose variants each fill the screen
    /// puts its own controls out of reach — and then two of three variants get judged in whatever
    /// state the buttons were last left in.
    private var controls: some View {
        HStack(spacing: 6) {
            chips(study.variants, selected: variant) { variant = $0 }
            Divider().frame(height: 16)
            chips(study.variantsB, selected: variantB) { variantB = $0 }
            Divider().frame(height: 16)
            utilities
        }
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.divider, lineWidth: 0.5))
        .padding(.bottom, 6)
    }

    /// One axis of the switcher. Split out because the row is now two axes plus three utilities,
    /// and as one expression the type checker gives up on it.
    private func chips(_ items: [(key: String, label: String)],
                       selected: String,
                       pick: @escaping (String) -> Void) -> some View {
        ForEach(items, id: \.key) { item in
            Button(item.label) { pick(item.key) }
                .font(Theme.dmMono(11, weight: selected == item.key ? .bold : .regular))
                .foregroundStyle(selected == item.key ? Theme.primaryText : Theme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(selected == item.key ? Theme.cardBackground : .clear, in: Capsule())
        }
    }

    @ViewBuilder private var utilities: some View {
        Button {
            forcedScheme = forcedScheme == .dark ? .light : (forcedScheme == .light ? nil : .dark)
        } label: {
            Image(systemName: forcedScheme == .dark ? "moon.fill"
                            : forcedScheme == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                .font(.system(size: 12))
        }
        // The hard case is a library with more folders than pages anyone wants to page through.
        Button { stressed.toggle() } label: {
            Image(systemName: stressed ? "square.grid.3x3.fill" : "square.grid.2x2")
                .font(.system(size: 12))
        }
        Divider().frame(height: 16)
        Button("Done") { dismiss() }
            .font(Theme.dmMono(11, weight: .medium))
    }

}
#endif
