import Foundation

/// Content for the one-time "from mason" seed fil, revealed after a new user creates their own
/// first fil. Fixed (no AI generation) so it always renders perfectly — even where on-device
/// intelligence is unavailable. Edit freely: this is the founder's welcome, in Mason's voice.
enum WelcomeFil {
    static let title = "from mason"
    static let gradientStart = "#408CD9"   // ocean blue
    static let gradientEnd = "#6659CC"     // indigo

    static let transcript = """
    Hi, I'm Mason, the maker of Fil.

    Congrats on making your first one! This one's mine!

    I wanted a fun place to put thoughts that lets me stay organized without turning it all into gigantic system. 

    Tap a word to attach a Filament. Tt's a powerful feature that you can use in an infinite number of ways. Like here for example!

    Follow these tips and you'll be up and running in no time!
    """

    // Sample filaments — each keyword appears in the transcript, so they highlight + are tappable.
    static let filamentKeyword = "filament"
    static let filamentNoteTitle = "What's a filament?"
    static let filamentNote = "A filament is a thin, thread-like object, fiber, or wire. The word comes from the Latin word filum, meaning thread. Here, it's a way for you to thread meta-thoughts into your main thoughts!"

    // The "here" filament — the word highlights and opens a tutorial video (bundled in Resources,
    // copied into the documents dir at seed time).
    static let exampleKeyword = "here"
    static let exampleVideoResource = "Intro"
    static let exampleVideoExtension = "mp4"

    // The "tips" filament — a small stack of getting-started notes.
    // (Draft copy in Mason's voice; add rich content later.)
    static let tipsKeyword = "tips"

    static let voiceNoteTitle = "No need to type"
    static let voiceNote = "Press the microphone button from the menu and you can just talk. I say most of my thoughts out loud."
    /// Screenshot of the composer's capture menu, shown beside the voice note (bundled resource).
    static let voiceTipImageResource = "voice-and-photo"
    static let voiceTipImageExtension = "webp"

    static let linksNoteTitle = "Links"
    static let linksNote = "Paste or type a link and it formats automatically, ready for whenever you come back to it."

    static let searchNoteTitle = "Finding It Later"
    static let searchNote = "Tap search to look back through your thoughts. Fil Pro lets you ask in your own words and finds past thoughts with better detail."

    static let landfilNoteTitle = "The Landfil"
    static let landfilNote = "when you're ready to let go of your thoughts, send them to the landfil (trash)."

    static let signoffNoteTitle = "One last thing"
    static let signoffNote = "Let me know how Fil goes for you! :)"
}
