//
//  FilCaptureControlIntents.swift
//
//  Shared by the app AND the widget extension (Target Membership must include BOTH — the system
//  requires that for a control to open the app). Conforms to OpenIntent, which is what actually
//  launches the app from a Control Center control; perform() stamps a pending-capture flag in the
//  shared app group that the app drains on foreground (ContentView.drainPendingCapture).
//

import AppIntents
import Foundation

/// Which capture the control should trigger on open.
enum FilCaptureTarget: String, AppEnum {
    case voice
    case compose

    static let typeDisplayRepresentation = TypeDisplayRepresentation("Fil capture")
    static let caseDisplayRepresentations: [FilCaptureTarget: DisplayRepresentation] = [
        .voice: "Record in fil",
        .compose: "Write in fil"
    ]
}

/// App-group signalling for the capture controls.
nonisolated enum FilCaptureLaunch {
    static let suite = "group.com.smidgecraft.Fil"
    static let key = "pendingCapture"   // "voice" | "compose"
    static func set(_ target: FilCaptureTarget) {
        UserDefaults(suiteName: suite)?.set(target.rawValue, forKey: key)
    }
}

/// Opens Fil from a Control Center control (or the Action button), stamping which capture to start.
struct FilCaptureOpenIntent: OpenIntent {
    static let title: LocalizedStringResource = "Capture in Fil"

    @Parameter(title: "What")
    var target: FilCaptureTarget

    init() {}
    init(target: FilCaptureTarget) { self.target = target }

    func perform() async throws -> some IntentResult {
        FilCaptureLaunch.set(target)
        return .result()
    }
}
