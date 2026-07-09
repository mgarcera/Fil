import Foundation

/// Encrypts user files at rest so they're unreadable while the device is locked (decryptable only
/// after the user unlocks). Applied to the SwiftData store and the audio/video files in the app's
/// document directory.
///
/// Scope is deliberately the app container only. The App Group snapshot the lock-screen widget reads
/// is left at its default protection so the widget can still render while the device is locked.
enum FileProtection {
    static func protectAtRest(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }
}
