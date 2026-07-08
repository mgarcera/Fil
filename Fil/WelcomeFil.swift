import Foundation

/// Content for the one-time "from mason" seed fil, revealed after a new user creates their own
/// first fil. Fixed (no AI generation) so it always renders perfectly — even where on-device
/// intelligence is unavailable. Edit freely: this is the founder's welcome, in Mason's voice.
enum WelcomeFil {
    static let title = "from mason"
    static let gradientStart = "#408CD9"   // ocean blue
    static let gradientEnd = "#6659CC"     // indigo

    static let transcript = """
    hi, i'm mason, and i made fil.

    you just made your first fil. this one's mine.

    i wanted somewhere to put thoughts without turning it into a project. no inbox, no tags, no streaks. just a fun place for them to be.

    tap a word to attach a filament. send thoughts to the landfil (trash) when you're ready to let them go.

    have fun deoptimizing :)
    """

    // Sample filaments — both keywords appear in the transcript, so they highlight + are tappable.
    static let filamentKeyword = "filament"
    static let filamentNoteTitle = "what's a filament?"
    static let filamentNote = "a filament is something you attach to a word to give it depth."

    // The "deoptimizing" filament — seeded so the word highlights; a video link goes here.
    static let deoptimizingKeyword = "deoptimizing"
}
