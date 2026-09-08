import SwiftUI

/// A benefit-framed screen shown *before* the first microphone/speech system prompt, so the user
/// understands why fil asks — and that typing is always an option — instead of getting a cold OS
/// dialog on their first record tap. Priming this way keeps the core feature from being denied on
/// reflex (a denial is permanent and can only be undone in Settings).
///
/// **Guideline 5.1.1(iv) constraints — do not reintroduce what was removed here.** Apple rejected
/// 1.0 (4) over this sheet. A pre-permission message may inform, but it may not gate:
/// - The button may not say "Enable" (or "Allow", "OK", "Turn On"). Apple names "Continue" and
///   "Next" as acceptable. The word must not imply the user is granting anything here.
/// - There must be no way to leave this sheet without reaching the system prompt. The old
///   "Not now" button, and swipe-to-dismiss, both let the user out early; the caller now sets
///   `.interactiveDismissDisabled()` for the same reason.
///
/// Declining stays available where Apple wants it: the system prompt itself. Typing stays
/// available because this sheet only appears on a deliberate record tap.
struct MicPrimingSheet: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 8)

            Text("Talk to Fil")
                .font(Theme.dmSans(22, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Text("Fil turns what you say into a titled note — right on your device. To record, it needs your microphone and speech recognition. You can always just type instead.")
                .font(Theme.dmSans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onContinue) {
                Text("Continue")
                    .font(Theme.dmSans(16, weight: .semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.primaryText, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
