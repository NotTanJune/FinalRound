//
//  ContentView.swift
//  Final Round
//
//  Created by Tanmay Nargas on 23/11/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Group {
            if appState.isCheckingProfile || appState.showMinimumLoadingAnimation {
                // Show animated splash screen while checking auth state or during transitions
                SplashLoadingView()
            } else if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else if !appState.isLoggedIn {
                // Go directly to LoginView after onboarding to avoid flash
                LoginView()
            } else if !appState.hasProfileSetup {
                ProfileSetupView()
            } else {
                MainTabView()
                // Removed .id(appState.selectedTab) to prevent view recreation
                // Tab state is managed by appState.selectedTab binding
            }
        }
    }
}

#Preview {
    let appState = AppState()
    return ContentView()
        .environmentObject(appState)
        .environmentObject(appState.tutorialManager)
}
