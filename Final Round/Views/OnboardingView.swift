import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    
    private let accent = AppTheme.accent
    
    private let pages = [
        OnboardingPage(
            icon: "video.circle.fill",
            title: "Real-Time Analysis",
            description: "Get instant feedback on your facial expressions, eye contact, and body language during practice interviews"
        ),
        OnboardingPage(
            icon: "waveform.circle.fill",
            title: "Speaking Analysis",
            description: "Track your speaking pace, detect filler words, and analyze voice confidence patterns"
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "100% Private",
            description: "All AI processing happens on your device. Your interviews never leave your phone"
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            title: "Track Progress",
            description: "Monitor your improvement over time with detailed analytics and personalized insights"
        )
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [AppTheme.background, accent.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button {
                            completeOnboarding()
                        } label: {
                            Text("Skip")
                                .font(AppTheme.font(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                    
                    Spacer(minLength: 0)
                    
                    TabView(selection: $currentPage) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            OnboardingPageView(page: pages[index])
                                .tag(index)
                                .padding(.horizontal, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Capsule()
                                .fill(currentPage == index ? accent : accent.opacity(0.3))
                                .frame(width: currentPage == index ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 160)
            }
            .interactiveDismissDisabled()
            .safeAreaInset(edge: .bottom) {
                BottomActionBar(showsSeparator: false) {
                    Button {
                        if currentPage < pages.count - 1 {
                            currentPage += 1
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if currentPage > 0 {
                        Button {
                            currentPage -= 1
                        } label: {
                            Text("Previous")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }
    
    private func completeOnboarding() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [appState] in
            appState.hasCompletedOnboarding = true
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: page.icon)
                .font(AppTheme.font(size: 100))
                .foregroundStyle(AppTheme.accent)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(AppTheme.font(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(page.description)
                    .font(AppTheme.font(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
