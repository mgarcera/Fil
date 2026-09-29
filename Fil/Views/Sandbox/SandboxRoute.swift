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

    @State private var study: Study = .pagedHome
    @State private var variant: String = "none"
    /// A second, independent axis. Two open questions at once is the normal case in a refinement
    /// loop, and folding them into one key gives you nine combinations and no way to read a
    /// verdict.
    @State private var variantB: String = "transport"
    @State private var forcedScheme: ColorScheme?
    @State private var stressed = false

    enum Study: String, CaseIterable, Identifiable {
        case pagedHome = "Paged home"
        var id: String { rawValue }

        /// Axis one: does a thought sit on a plate, or straight on the ground?
        ///
        /// The reference Mason brought on 2026-09-28 has no plates at all — white text directly on
        /// a dark ground — and ours is the inverse. "mixed" splits it: prose on the ground, objects
        /// on a plate.
        var variants: [(key: String, label: String)] {
            switch self {
            case .pagedHome:
                // Settled 2026-09-28: no plates. White straight on the ground, as in the reference.
                []
            }
        }

        /// Axis two: what the bottom bar carries beyond the transport.
        var variantsB: [(key: String, label: String)] {
            switch self {
            case .pagedHome:
                // Settled: the bar carries the transport and nothing else.
                []
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch study {
                case .pagedHome:
                    PagedHomeStudy(variant: variant, bar: variantB, stressed: stressed)
                }
            }
            .ignoresSafeArea()

            controls
        }
        .preferredColorScheme(forcedScheme)
        .onChange(of: study) { _, new in
            variant = new.variants.first?.key ?? ""
            variantB = new.variantsB.first?.key ?? ""
        }
    }

    /// Pinned to the top on a blurred capsule, because a study whose variants each fill the screen
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
        .padding(.top, 6)
    }

    /// One axis of the switcher. Split out because the row is now two axes plus four utilities,
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
