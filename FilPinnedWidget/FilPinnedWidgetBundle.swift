//
//  FilPinnedWidgetBundle.swift
//  FilPinnedWidget
//
//  Created by Mason Garcera on 6/30/26.
//

import WidgetKit
import SwiftUI

@main
struct FilPinnedWidgetBundle: WidgetBundle {
    var body: some Widget {
        FilPinnedWidget()
        FilPinnedWidgetControl()
        FilPinnedWidgetLiveActivity()
    }
}
