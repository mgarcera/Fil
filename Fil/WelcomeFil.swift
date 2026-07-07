import Foundation

/// Content for the one-time "from mason" seed fil, revealed after a new user creates their own
/// first fil. Fixed (no AI generation) so it always renders perfectly — even where on-device
/// intelligence is unavailable. Edit freely: this is the founder's welcome, in Mason's voice.
enum WelcomeFil {
    static let title = "from mason"
    static let gradientStart = "#F24D59"   // coral
    static let gradientEnd = "#6659CC"     // indigo

    static let transcript = """
    hi — i'm mason, and i made fil.

    you just made your first fil. this one's mine.

    i wanted somewhere to put a thought without turning it into a project. no inbox, no tags, no streaks. some thoughts are just thoughts. they just need to exist.

    tap a word to attach a filament. swipe to landfil a fil when you're ready to let it go — even this one.

    i hope you find as much ful·fil·ment here as i do.
    """

    // Sample filaments — both keywords appear in the transcript, so they highlight + are tappable.
    static let filamentKeyword = "filament"
    static let filamentNote = "a filament is a little something you attach to a word — a note, photo, recording, or link. you're reading one now."

    static let landfilKeyword = "landfil"
    static let landfilNote = "landfil = letting a fil go. swipe it away anytime. nothing here asks you to keep it."
}
