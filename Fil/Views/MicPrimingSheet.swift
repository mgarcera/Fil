import SwiftUI

/// A benefit-framed screen shown *before* the first microphone/speech system prompt, so the user
/// understands why fil asks — and that typing is always an option — instead of getting a cold OS
/// dialog on their first record tap. Priming this way keeps the core feature from being denied on
/// reflex (a denial is permanent and can only be undone in Settings).
struct MicPrimingSheet: View {
    let onEnable: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 8)

            Text("talk to fil")
                .font(Theme.dmSans(22, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Text("fil turns what you say into a titled note — right on your device. to record, it needs your microphone and speech recognition. you can always just type instead.")
                .font(Theme.dmSans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button(action: onEnable) {
                    Text("enable")
                        .font(Theme.dmSans(16, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.primaryText, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onNotNow) {
                    Text("not now")
                        .font(Theme.dmSans(15, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
