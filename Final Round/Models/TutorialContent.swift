import SwiftUI

// MARK: - Tutorial Step Model

/// Represents a single step in a tutorial
struct TutorialStep: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let icon: String
    let targetElementId: String?
    let arrowDirection: ArrowDirection
    let highlightPadding: CGFloat
    let requiresScroll: Bool
    
    /// Direction the arrow should point
    enum ArrowDirection {
        case up
        case down
        case left
        case right
        case none
    }
    
    init(
        id: String,
        title: String,
        message: String,
        icon: String = "info.circle.fill",
        targetElementId: String? = nil,
        arrowDirection: ArrowDirection = .down,
        highlightPadding: CGFloat = 8,
        requiresScroll: Bool = false
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.icon = icon
        self.targetElementId = targetElementId
        self.arrowDirection = arrowDirection
        self.highlightPadding = highlightPadding
        self.requiresScroll = requiresScroll
    }
    
    static func == (lhs: TutorialStep, rhs: TutorialStep) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tutorial Content

/// Contains all tutorial step definitions organized by tutorial type
struct TutorialContent {
    
    /// Get all steps for a specific tutorial type
    static func steps(for tutorial: TutorialManager.TutorialType) -> [TutorialStep] {
        switch tutorial {
        case .home:
            return homeSteps
        case .interviewSession:
            return sessionSteps
        case .sessionSummary:
            return summarySteps
        }
    }
    
    // MARK: - Home Tutorial Steps
    
    static let homeSteps: [TutorialStep] = [
        TutorialStep(
            id: "generate-button",
            title: "Create Custom Interview",
            message: "Tap 'Generate' to create a custom interview prep. You'll set your target role, question categories, and difficulty level.",
            icon: "wand.and.stars",
            targetElementId: "home-generate-button",
            arrowDirection: .up,
            highlightPadding: 12
        ),
        TutorialStep(
            id: "job-url",
            title: "Generate from Job URL",
            message: "Paste a LinkedIn job posting URL here to automatically generate interview questions tailored to that specific position.",
            icon: "link",
            targetElementId: "home-job-url-section",
            arrowDirection: .up,
            highlightPadding: 16
        ),
        TutorialStep(
            id: "recommended-jobs",
            title: "Browse Recommended Jobs",
            message: "We find jobs that match your profile. Tap any job card to view details and start a prep session for that role.",
            icon: "briefcase.fill",
            targetElementId: "home-recommended-section",
            arrowDirection: .down,
            highlightPadding: 16
        ),
        TutorialStep(
            id: "profile-reminder",
            title: "Replay Tutorials Anytime",
            message: "You can replay any tutorial from the Profile tab. Just tap 'Tutorials' to access them whenever you need a refresher!",
            icon: "arrow.counterclockwise",
            targetElementId: nil,
            arrowDirection: .none,
            highlightPadding: 0
        )
    ]
    
    // MARK: - Interview Session Tutorial Steps
    
    static let sessionSteps: [TutorialStep] = [
        TutorialStep(
            id: "indicators",
            title: "Session Timer",
            message: "Track your session duration here. The audio waveform and eye contact percentage appear inside the camera view.",
            icon: "timer",
            targetElementId: "session-timer",
            arrowDirection: .up,
            highlightPadding: 6
        ),
        TutorialStep(
            id: "question-card",
            title: "Interview Questions",
            message: "Each question appears here. Read it aloud and answer naturally.",
            icon: "text.bubble.fill",
            targetElementId: "session-question",
            arrowDirection: .down,
            highlightPadding: 4
        ),
        TutorialStep(
            id: "controls",
            title: "Session Controls",
            message: "Tap 'Next' when done, 'Skip' to move on, or the red button to end early.",
            icon: "slider.horizontal.3",
            targetElementId: "session-controls",
            arrowDirection: .down,
            highlightPadding: 8
        )
    ]
    
    // MARK: - Session Summary Tutorial Steps
    
    static let summarySteps: [TutorialStep] = [
        TutorialStep(
            id: "share-button",
            title: "Share Your Results",
            message: "Tap the share button to create a beautiful results card you can share on social media!",
            icon: "square.and.arrow.up",
            targetElementId: "summary-share",
            arrowDirection: .up,
            highlightPadding: 4
        ),
        TutorialStep(
            id: "overall-grade",
            title: "Your Performance Grade",
            message: "Your overall grade based on answer quality, eye contact, confidence, and speech analysis.",
            icon: "star.fill",
            targetElementId: "summary-grade",
            arrowDirection: .up,
            highlightPadding: 4
        ),
        TutorialStep(
            id: "analytics-cards",
            title: "Quick Analytics",
            message: "Key metrics at a glance: role practiced, session duration, and questions answered.",
            icon: "chart.pie.fill",
            targetElementId: "summary-stats",
            arrowDirection: .up,
            highlightPadding: 4
        ),
        TutorialStep(
            id: "scroll-hint",
            title: "More Insights Below",
            message: "We'll scroll down to show you detailed insights and question analysis.",
            icon: "arrow.down.circle.fill",
            targetElementId: nil,
            arrowDirection: .none,
            highlightPadding: 0,
            requiresScroll: true
        ),
        TutorialStep(
            id: "key-insights",
            title: "Strengths & Recommendations",
            message: "Your strengths and personalized recommendations for improvement.",
            icon: "lightbulb.fill",
            targetElementId: "summary-insights",
            arrowDirection: .up,
            highlightPadding: 8
        ),
        TutorialStep(
            id: "questions-analysis",
            title: "Detailed Question Analysis",
            message: "Tap any question to see your transcription, feedback, and tips for improvement.",
            icon: "list.bullet.rectangle.fill",
            targetElementId: "summary-questions",
            arrowDirection: .up,
            highlightPadding: 8
        )
    ]
}

