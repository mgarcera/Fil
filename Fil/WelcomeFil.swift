import Foundation

/// Content for the one-time "from mason" seed fil, revealed after a new user creates their own
/// first fil. Fixed (no AI generation) so it always renders perfectly — even where on-device
/// intelligence is unavailable. Edit freely: this is the founder's welcome, in Mason's voice.
enum WelcomeFil {
    static let title = "from mason"
    static let gradientStart = "#F24D59"   // coral
    static let gradientEnd = "#6659CC"     // indigo

    static let transcript = """
    hi, i'm mason, and i made fil.

    you just made your first fil. this one's mine.

    i wanted somewhere to put thoughts without turning it into a project. no inbox, no tags, no streaks. just a fun place for them to be.

    tap a word to attach a filament. long press to send thoughts to the landfil when you're ready to let it go. even this one.

    i hope you find as much ful·fil·ment here as i do.
    """

    // Sample filaments — both keywords appear in the transcript, so they highlight + are tappable.
    static let filamentKeyword = "filament"
    static let filamentNoteTitle = "what's a filament?"
    static let filamentNote = "a filament is something you attach to a word to give it depth."

    static let landfilKeyword = "landfil"
    static let landfilNoteTitle = "what's the landfil?"
    static let landfilNote = "landfil = trash."
}
