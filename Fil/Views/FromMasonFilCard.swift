import SwiftUI

struct FromMasonFilCard: View {
    private static let bodyText = """
    fil is not a project management tool, productivity app, second brain, or journal. it has no:

    - inbox
    - templates
    - tags
    - folders
    - dashboards
    - streaks
    - reminders
    - graphs
    - daily notes
    - due dates
    - priority levels
    - integrations
    - workspaces

    it doesn't want to systematize you, make you more efficient, or understand your mood trends. optimization culture has plenty of us believing that our thoughts are only valuable if they're organized, tagged, linked, and actionable.

    some thoughts are just thoughts. some moments are just moments. these things don't need to become a project or goal in a database. they just need to exist somewhere. fil is that place.

    it doesn't ask you to be consistent. it doesn't have premade frameworks you have to adapt to. it has zero opinion on how you should organize or scaffold yourself.

    instead, it adapts to you in the simplest way: listening. fil learning your voice and reflecting it back to you is the deepest possible expression of this product philosophy because it refuses to impose a style on you. its style is your style. or at least as close to it as it can get.
    
    thoughts also aren't two-dimensional. they're aren't on a flat x/y-axis. fil thinks about the z-axis, the third dimension, because thoughts are rich with depth. using the fil'ament feature, you can highlight even a single word and attach an infinite amount of contexts to it. take "i went to the beach with my family" for example. the word "beach" can mean many things to you; fil helps you add meaning to it. the word "family" might mean differently, so add to it differently. 

    fil is free and unmonetized. there's nothing to sell. no tier to upgrade to. no features behind a paywall. i made it and didn't want to charge you for it because on-device ai is something we've already paid for. fil scales so long as you have apple intelligence. 
    
    (now if you have any desire to tip me, that's different. won't say no to that! an investment in me is an investment into r&d for fil.)
    
    share with it the things you to do for work, school, anything really, and you might be surprised at how much optimization you didn't need. 

    i hope you'll find as much ful*fil*ment and fun in its simplicity as i do :) and if this becomes part of your stack, let me know. i don't have social media (on purpose) but i do love a good email. 
    """

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            FromMasonFilBackdrop()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("from mason")
                        .font(Theme.dmSans(9, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(Theme.primaryText.opacity(0.5), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                    Text(Self.bodyText)
                        .font(Theme.dmSans(15, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct FromMasonFilBackdrop: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0.0, 0.0), SIMD2(0.5, 0.0), SIMD2(1.0, 0.0),
                SIMD2(0.0, 0.45), SIMD2(0.5, 0.5), SIMD2(1.0, 0.55),
                SIMD2(0.0, 1.0), SIMD2(0.45, 1.0), SIMD2(1.0, 1.0)
            ],
            colors: [
                Color(hex: "#F7B2C8").opacity(0.28), Color(hex: "#F2BC79").opacity(0.22), Color(hex: "#F7B2C8").opacity(0.18),
                Color(hex: "#F2BC79").opacity(0.18), Color(hex: "#B9D8F6").opacity(0.2), Color(hex: "#F2BC79").opacity(0.16),
                Color(hex: "#B9D8F6").opacity(0.14), Color(hex: "#F7B2C8").opacity(0.16), Color.clear
            ],
            smoothsColors: true
        )
        .blur(radius: 14)
        .scaleEffect(1.12)
        .allowsHitTesting(false)
    }
}
