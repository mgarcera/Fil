import Foundation

/// Content for the one-time "from mason" seed fil, revealed after a new user creates their own
/// first fil. Fixed (no AI generation) so it always renders perfectly — even where on-device
/// intelligence is unavailable. Edit freely: this is the founder's welcome, in Mason's voice.
enum WelcomeFil {
    static let title = "from mason"
    static let gradientStart = "#408CD9"   // ocean blue
    static let gradientEnd = "#6659CC"     // indigo

    static let transcript = """
    hi, i'm mason, the maker of fil.

    congrats on making your first one! this one's mine!

    i wanted a place to put thoughts without turning it into a project. no inbox, tags, streaks, or anything like that. just a cool place for them to be.

    tap a word to attach a filament. it's a powerful feature that you can use in an infinite number of ways. like here for example!

    follow these tips and you'll be up and running in the next few minutes!
    """

    // Sample filaments — each keyword appears in the transcript, so they highlight + are tappable.
    static let filamentKeyword = "filament"
    static let filamentNoteTitle = "what's a filament?"
    static let filamentNote = "a filament is something you attach to a word to give it depth."

    // The "here" filament — the word highlights and opens a tutorial video (bundled in Resources,
    // copied into the documents dir at seed time).
    static let exampleKeyword = "here"
    static let exampleVideoResource = "Intro"
    static let exampleVideoExtension = "mp4"

    // The "tips" filament — a small stack of getting-started notes.
    // (Draft copy in Mason's voice; add rich content later.)
    static let tipsKeyword = "tips"

    static let voiceNoteTitle = "no need to type"
    static let voiceNote = "press \"record voice\" from the menu and you can just talk. i say most of my thoughts out loud."
    /// Screenshot of the composer's capture menu, shown beside the voice note (bundled resource).
    static let voiceTipImageResource = "voice-and-photo"
    static let voiceTipImageExtension = "webp"

    static let linksNoteTitle = "links"
    static let linksNote = "paste or type a link and it turns into a fil with the page's title and a preview, ready for when you come back to it."

    static let searchNoteTitle = "finding it later"
    static let searchNote = "tap search at the top to look back through your thoughts. fil pro lets you ask in your own words and finds what you meant."

    static let landfilNoteTitle = "the landfil"
    static let landfilNote = "when you're ready to let go of your thoughts, send them to the landfil (trash)."

    static let signoffNoteTitle = "one last thing"
    static let signoffNote = "let me know how deoptimizing goes for you :)"
}
