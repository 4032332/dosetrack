// DoseTrack/App/TabNavigator.swift
import SwiftUI

/// Shared object that lets any view switch the main tab programmatically.
final class TabNavigator: ObservableObject {
    static let shared = TabNavigator()
    @Published var selectedTab: MainTabView.Tab = .today
}
