import SwiftUI
import Combine

/// Manages the app's tutorial system with 3 independent, replayable tutorials
@MainActor
class TutorialManager: ObservableObject {
    // MARK: - Tutorial Types
    
    enum TutorialType: String, CaseIterable {
        case home = "home"
        case interviewSession = "interviewSession"
        case sessionSummary = "sessionSummary"
        
        var displayName: String {
            switch self {
            case .home: return "Home & Navigation"
            case .interviewSession: return "Interview Session"
            case .sessionSummary: return "Session Summary"
            }
        }
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .interviewSession: return "video.fill"
            case .sessionSummary: return "chart.bar.doc.horizontal.fill"
            }
        }
        
        var userDefaultsKey: String {
            "hasSeenTutorial_\(rawValue)"
        }
    }
    
    // MARK: - Published State
    
    /// Whether the home tutorial has been seen/completed
    @Published var hasSeenHomeTutorial: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenHomeTutorial, forKey: TutorialType.home.userDefaultsKey)
        }
    }
    
    /// Whether the interview session tutorial has been seen/completed
    @Published var hasSeenSessionTutorial: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenSessionTutorial, forKey: TutorialType.interviewSession.userDefaultsKey)
        }
    }
    
    /// Whether the session summary tutorial has been seen/completed
    @Published var hasSeenSummaryTutorial: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenSummaryTutorial, forKey: TutorialType.sessionSummary.userDefaultsKey)
        }
    }
    
    /// Currently active tutorial (if any)
    @Published var activeTutorial: TutorialType?
    
    /// Current step index within the active tutorial
    @Published var currentStepIndex: Int = 0
    
    /// Whether the tutorial is being shown as a replay (from Profile)
    @Published var isReplay: Bool = false
    
    // MARK: - Computed Properties
    
    /// Whether the user has never seen any tutorial
    var isFirstTimeUser: Bool {
        !hasSeenHomeTutorial && !hasSeenSessionTutorial && !hasSeenSummaryTutorial
    }
    
    /// Whether a tutorial is currently active
    var isTutorialActive: Bool {
        activeTutorial != nil
    }
    
    /// Get completion status for a specific tutorial
    func hasCompleted(_ tutorial: TutorialType) -> Bool {
        switch tutorial {
        case .home: return hasSeenHomeTutorial
        case .interviewSession: return hasSeenSessionTutorial
        case .sessionSummary: return hasSeenSummaryTutorial
        }
    }
    
    // MARK: - Initialization
    
    init() {
        self.hasSeenHomeTutorial = UserDefaults.standard.bool(forKey: TutorialType.home.userDefaultsKey)
        self.hasSeenSessionTutorial = UserDefaults.standard.bool(forKey: TutorialType.interviewSession.userDefaultsKey)
        self.hasSeenSummaryTutorial = UserDefaults.standard.bool(forKey: TutorialType.sessionSummary.userDefaultsKey)
    }
    
    // MARK: - Tutorial Control
    
    /// Start a tutorial
    func startTutorial(_ type: TutorialType, isReplay: Bool = false) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            self.activeTutorial = type
            self.currentStepIndex = 0
            self.isReplay = isReplay
        }
    }
    
    /// Start the home tutorial if it hasn't been seen
    func startHomeTutorialIfNeeded() {
        guard !hasSeenHomeTutorial else { return }
        startTutorial(.home)
    }
    
    /// Start the session tutorial if it hasn't been seen
    func startSessionTutorialIfNeeded() {
        guard !hasSeenSessionTutorial else { return }
        startTutorial(.interviewSession)
    }
    
    /// Start the summary tutorial if it hasn't been seen
    func startSummaryTutorialIfNeeded() {
        guard !hasSeenSummaryTutorial else { return }
        startTutorial(.sessionSummary)
    }
    
    /// Advance to the next step in the current tutorial
    func nextStep() {
        guard let tutorial = activeTutorial else { return }
        let steps = TutorialContent.steps(for: tutorial)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if currentStepIndex < steps.count - 1 {
                currentStepIndex += 1
            } else {
                // Tutorial complete
                completeTutorial()
            }
        }
    }
    
    /// Go to the previous step
    func previousStep() {
        guard currentStepIndex > 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentStepIndex -= 1
        }
    }
    
    /// Skip the current tutorial
    /// For home tutorial: Shows the "Profile tab reminder" step first
    func skipTutorial() {
        guard let tutorial = activeTutorial else { return }
        
        if tutorial == .home && !isReplay {
            // Show the profile reminder step before dismissing
            let steps = TutorialContent.steps(for: .home)
            let reminderIndex = steps.firstIndex { $0.id == "profile-reminder" } ?? (steps.count - 1)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentStepIndex = reminderIndex
            }
        } else {
            // For other tutorials, just dismiss
            completeTutorial()
        }
    }
    
    /// Complete and dismiss the current tutorial
    func completeTutorial() {
        guard let tutorial = activeTutorial else { return }
        
        // Mark as seen
        markTutorialComplete(tutorial)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeTutorial = nil
            currentStepIndex = 0
            isReplay = false
        }
    }
    
    /// Mark a specific tutorial as complete
    func markTutorialComplete(_ tutorial: TutorialType) {
        switch tutorial {
        case .home:
            hasSeenHomeTutorial = true
        case .interviewSession:
            hasSeenSessionTutorial = true
        case .sessionSummary:
            hasSeenSummaryTutorial = true
        }
    }
    
    /// Reset a specific tutorial so it can be replayed
    func resetTutorial(_ tutorial: TutorialType) {
        switch tutorial {
        case .home:
            hasSeenHomeTutorial = false
        case .interviewSession:
            hasSeenSessionTutorial = false
        case .sessionSummary:
            hasSeenSummaryTutorial = false
        }
    }
    
    /// Reset all tutorials
    func resetAllTutorials() {
        hasSeenHomeTutorial = false
        hasSeenSessionTutorial = false
        hasSeenSummaryTutorial = false
    }
    
    // MARK: - Current Step Info
    
    /// Get the current step for the active tutorial
    var currentStep: TutorialStep? {
        guard let tutorial = activeTutorial else { return nil }
        let steps = TutorialContent.steps(for: tutorial)
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }
    
    /// Get the total number of steps for the active tutorial
    var totalSteps: Int {
        guard let tutorial = activeTutorial else { return 0 }
        return TutorialContent.steps(for: tutorial).count
    }
    
    /// Check if current step is the last step
    var isLastStep: Bool {
        currentStepIndex >= totalSteps - 1
    }
    
    /// Check if current step is the first step
    var isFirstStep: Bool {
        currentStepIndex == 0
    }
}

