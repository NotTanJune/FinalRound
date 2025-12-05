import SwiftUI

struct SplashLoadingView: View {
    @State private var isAnimating = false
    @State private var showDot1 = false
    @State private var showDot2 = false
    @State private var showDot3 = false
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // App name with animated effect
                HStack(spacing: 8) {
                    // "Final" text
                    Text("Final")
                        .font(AppTheme.font(size: 48, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    // "Round" text with accent color
                    Text("Round")
                        .font(AppTheme.font(size: 48, weight: .bold))
                        .foregroundStyle(AppTheme.primary)
                }
                .scaleEffect(isAnimating ? 1.0 : 0.9)
                .opacity(isAnimating ? 1 : 0.7)
                
                // Loading dots
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 10, height: 10)
                        .scaleEffect(showDot1 ? 1.0 : 0.5)
                        .opacity(showDot1 ? 1 : 0.3)
                    
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 10, height: 10)
                        .scaleEffect(showDot2 ? 1.0 : 0.5)
                        .opacity(showDot2 ? 1 : 0.3)
                    
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 10, height: 10)
                        .scaleEffect(showDot3 ? 1.0 : 0.5)
                        .opacity(showDot3 ? 1 : 0.3)
                }
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Main text breathing animation
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            isAnimating = true
        }
        
        // Staggered dot animations
        animateDots()
    }
    
    private func animateDots() {
        // Create a looping sequence for the dots
        let dotDuration = 0.4
        let totalCycleDuration = dotDuration * 4
        
        // Initial animation
        withAnimation(.easeInOut(duration: dotDuration)) {
            showDot1 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + dotDuration) {
            withAnimation(.easeInOut(duration: dotDuration)) {
                showDot2 = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + dotDuration * 2) {
            withAnimation(.easeInOut(duration: dotDuration)) {
                showDot3 = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + dotDuration * 3) {
            withAnimation(.easeInOut(duration: dotDuration)) {
                showDot1 = false
                showDot2 = false
                showDot3 = false
            }
        }
        
        // Loop the animation
        DispatchQueue.main.asyncAfter(deadline: .now() + totalCycleDuration) {
            animateDots()
        }
    }
}

#Preview {
    SplashLoadingView()
}

