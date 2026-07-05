import SwiftUI

struct FromMasonFilCard: View {
    private static let bodyText = """
    fil is not a: 
    
    project management tool
    productivity app
    second brain
    journal 
    
    it has no:

    - inbox
    - templates
    - tags
    - folders
    - dashboards
    - streaks
    - reminders
    - graphs or charts
    - due dates
    - priority levels
    - integrations
    - mood tracking
    - workspaces

    it doesn't want to systematize you, make you more efficient, or understand your trends
    
    optimization culture makes us believe that our thoughts are only valuable if they're organized, tagged, linked, and actionable

    some thoughts are just thoughts
    
    some moments are just moments
    
    some things don't need to become a project or goal in a database
    
    they just need to exist 
    
    fil doesn't ask you to be consistent 
    
    fil doesn't have premade frameworks you have to adapt to 
    
    fil has zero opinion on how you should organize or scaffold yourself
    
    fil the things you to do for work, school, life, and you might be surprised at how much optimization you didn't need

    i hope you'll find as much ful*fil*ment and fun as i do 
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
