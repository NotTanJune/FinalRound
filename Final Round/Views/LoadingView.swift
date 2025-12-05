import SwiftUI
import Lottie

struct LoadingView: View {
    var message: String = "Loading..."
    var size: CGFloat = 150
    
    var body: some View {
        VStack(spacing: 24) {
            LottieView(animation: .named("Loading"))
                .playing(loopMode: .loop)
                .animationSpeed(1.0)
                .frame(width: size, height: size)
            
            Text(message)
                .font(AppTheme.font(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

#Preview {
    LoadingView()
}
