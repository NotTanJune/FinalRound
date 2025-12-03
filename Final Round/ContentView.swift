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
                WelcomeView()
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
    ContentView()
        .environmentObject(AppState())
}
