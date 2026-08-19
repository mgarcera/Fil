import Foundation

/// Content for the one-time "from mason" seed fil, revealed after a new user creates their own
/// first fil. Fixed (no AI generation) so it always renders perfectly — even where on-device
/// intelligence is unavailable. Edit freely: this is the founder's welcome, in Mason's voice.
enum WelcomeFil {
    static let title = "from mason"
    static let gradientStart = "#408CD9"   // ocean blue
    static let gradientEnd = "#6659CC"     // indigo

    static let transcript = """
    Hi, I'm Mason, the maker of Fil (Click me!).

    Congrats on adding your first thought! This one's mine that I wanted to leave for you.

    I made Fil because I wanted a fun place to put thoughts that lets me stay organized without turning it all into one gigantic system. Keeping track of thoughts can get messy, but at least Fil makes it a beautiful mess. 

    Tap a word to attach a filament. It's a powerful feature that you can use in an infinite number of ways. Like here for example!

    You'll be up and running in no time. If you have any questions or comments, you can find the feedback form in Settings > Open feedback form. Happy filling!
    """

    // Sample filaments — each keyword appears in the transcript, so they highlight + are tappable.
    //
    // No "(Click me!)" on these titles. By the time a filament title is on screen the gesture has
    // already been performed — the prompt belongs on the first invitation only, which is the
    // transcript's opening line (Note.titleLine renders it as the card's title on the canvas).
    static let filamentKeyword = "filament"
    static let filamentNoteTitle = "What's a filament?"
    static let filamentNote = "Filament: A thin, thread-like object, fiber, or wire. Comes from the Latin word filum, meaning thread. Here, it's a way for you to thread thoughts into your thoughts! Cool huh? Just long tap a word and press filament to do it."

    /// The "here" filament — a stack of getting-started notes.
    ///
    /// These used to hang off a "tips" keyword, which never appeared in the transcript, so nothing
    /// highlighted and no one could open them. "here" is in the text, which is what makes them
    /// reachable. Any keyword added below must exist in `transcript` or it attaches to nothing.
    static let exampleKeyword = "here"

    static let voiceNoteTitle = "No need to type"
    static let voiceNote = "Press the microphone button from the menu and you can just talk. I say most of my thoughts out loud."

    static let linksNoteTitle = "Links"
    static let linksNote = "Paste or type a link and it formats automatically."

    static let searchNoteTitle = "Finding Thoughts Later"
    static let searchNote = "Tap search to look back through your thoughts. Fil Extra lets you ask in your own words and finds them with better detail."

    static let landfilNoteTitle = "The Landfil"
    static let landfilNote = "When you're ready to let go of your thoughts, send them to the landfil (trash)."

    static let signoffNoteTitle = "One last thing"
    static let signoffNote = "As you use the app, please let me know how Fil goes for you. You can submit feedback anytime in Settings > About > Open feedback form."
}
