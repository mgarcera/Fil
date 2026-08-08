import SwiftUI

// PREVIEW-ONLY specimen for the bundled Fredoka font. Open the Xcode canvas to see it; not wired
// into the app. Delete once we've decided where (if anywhere) Fredoka is used.

#Preview("Fredoka specimen") {
    ScrollView {
        VStack(alignment: .leading, spacing: 26) {
            // Weights
            VStack(alignment: .leading, spacing: 8) {
                label("Weights")
                Text("Light — a quiet thought").font(Theme.fredoka(22, weight: .light))
                Text("Regular — a quiet thought").font(Theme.fredoka(22, weight: .regular))
                Text("Medium — a quiet thought").font(Theme.fredoka(22, weight: .medium))
                Text("SemiBold — a quiet thought").font(Theme.fredoka(22, weight: .semibold))
                Text("Bold — a quiet thought").font(Theme.fredoka(22, weight: .bold))
            }
            .foregroundStyle(Theme.primaryText)

            Divider().overlay(Theme.divider)

            // How it might read as a display face vs. the current Instrument Serif
            VStack(alignment: .leading, spacing: 10) {
                label("Display comparison")
                Text("Folders").font(Theme.instrumentSerif(30)).foregroundStyle(Theme.primaryText)
                Text("Instrument Serif (current)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                Text("Folders").font(Theme.fredoka(30, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text("Fredoka SemiBold").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            }

            Divider().overlay(Theme.divider)

            // On a gradient card (matches the new fil card treatment)
            VStack(alignment: .leading, spacing: 10) {
                label("On a fil card")
                cardSample("Call the framer back about the hallway prints", "#33BF99", "#408CD9")
                cardSample("gift idea: cyanotype kit", "#6659CC", "#E8196A")
            }

            Divider().overlay(Theme.divider)

            // Body-copy legibility
            VStack(alignment: .leading, spacing: 10) {
                label("Body copy")
                Text("The rounded terminals give Fredoka a warm, approachable feel. Here's a longer run of text at a reading size to judge rhythm and legibility across a few lines.")
                    .font(Theme.fredoka(15, weight: .regular))
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .padding(20)
    }
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

private func label(_ text: String) -> some View {
    Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
}

private func cardSample(_ text: String, _ start: String, _ end: String) -> some View {
    HStack(spacing: 14) {
        Text(text)
            .font(Theme.fredoka(15, weight: .regular))
            .foregroundStyle(Theme.primaryText)
            .lineLimit(2)
        Spacer(minLength: 0)
    }
    .padding(.vertical, 12).padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.gradient(startHex: start, endHex: end))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
}
