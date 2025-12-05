import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLogin = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer().frame(height: 20)
                heroSection
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                BottomActionBar(showsSeparator: false) {
                    Button {
                        showLogin = true
                    } label: {
                        Text("Continue to Sign In")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .fullScreenCover(isPresented: $showLogin) {
                LoginView()
            }
            .onAppear {
                // For returning users (who have completed onboarding), skip welcome and go directly to login
                if appState.hasCompletedOnboarding {
                    showLogin = true
                }
            }
        }
    }
    
    private var heroSection: some View {
        VStack(spacing: 32) {
            Image("splash_interview")
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            
            Text("Final Round")
                .font(AppTheme.font(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
}

#Preview {
    WelcomeView()
        .environmentObject(AppState())
}
