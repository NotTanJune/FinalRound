import SwiftUI

// MARK: - Tutorial Highlight Anchor Preference Key

/// Preference key for collecting tutorial highlight anchors
struct TutorialHighlightAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Tutorial Highlight Frame Preference Key (Legacy support)

/// Preference key for collecting tutorial highlight frames
struct TutorialHighlightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Tutorial Highlight Modifier

/// Modifier to mark a view as a tutorial highlight target using anchor preferences
struct TutorialHighlight: ViewModifier {
    let id: String
    
    func body(content: Content) -> some View {
        content
            .anchorPreference(key: TutorialHighlightAnchorKey.self, value: .bounds) { anchor in
                [id: anchor]
            }
    }
}

extension View {
    /// Marks this view as a tutorial highlight target with the given ID
    func tutorialHighlight(_ id: String) -> some View {
        modifier(TutorialHighlight(id: id))
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tutorial Wrapper View

/// A wrapper view that handles tutorial overlay for a specific screen
struct TutorialWrapper<Content: View>: View {
    @EnvironmentObject var tutorialManager: TutorialManager
    let tutorialType: TutorialManager.TutorialType
    let content: Content
    
    init(
        tutorialType: TutorialManager.TutorialType,
        @ViewBuilder content: () -> Content
    ) {
        self.tutorialType = tutorialType
        self.content = content()
    }
    
    var body: some View {
        content
            .overlayPreferenceValue(TutorialHighlightAnchorKey.self) { anchors in
                // Tutorial overlay - shown when this tutorial is active
                // Uses GeometryReader internally, so anchors resolve correctly
                if tutorialManager.activeTutorial == tutorialType {
                    GeometryReader { geometry in
                        TutorialOverlayContent(
                            anchors: anchors,
                            geometry: geometry
                        )
                    }
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
    }
}

/// Internal view that renders the tutorial overlay with resolved anchors
private struct TutorialOverlayContent: View {
    @EnvironmentObject var tutorialManager: TutorialManager
    let anchors: [String: Anchor<CGRect>]
    let geometry: GeometryProxy
    
    private var currentStep: TutorialStep? {
        tutorialManager.currentStep
    }
    
    @State private var tooltipSize: CGSize = .zero
    
    /// Returns the highlight frame for the current step
    private var highlightFrame: CGRect? {
        guard let step = currentStep,
              let targetId = step.targetElementId,
              let anchor = anchors[targetId] else {
            return nil
        }
        let frame = geometry[anchor]
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame.insetBy(dx: -step.highlightPadding, dy: -step.highlightPadding)
    }
    
    var body: some View {
        let screenSize = CGSize(
            width: geometry.size.width,
            height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        )
        
        ZStack {
            // Dark overlay with spotlight cutout
            spotlightOverlay(screenSize: screenSize)
            
            // Tooltip card
            if let step = currentStep {
                tooltipCard(for: step, screenSize: screenSize)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .offset(y: -geometry.safeAreaInsets.top)
    }
    
    @ViewBuilder
    private func spotlightOverlay(screenSize: CGSize) -> some View {
        if let frame = highlightFrame {
            let cornerRadius: CGFloat = min(20, min(frame.width, frame.height) / 4)
            
            // Adjust frame Y coordinate for safe area offset
            let adjustedFrame = CGRect(
                x: frame.origin.x,
                y: frame.origin.y + geometry.safeAreaInsets.top,
                width: frame.width,
                height: frame.height
            )
            
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.75))
                )
                
                context.blendMode = .destinationOut
                let spotlightPath = Path(roundedRect: adjustedFrame, cornerRadius: cornerRadius)
                context.fill(spotlightPath, with: .color(.white))
            }
            .frame(width: screenSize.width, height: screenSize.height)
            .allowsHitTesting(true)
        } else {
            Color.black.opacity(0.75)
                .allowsHitTesting(true)
        }
    }
    
    @ViewBuilder
    private func tooltipCard(for step: TutorialStep, screenSize: CGSize) -> some View {
        let safeTop = geometry.safeAreaInsets.top
        let safeBottom = geometry.safeAreaInsets.bottom
        
        // Calculate arrow offset for horizontal alignment with element
        let arrowOffset: CGFloat = {
            guard let frame = highlightFrame else { return 0 }
            let elementCenterX = frame.midX
            let tooltipCenterX = screenSize.width / 2
            let maxOffset = (screenSize.width - 40) / 2 - 30
            return min(max(elementCenterX - tooltipCenterX, -maxOffset), maxOffset)
        }()
        
        // Calculate tooltip Y position
        let tooltipY: CGFloat = {
            let tooltipHeight = tooltipSize.height > 0 ? tooltipSize.height : 200
            let arrowHeight: CGFloat = 10
            let margin: CGFloat = 16
            
            guard let frame = highlightFrame else {
                return screenSize.height / 2
            }
            
            // Adjust frame for safe area
            let adjustedFrameY = frame.origin.y + safeTop
            let adjustedFrameMaxY = adjustedFrameY + frame.height
            
            switch step.arrowDirection {
            case .up:
                // Tooltip below element
                var y = adjustedFrameMaxY + tooltipHeight / 2 + arrowHeight + margin
                if y + tooltipHeight / 2 > screenSize.height - safeBottom - margin {
                    y = adjustedFrameY - tooltipHeight / 2 - arrowHeight - margin
                }
                return y
            case .down:
                // Tooltip above element
                var y = adjustedFrameY - tooltipHeight / 2 - arrowHeight - margin
                if y - tooltipHeight / 2 < safeTop + margin {
                    y = adjustedFrameMaxY + tooltipHeight / 2 + arrowHeight + margin
                }
                return y
            case .left, .right, .none:
                return screenSize.height / 2
            }
        }()
        
        VStack(spacing: 0) {
            if step.arrowDirection == .up, highlightFrame != nil {
                Triangle()
                    .fill(Color.white)
                    .frame(width: 20, height: 10)
                    .offset(x: arrowOffset)
            }
            
            tooltipContent(for: step)
            
            if step.arrowDirection == .down, highlightFrame != nil {
                Triangle()
                    .fill(Color.white)
                    .frame(width: 20, height: 10)
                    .rotationEffect(.degrees(180))
                    .offset(x: arrowOffset)
            }
        }
        .background(
            GeometryReader { tooltipGeometry in
                Color.clear.onAppear {
                    tooltipSize = tooltipGeometry.size
                }
                .onChange(of: step.id) { _, _ in
                    tooltipSize = tooltipGeometry.size
                }
            }
        )
        .position(x: screenSize.width / 2, y: tooltipY)
    }
    
    @ViewBuilder
    private func tooltipContent(for step: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: step.icon)
                    .font(AppTheme.font(size: 24))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.lightGreen)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(AppTheme.font(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text("Step \(tutorialManager.currentStepIndex + 1) of \(tutorialManager.totalSteps)")
                        .font(AppTheme.font(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                Spacer()
            }
            
            Text(step.message)
                .font(AppTheme.font(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            if step.requiresScroll {
                HStack(spacing: 8) {
                    Image(systemName: "hand.point.up.fill")
                        .font(AppTheme.font(size: 16))
                    Text("Swipe up to continue exploring")
                        .font(AppTheme.font(size: 13, weight: .medium))
                }
                .foregroundStyle(AppTheme.primary)
                .padding(.top, 4)
            }
            
            HStack(spacing: 12) {
                Button {
                    tutorialManager.skipTutorial()
                } label: {
                    Text("Skip")
                        .font(AppTheme.font(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                
                Spacer()
                
                if !tutorialManager.isFirstStep {
                    Button {
                        tutorialManager.previousStep()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(AppTheme.font(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.lightGreen)
                            .clipShape(Circle())
                    }
                }
                
                Button {
                    if tutorialManager.isLastStep {
                        tutorialManager.completeTutorial()
                    } else {
                        tutorialManager.nextStep()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tutorialManager.isLastStep ? "Got it!" : "Next")
                            .font(AppTheme.font(size: 15, weight: .bold))
                        if !tutorialManager.isLastStep {
                            Image(systemName: "chevron.right")
                                .font(AppTheme.font(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 20)
    }
}

// MARK: - Tutorial Replay Button

/// A button to replay a specific tutorial from the Profile screen
struct TutorialReplayButton: View {
    let tutorial: TutorialManager.TutorialType
    @EnvironmentObject var tutorialManager: TutorialManager
    @EnvironmentObject var appState: AppState
    @State private var showingResetConfirmation = false
    
    private var subtitleText: String {
        switch tutorial {
        case .home:
            return "Learn about interview generation options"
        case .interviewSession:
            return "Understand the interview interface"
        case .sessionSummary:
            return "Explore your performance feedback"
        }
    }
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tutorial.icon)
                    .font(AppTheme.font(size: 18))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.lightGreen)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tutorial.displayName)
                        .font(AppTheme.font(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text(subtitleText)
                        .font(AppTheme.font(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if tutorialManager.hasCompleted(tutorial) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.font(size: 16))
                        .foregroundStyle(AppTheme.primary)
                }
                
                Image(systemName: tutorial == .home ? "play.circle.fill" : "arrow.counterclockwise.circle.fill")
                    .font(AppTheme.font(size: 20))
                    .foregroundStyle(AppTheme.primary)
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .alert("Reset Tutorial", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset") {
                tutorialManager.resetTutorial(tutorial)
            }
        } message: {
            Text("This tutorial will show again the next time you \(tutorial == .interviewSession ? "start an interview" : "view a session summary").")
        }
    }
    
    private func handleTap() {
        switch tutorial {
        case .home:
            // Navigate to Home tab and start tutorial
            withAnimation {
                appState.selectedTab = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                tutorialManager.startTutorial(tutorial, isReplay: true)
            }
        case .interviewSession, .sessionSummary:
            // Show confirmation to reset tutorial
            showingResetConfirmation = true
        }
    }
}

#Preview {
    let manager = TutorialManager()
    
    return VStack {
        Text("Test Content")
            .tutorialHighlight("test-element")
        
        Button("Start Tutorial") {
            manager.startTutorial(.home)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppTheme.background)
    .environmentObject(manager)
}
