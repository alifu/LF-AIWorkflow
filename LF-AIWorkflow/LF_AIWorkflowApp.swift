//
//  LF_AIWorkflowApp.swift
//  LF-AIWorkflow
//
//  Created by Alif Ramadhoni on 27/10/26.
//

import SwiftUI

@main
struct LF_AIWorkflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app (LSUIElement): no window opens at launch; the notch panel is created by AppDelegate.
        Settings {
            ThemedRoot(settings: AppComposition.settings) {
                SettingsView(settings: AppComposition.settings)
            }
        }
    }
}
