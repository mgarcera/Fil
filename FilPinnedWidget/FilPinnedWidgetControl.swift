//
//  FilPinnedWidgetControl.swift
//  FilPinnedWidget
//
//  Two Control Center controls (also bindable to the Action Button) for one-tap capture. Both use
//  FilCaptureOpenIntent (an OpenIntent) so the control actually launches the app; see
//  FilCaptureControlIntents.swift. That intent file must be a member of BOTH the app and the widget
//  extension targets for the open to work.
//

import AppIntents
import SwiftUI
import WidgetKit

struct FilVoiceCaptureControl: ControlWidget {
    static let kind = "com.masongarcera.Fil.VoiceCaptureControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: FilCaptureOpenIntent(target: .voice)) {
                Label("Record in fil", systemImage: "mic.fill")
            }
        }
        .displayName("Record in fil")
        .description("Open Fil and start a voice note.")
    }
}

struct FilComposeCaptureControl: ControlWidget {
    static let kind = "com.masongarcera.Fil.ComposeCaptureControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: FilCaptureOpenIntent(target: .compose)) {
                Label("Write in fil", systemImage: "square.and.pencil")
            }
        }
        .displayName("Write in fil")
        .description("Open Fil ready to type a thought.")
    }
}
