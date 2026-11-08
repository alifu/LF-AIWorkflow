//
//  ThemeEnvironment.swift
//  LF-AIWorkflow
//

import SwiftUI

extension EnvironmentValues {
    /// The active theme; injected by `ThemedRoot` into both the panel and the Settings tree.
    @Entry var appTheme: AppTheme = .classic
}
