import SwiftUI
import AVKit
import AVFoundation
import Combine

struct SessionSummaryView: View {
    @Binding var session: InterviewSession
    @ObservedObject var analysisManager: DeferredAnalysisManager
    let answeredQuestions: Int
    let startTime: Date
    let endTime: Date
    let onDismiss: () -> Void
    let onGoHome: () -> Void
    let onViewResults: () -> Void
    var isFromHistory: Bool = false
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tutorialManager: TutorialManager
    @State private var showingAnalytics = true
    @State private var hasSavedSession = false
    @State private var showingSharePreview = false
    private let suggestionsEngine = ImprovementSuggestionsEngine()
    
    // Convenience initializer for viewing historical sessions (no analysis needed)
    init(
        session: InterviewSession,
        answeredQuestions: Int,
        startTime: Date,
        endTime: Date,
        onDismiss: @escaping () -> Void,
        onGoHome: @escaping () -> Void,
        onViewResults: @escaping () -> Void,
        isFromHistory: Bool = false
    ) {
        // Create a static binding for historical sessions
        self._session = .constant(session)
        // Create a dummy analysis manager that won't do anything
        self.analysisManager = DeferredAnalysisManager()
        self.answeredQuestions = answeredQuestions
        self.startTime = startTime
        self.endTime = endTime
        self.onDismiss = onDismiss
        self.onGoHome = onGoHome
        self.onViewResults = onViewResults
        self.isFromHistory = isFromHistory
    }
    
    // Full initializer for post-interview analysis
    init(
        session: Binding<InterviewSession>,
        analysisManager: DeferredAnalysisManager,
        answeredQuestions: Int,
        startTime: Date,
        endTime: Date,
        onDismiss: @escaping () -> Void,
        onGoHome: @escaping () -> Void,
        onViewResults: @escaping () -> Void,
        isFromHistory: Bool = false
    ) {
        self._session = session
        self.analysisManager = analysisManager
        self.answeredQuestions = answeredQuestions
        self.startTime = startTime
        self.endTime = endTime
        self.onDismiss = onDismiss
        self.onGoHome = onGoHome
        self.onViewResults = onViewResults
        self.isFromHistory = isFromHistory
    }
    
    var gradeBackgroundColor: Color {
        // Show gray when still analyzing
        guard !analysisManager.isAnalyzing else {
            return AppTheme.textSecondary.opacity(0.5)
        }
        let score = Int(session.averageScore)
        switch score {
        case 90...100: return AppTheme.primary
        case 80..<90: return Color.blue
        case 70..<80: return Color.orange
        default: return AppTheme.softRed
        }
    }
    
    // MARK: - Extracted Views for Tutorial Highlights
    
    /// Grade circle view - extracted for precise tutorial highlighting
    @ViewBuilder
    private var gradeCircleView: some View {
        ZStack {
            Circle()
                .fill(gradeBackgroundColor)
                .frame(width: 80, height: 80)
            
            if analysisManager.isAnalyzing {
                // Show progress ring while analyzing
                Circle()
                    .stroke(AppTheme.primary.opacity(0.3), lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: analysisManager.totalCount > 0 ? Double(analysisManager.completedCount) / Double(analysisManager.totalCount) : 0)
                    .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4), value: analysisManager.completedCount)
                
                Text("\(analysisManager.completedCount)/\(analysisManager.totalCount)")
                    .font(AppTheme.font(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 2) {
                    Text(session.overallGrade)
                        .font(AppTheme.font(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(Int(session.averageScore))")
                        .font(AppTheme.font(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: analysisManager.isAnalyzing)
    }
    
    /// Stats row view - extracted for precise tutorial highlighting
    private var statsRowView: some View {
        HStack(spacing: 8) {
            SummaryStat(label: "Role", value: session.role)
            SummaryStat(label: "Duration", value: session.formattedDuration)
            SummaryStat(label: "Questions", value: "\(answeredQuestions)/\(session.questions.count)")
        }
    }
    
    var body: some View {
        TutorialWrapper(tutorialType: .sessionSummary) {
            summaryContent
        }
    }
    
    private var summaryContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(AppTheme.font(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.cardBackground)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Text("Feedback")
                    .font(AppTheme.font(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
                
                Button {
                    showingSharePreview = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(AppTheme.font(size: 16, weight: .semibold))
                        .foregroundStyle(analysisManager.isAnalyzing ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.cardBackground)
                        .clipShape(Circle())
                }
                .disabled(analysisManager.isAnalyzing)
                .tutorialHighlight("summary-share")
            }
            .padding(20)
            
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // Analysis Progress Banner (shown during analysis)
                    if analysisManager.isAnalyzing {
                        AnalysisProgressBanner(analysisManager: analysisManager)
                            .padding(.horizontal, 20)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                    
                    // Top Summary Card
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(analysisManager.isAnalyzing ? "Analyzing..." : "Great Job!")
                                    .font(AppTheme.font(size: 24, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(analysisManager.isAnalyzing ? "Processing your responses" : "You've completed the interview.")
                                    .font(AppTheme.font(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            // Grade circle - wrapped for precise highlighting
                            gradeCircleView
                                .tutorialHighlight("summary-grade")
                        }
                        
                        // Stats row - wrapped for precise highlighting
                        statsRowView
                            .tutorialHighlight("summary-stats")
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(24)
                    .padding(.horizontal, 20)
                    .id("top-section")
                    
                    // Analytics Overview Cards (show skeleton when analyzing)
                    if analysisManager.isAnalyzing && analysisManager.completedCount == 0 {
                        AnalyticsOverviewSkeleton()
                            .padding(.horizontal, 20)
                    } else {
                    AnalyticsOverviewCards(session: session)
                        .padding(.horizontal, 20)
                            .animation(.spring(response: 0.4), value: session.averageScore)
                    }
                    
                    // Analytics Charts Section (only show after some analysis)
                    if !analysisManager.isAnalyzing && showingAnalytics && hasAnalyticsData {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Performance Analytics")
                                    .font(AppTheme.font(size: 18, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Button {
                                    withAnimation {
                                        showingAnalytics.toggle()
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(AppTheme.font(size: 14))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(spacing: 16) {
                                TimeSpentChart(questions: session.questions)
                                    .padding(.horizontal, 20)
                                
                                EyeContactChart(questions: session.questions)
                                    .padding(.horizontal, 20)
                                
                                ConfidenceScoreChart(questions: session.questions)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                    } else if !analysisManager.isAnalyzing && hasAnalyticsData {
                        Button {
                            withAnimation {
                                showingAnalytics.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Show Performance Analytics")
                                    .font(AppTheme.font(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.primary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(AppTheme.font(size: 14))
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .padding(16)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Improvement Suggestions (only show after analysis)
                    if !analysisManager.isAnalyzing, let sessionSummary = generateSessionSummary() {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Key Insights")
                                .font(AppTheme.font(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 20)
                            
                            if !sessionSummary.strengths.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(AppTheme.primary)
                                        Text("Strengths")
                                            .font(AppTheme.font(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                    
                                    ForEach(sessionSummary.strengths, id: \.self) { strength in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(AppTheme.font(size: 12))
                                                .foregroundStyle(AppTheme.primary)
                                            Text(strength)
                                                .font(AppTheme.font(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(AppTheme.lightGreen)
                                .cornerRadius(16)
                                .padding(.horizontal, 20)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                            }
                            
                            if !sessionSummary.overallRecommendations.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundStyle(Color.orange)
                                        Text("Recommendations")
                                            .font(AppTheme.font(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                    
                                    ForEach(Array(sessionSummary.overallRecommendations.enumerated()), id: \.offset) { index, recommendation in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(index + 1).")
                                                .font(AppTheme.font(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.orange)
                                            Text(recommendation)
                                                .font(AppTheme.font(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(16)
                                .padding(.horizontal, 20)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                            }
                        }
                        .tutorialHighlight("summary-insights")
                        .id("insights-section")
                    }
                    
                    // Questions List with Progressive Loading
                    VStack(alignment: .leading, spacing: 16) {
                        // Heading + first question for tutorial highlight
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Questions Analysis")
                                .font(AppTheme.font(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 20)
                        
                            if let firstQuestion = session.questions.first {
                                ProgressiveQuestionRow(
                                    index: 1,
                                    question: firstQuestion,
                                    analysisState: analysisManager.stateForQuestion(0),
                                    suggestionsEngine: suggestionsEngine
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: analysisManager.stateForQuestion(0))
                            }
                        }
                        .tutorialHighlight("summary-questions")
                        .id("questions-section")
                        
                        // Remaining questions
                        ForEach(Array(session.questions.enumerated().dropFirst()), id: \.offset) { index, question in
                            ProgressiveQuestionRow(
                                index: index + 1,
                                question: question,
                                analysisState: analysisManager.stateForQuestion(index),
                                suggestionsEngine: suggestionsEngine
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity
                            ))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: analysisManager.stateForQuestion(index))
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .onChange(of: tutorialManager.currentStepIndex) { oldIndex, newIndex in
                // Auto-scroll based on tutorial step
                if tutorialManager.activeTutorial == .sessionSummary {
                    let currentStep = tutorialManager.currentStep
                    let isGoingBack = newIndex < oldIndex
                    
                    if isGoingBack {
                        // Going backwards - scroll to appropriate section
                        if let stepId = currentStep?.id {
                            switch stepId {
                            case "share-button", "overall-grade", "analytics-cards", "scroll-hint":
                                // These are at the top - scroll to top
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo("top-section", anchor: .top)
                                }
                            case "key-insights":
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo("insights-section", anchor: .center)
                                }
                            default:
                                break
                            }
                        }
                    } else {
                        // Going forwards
                        if currentStep?.id == "key-insights" {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo("insights-section", anchor: .center)
                            }
                        } else if currentStep?.id == "questions-analysis" {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo("questions-section", anchor: .top)
                            }
                        }
                    }
                }
            }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: analysisManager.isAnalyzing)
            
            // Floating Bottom Action
            VStack {
                if isFromHistory {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .shadow(color: AppTheme.primary.opacity(0.3), radius: 12, x: 0, y: 6)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            onViewResults()
                        } label: {
                            Text("Go to Preps")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(analysisManager.isAnalyzing)
                        .opacity(analysisManager.isAnalyzing ? 0.5 : 1)
                        
                        Button {
                            onGoHome()
                        } label: {
                            Text("Back to Home")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(analysisManager.isAnalyzing)
                        .opacity(analysisManager.isAnalyzing ? 0.5 : 1)
                    }
                    .shadow(color: AppTheme.primary.opacity(0.2), radius: 12, x: 0, y: 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.background.opacity(0),
                        AppTheme.background.opacity(0.9),
                        AppTheme.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false),
                alignment: .bottom
            )
        }
        .background(AppTheme.background)
        .onAppear {
            if isFromHistory {
                // For historical sessions, initialize states from existing session data
                analysisManager.initializeFromSession(session)
            } else {
                startDeferredAnalysis()
            }
            
            // Start summary tutorial if not seen yet (not for history views)
            if !isFromHistory {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    tutorialManager.startSummaryTutorialIfNeeded()
                }
            }
        }
        .sheet(isPresented: $showingSharePreview) {
            SharePreviewView(
                session: session,
                startTime: startTime,
                endTime: endTime
            )
        }
    }
    
    private var hasAnalyticsData: Bool {
        session.questions.contains { question in
            question.answer?.eyeContactMetrics != nil ||
            question.answer?.confidenceScore != nil ||
            question.answer?.toneAnalysis != nil
        }
    }
    
    private func generateSessionSummary() -> SessionSummary? {
        guard hasAnalyticsData else { return nil }
        return suggestionsEngine.generateSessionSummary(for: session)
    }
    
    private func startDeferredAnalysis() {
        guard !isFromHistory && !hasSavedSession else { return }
        
        Task {
            // Background analysis is already running from InterviewSessionView
            // Just wait for any remaining items to complete
            print("📊 Waiting for background analysis to complete...")
            print("📊 Status: \(analysisManager.completedCount)/\(analysisManager.totalCount) complete")
            
            // Wait for all background processing to finish
            await analysisManager.finishRemainingAnalysis()
            
            // After all analysis is complete, save to Supabase
            await saveSessionToSupabase()
        }
    }
    
    @MainActor
    private func saveSessionToSupabase() async {
        guard !hasSavedSession else { return }
        hasSavedSession = true
        
        print("💾 Saving analyzed session to Supabase...")
        
        // Warm up connection
        await SupabaseService.shared.aggressiveWarmUp()
        
        var saveSucceeded = false
        for attempt in 1...3 {
            do {
                try await SupabaseService.shared.saveInterviewSession(session)
                print("✅ Session saved to Supabase (attempt \(attempt))")
                saveSucceeded = true
                
                // Update the preloaded sessions cache
                appState.preloadedSessions.insert(session, at: 0)
                appState.sessionJustSaved = true
                break
            } catch {
                print("❌ Failed to save session (attempt \(attempt)): \(error.localizedDescription)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        
        if !saveSucceeded {
            print("❌ Session save failed after 3 attempts")
            // Still add to preloaded so user sees it locally
            appState.preloadedSessions.insert(session, at: 0)
            appState.sessionJustSaved = true
        }
    }
}

// MARK: - Analysis Progress Banner

struct AnalysisProgressBanner: View {
    @ObservedObject var analysisManager: DeferredAnalysisManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Animated spinner
            ZStack {
                Circle()
                    .stroke(AppTheme.primary.opacity(0.2), lineWidth: 3)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(analysisManager.isAnalyzing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: analysisManager.isAnalyzing)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(analysisManager.progress?.progressText ?? "Preparing analysis...")
                        .font(AppTheme.font(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                if let progress = analysisManager.progress {
                    Text(progress.currentState.displayText)
                        .font(AppTheme.font(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(AppTheme.primary.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Analytics Overview Skeleton

struct AnalyticsOverviewSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(shimmerGradient)
                        .frame(height: 24)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(shimmerGradient)
                        .frame(height: 16)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
            }
        }
        .onAppear { isAnimating = true }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.textSecondary.opacity(0.1),
                AppTheme.textSecondary.opacity(0.2),
                AppTheme.textSecondary.opacity(0.1)
            ],
            startPoint: isAnimating ? .leading : .trailing,
            endPoint: isAnimating ? .trailing : .leading
        )
    }
}

// MARK: - Progressive Question Row

struct ProgressiveQuestionRow: View {
    let index: Int
    let question: InterviewQuestion
    let analysisState: QuestionAnalysisState
    let suggestionsEngine: ImprovementSuggestionsEngine
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Question number badge
                ZStack {
                    Circle()
                        .fill(badgeBackgroundColor)
                        .frame(width: 32, height: 32)
                    
                    if analysisState.isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(AppTheme.primary)
                    } else {
                Text("\(index)")
                    .font(AppTheme.font(size: 14, weight: .bold))
                            .foregroundStyle(badgeTextColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                        .font(AppTheme.font(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    // Status/Metrics Row
                    HStack(spacing: 8) {
                        AnalysisStatusBadge(state: analysisState, question: question)
                        
                        Spacer(minLength: 0)
                        
                        if analysisState.isComplete {
                            Button {
                                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(AppTheme.font(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                }
            }
            
            // Expanded content (only when complete)
            if isExpanded, case .complete = analysisState {
                ExpandedQuestionContent(
                    question: question,
                    suggestionsEngine: suggestionsEngine
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    private var badgeBackgroundColor: Color {
        switch analysisState {
        case .complete:
            return AppTheme.lightGreen
        case .failed, .skipped:
            return AppTheme.softRed.opacity(0.2)
        default:
            return AppTheme.textSecondary.opacity(0.1)
        }
    }
    
    private var badgeTextColor: Color {
        switch analysisState {
        case .complete:
            return AppTheme.primary
        case .failed, .skipped:
            return AppTheme.softRed
        default:
            return AppTheme.textSecondary
        }
    }
}

// MARK: - Analysis Status Badge

struct AnalysisStatusBadge: View {
    let state: QuestionAnalysisState
    let question: InterviewQuestion
    
    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .pending:
                Image(systemName: "clock")
                    .font(AppTheme.font(size: 10))
                Text("Waiting...")
                    .font(AppTheme.font(size: 12, weight: .medium))
                
            case .queued:
                Image(systemName: "list.bullet")
                    .font(AppTheme.font(size: 10))
                Text("In queue...")
                    .font(AppTheme.font(size: 12, weight: .medium))
                
            case .transcribing:
                LoadingDots()
                Text("Transcribing")
                    .font(AppTheme.font(size: 12, weight: .medium))
                
            case .analyzingTone:
                LoadingDots()
                Text("Analyzing")
                    .font(AppTheme.font(size: 12, weight: .medium))
                
            case .evaluating:
                LoadingDots()
                Text("Evaluating")
                    .font(AppTheme.font(size: 12, weight: .medium))
                
            case .complete:
                // Show actual metrics
                if let answer = question.answer {
                    if let evaluation = answer.evaluation {
                                MetricBadge(
                                    icon: "star.fill",
                                    value: "\(evaluation.score)",
                                    color: scoreColor(for: evaluation.score)
                                )
                            }
                            
                    if let confidence = answer.confidenceScore {
                                MetricBadge(
                                    icon: "chart.line.uptrend.xyaxis",
                                    value: String(format: "%.1f", confidence),
                                    color: confidenceColor(for: confidence)
                                )
                            }
                            
                    if let eyeContact = answer.eyeContactMetrics {
                                MetricBadge(
                                    icon: "eye.fill",
                                    value: "\(Int(eyeContact.percentage))%",
                                    color: eyeContactColor(for: eyeContact.percentage)
                                )
                            }
                            
                    if let timeSpent = answer.timeSpent {
                                MetricBadge(
                                    icon: "clock.fill",
                                    value: "\(Int(timeSpent))s",
                                    color: AppTheme.textSecondary
                                )
                            }
                        }
                        
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppTheme.font(size: 10))
                Text("Failed")
                    .font(AppTheme.font(size: 12, weight: .medium))
                
            case .skipped:
                Image(systemName: "forward.fill")
                    .font(AppTheme.font(size: 10))
                Text("Skipped")
                    .font(AppTheme.font(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, state.isComplete ? 0 : 10)
        .padding(.vertical, state.isComplete ? 0 : 6)
        .background(state.isComplete ? Color.clear : backgroundColor)
        .cornerRadius(8)
    }
    
    private var foregroundColor: Color {
        switch state {
        case .complete:
            return AppTheme.textPrimary
        case .failed:
            return AppTheme.softRed
        case .skipped:
            return AppTheme.textSecondary
        default:
            return AppTheme.primary
        }
    }
    
    private var backgroundColor: Color {
        switch state {
        case .failed:
            return AppTheme.softRed.opacity(0.1)
        case .skipped:
            return AppTheme.textSecondary.opacity(0.1)
        default:
            return AppTheme.primary.opacity(0.1)
        }
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100: return AppTheme.primary
        case 80..<90: return Color.blue
        case 70..<80: return Color.orange
        default: return AppTheme.softRed
        }
    }
    
    private func confidenceColor(for score: Double) -> Color {
        switch score {
        case 8...10: return AppTheme.primary
        case 6..<8: return Color.blue
        case 4..<6: return Color.orange
        default: return AppTheme.softRed
        }
    }
    
    private func eyeContactColor(for percentage: Double) -> Color {
        percentage >= 60 ? AppTheme.primary : Color.orange
    }
}

// MARK: - Loading Dots Animation

struct LoadingDots: View {
    @State private var animationStep = 0
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppTheme.primary)
                    .frame(width: 4, height: 4)
                    .opacity(animationStep == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) {
                animationStep = (animationStep + 1) % 3
            }
        }
    }
}

// MARK: - Expanded Question Content

struct ExpandedQuestionContent: View {
    let question: InterviewQuestion
    let suggestionsEngine: ImprovementSuggestionsEngine
    
    var body: some View {
                VStack(alignment: .leading, spacing: 16) {
                    // Analytics Metrics
                    if let answer = question.answer {
                            // Tone Analysis
                            if let tone = answer.toneAnalysis {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Speech Analysis")
                                        .font(AppTheme.font(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    
                                    HStack(spacing: 16) {
                                        AnalyticItem(
                                            label: "Pace",
                                            value: tone.formattedPace,
                                            subtitle: tone.paceDescription
                                        )
                                        AnalyticItem(
                                            label: "Sentiment",
                                            value: tone.sentiment.label,
                                            subtitle: String(format: "%.0f%% confident", tone.sentiment.confidence * 100)
                                        )
                                        AnalyticItem(
                                            label: "Pauses",
                                            value: "\(tone.pauseCount)",
                                            subtitle: String(format: "%.1fs avg", tone.averagePauseDuration)
                                        )
                                    }
                                }
                                .padding(12)
                                .background(AppTheme.background)
                                .cornerRadius(12)
                            }
                            
                            // Suggestions
                                let suggestions = suggestionsEngine.generateSuggestions(for: answer)
                                if !suggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Improvement Tips")
                                            .font(AppTheme.font(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        
                                        ForEach(suggestions.prefix(3), id: \.title) { suggestion in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "lightbulb.fill")
                                                    .font(AppTheme.font(size: 12))
                                                    .foregroundStyle(Color.orange)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(suggestion.title)
                                                        .font(AppTheme.font(size: 13, weight: .semibold))
                                                        .foregroundStyle(AppTheme.textPrimary)
                                                    Text(suggestion.description)
                                                        .font(AppTheme.font(size: 12))
                                                        .foregroundStyle(AppTheme.textSecondary)
                                                }
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(12)
                        }
                    }
                    
                    // Audio Player
                    if let audioURL = question.answer?.audioURL,
                       let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let fullAudioURL = documentsPath.appendingPathComponent(audioURL)
                        if FileManager.default.fileExists(atPath: fullAudioURL.path) {
                            AudioPlayerView(audioURL: fullAudioURL)
                        }
                    }
                    
                    // Transcription
            if let transcription = question.answer?.transcription,
               transcription != "No audio recorded",
               transcription != "Analysis failed" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcription")
                                .font(AppTheme.font(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text(transcription)
                                .font(AppTheme.font(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineSpacing(4)
                                .padding(12)
                                .background(AppTheme.background)
                                .cornerRadius(8)
                        }
                    }
                    
                    // Feedback
                    if let feedback = question.answer?.evaluation?.feedback {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Feedback")
                                .font(AppTheme.font(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text(feedback)
                                .font(AppTheme.font(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.leading, 44)
            }
}

// MARK: - Supporting Views (kept from original)

struct SummaryStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTheme.font(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(AppTheme.font(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.background)
        .cornerRadius(12)
    }
}

struct MetricBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTheme.font(size: 10))
                .frame(width: 10, height: 10)
            Text(value)
                .font(AppTheme.font(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct AnalyticItem: View {
    let label: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTheme.font(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(AppTheme.font(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .font(AppTheme.font(size: 10))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AudioPlayerView: View {
    let audioURL: URL
    @StateObject private var audioPlayer = AudioPlayerManager()
    
    var body: some View {
        HStack(spacing: 16) {
            Button {
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(AppTheme.font(size: 40))
                    .foregroundStyle(AppTheme.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatTime(audioPlayer.currentTime))
                        .font(AppTheme.font(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Text(formatTime(audioPlayer.duration))
                        .font(AppTheme.font(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.textSecondary.opacity(0.2))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.primary)
                            .frame(width: geometry.size.width * CGFloat(audioPlayer.progress), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .onAppear {
            audioPlayer.setupPlayer(with: audioURL)
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var progress: Double = 0
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    func setupPlayer(with url: URL) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            print("❌ Error setting up audio player: \(error)")
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }
    
    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            self.currentTime = player.currentTime
            self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
            
            if !player.isPlaying {
                self.isPlaying = false
                self.stopTimer()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// Legacy compatibility - EnhancedFeedbackQuestionRow for history views
struct EnhancedFeedbackQuestionRow: View {
    let index: Int
    let question: InterviewQuestion
    let suggestionsEngine: ImprovementSuggestionsEngine
    @State private var isExpanded = false
    
    var body: some View {
        ProgressiveQuestionRow(
            index: index,
            question: question,
            analysisState: .complete(question.answer ?? QuestionAnswer(transcription: "")),
            suggestionsEngine: suggestionsEngine
        )
    }
}

// MARK: - Shareable Result Card

/// A visually appealing card that can be rendered as an image for sharing
struct ShareableResultCard: View {
    let session: InterviewSession
    let startTime: Date
    let endTime: Date
    
    private var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: startTime)
    }
    
    private var gradeColor: Color {
        let score = Int(session.averageScore)
        switch score {
        case 90...100: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case 80..<90: return Color(red: 0.3, green: 0.6, blue: 0.9)
        case 70..<80: return Color(red: 1.0, green: 0.6, blue: 0.2)
        default: return Color(red: 0.9, green: 0.3, blue: 0.3)
        }
    }
    
    var body: some View {
        ZStack {
            // Solid dark background
            Color(red: 0.08, green: 0.1, blue: 0.12)
            
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)
                
                // App branding (text only)
                Text("Final Round")
                    .font(AppTheme.font(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 40)
                
                // Grade circle
                ZStack {
                    Circle()
                        .fill(gradeColor)
                        .frame(width: 160, height: 160)
                        .shadow(color: gradeColor.opacity(0.5), radius: 20, y: 10)
                    
                    VStack(spacing: 4) {
                        Text(session.overallGrade)
                            .font(AppTheme.font(size: 64, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(Int(session.averageScore))%")
                            .font(AppTheme.font(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.bottom, 40)
                
                // Role
                Text(session.role)
                    .font(AppTheme.font(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                
                Text("Interview Practice")
                    .font(AppTheme.font(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 40)
                
                // Stats grid
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        ShareStatBox(
                            icon: "questionmark.circle.fill",
                            value: "\(session.answeredCount)/\(session.questions.count)",
                            label: "Questions"
                        )
                        ShareStatBox(
                            icon: "clock.fill",
                            value: formattedDuration,
                            label: "Duration"
                        )
                    }
                    
                    HStack(spacing: 20) {
                        if session.averageEyeContact > 0 {
                            ShareStatBox(
                                icon: "eye.fill",
                                value: "\(Int(session.averageEyeContact))%",
                                label: "Eye Contact"
                            )
                        }
                        if session.averageConfidenceScore > 0 {
                            ShareStatBox(
                                icon: "chart.line.uptrend.xyaxis",
                                value: String(format: "%.1f", session.averageConfidenceScore),
                                label: "Confidence"
                            )
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                
                Spacer()
                
                // Date and watermark
                VStack(spacing: 8) {
                    Text(formattedDate)
                        .font(AppTheme.font(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Text("finalround.app")
                        .font(AppTheme.font(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 400, height: 700)
    }
}

struct ShareStatBox: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(AppTheme.font(size: 20))
                .foregroundStyle(.white.opacity(0.7))
            
            Text(value)
                .font(AppTheme.font(size: 22, weight: .bold))
                .foregroundStyle(.white)
            
            Text(label)
                .font(AppTheme.font(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Share Text Generator

struct ShareTextGenerator {
    static func generateShareText(for session: InterviewSession, startTime: Date, endTime: Date) -> String {
        let duration = endTime.timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        var text = """
        I just completed a \(session.role) interview practice on Final Round! 🎯
        
        📊 Grade: \(session.overallGrade) (\(Int(session.averageScore))%)
        ✅ Questions: \(session.answeredCount)/\(session.questions.count) answered
        ⏱️ Duration: \(minutes)m \(seconds)s
        """
        
        if session.averageEyeContact > 0 {
            text += "\n👁️ Eye Contact: \(Int(session.averageEyeContact))%"
        }
        
        if session.averageConfidenceScore > 0 {
            text += "\n💪 Confidence: \(String(format: "%.1f", session.averageConfidenceScore))/10"
        }
        
        text += "\n\n#InterviewPrep #FinalRound #CareerGrowth"
        
        return text
    }
}

// MARK: - Share Preview View

struct SharePreviewView: View {
    @Environment(\.dismiss) var dismiss
    let session: InterviewSession
    let startTime: Date
    let endTime: Date
    
    @State private var includeImage = true
    @State private var includeText = true
    @State private var renderedImage: UIImage?
    @State private var isRendering = true
    @State private var isSharing = false
    
    private var shareText: String {
        ShareTextGenerator.generateShareText(for: session, startTime: startTime, endTime: endTime)
    }
    
    /// Check if share button should be enabled
    private var canShare: Bool {
        guard !isSharing else { return false }
        // If only text is selected, we can share
        if !includeImage && includeText { return true }
        // If image is selected, we need the rendered image
        if includeImage && renderedImage != nil { return true }
        // If neither is selected, can't share
        if !includeImage && !includeText { return false }
        // Image selected but not ready yet
        return false
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Image Preview Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button {
                                includeImage.toggle()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: includeImage ? "checkmark.square.fill" : "square")
                                        .font(AppTheme.font(size: 22))
                                        .foregroundStyle(includeImage ? AppTheme.primary : AppTheme.textSecondary)
                                    
                                    Text("Include Image")
                                        .font(AppTheme.font(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                        
                        // Image preview
                        if let image = renderedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(includeImage ? AppTheme.primary : AppTheme.border, lineWidth: includeImage ? 2 : 1)
                                )
                                .opacity(includeImage ? 1 : 0.5)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.cardBackground)
                                .frame(height: 280)
                                .overlay(
                                    VStack(spacing: 12) {
                                        ProgressView()
                                        Text("Generating preview...")
                                            .font(AppTheme.font(size: 13))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                )
                        }
                    }
                    .padding(16)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Text Preview Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button {
                                includeText.toggle()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: includeText ? "checkmark.square.fill" : "square")
                                        .font(AppTheme.font(size: 22))
                                        .foregroundStyle(includeText ? AppTheme.primary : AppTheme.textSecondary)
                                    
                                    Text("Include Text")
                                        .font(AppTheme.font(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                        
                        // Text preview
                        Text(shareText)
                            .font(AppTheme.font(size: 14))
                            .foregroundStyle(includeText ? AppTheme.textPrimary : AppTheme.textSecondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.background)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(includeText ? AppTheme.primary : AppTheme.border, lineWidth: includeText ? 2 : 1)
                            )
                            .opacity(includeText ? 1 : 0.5)
                    }
                    .padding(16)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .background(AppTheme.background)
            .navigationTitle("Share Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTheme.font(size: 14, weight: .semibold))
                            .padding(10)
                            .background(AppTheme.controlBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    prepareAndShare()
                } label: {
                    HStack(spacing: 8) {
                        if isRendering && includeImage || isSharing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isSharing ? "Sharing..." : (isRendering && includeImage ? "Preparing..." : "Share"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canShare)
                .opacity(canShare ? 1 : 0.5)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: AppTheme.background.opacity(0), location: 0),
                            .init(color: AppTheme.background, location: 0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .task {
                await renderImageAsync()
            }
        }
    }
    
    @MainActor
    private func renderImageAsync() async {
        isRendering = true
        
        // Small delay to allow SwiftUI layout to complete
        // This is crucial for ImageRenderer to work on first attempt
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Create the card view for rendering
        let card = ShareableResultCard(
            session: session,
            startTime: startTime,
            endTime: endTime
        )
        .environment(\.colorScheme, .dark)
        
        // Attempt rendering with retries
        for attempt in 1...3 {
            let renderer = ImageRenderer(content: card)
            renderer.scale = UIScreen.main.scale
            renderer.proposedSize = ProposedViewSize(width: 400, height: 700)
            
            if let uiImage = renderer.uiImage {
                renderedImage = uiImage
                isRendering = false
                return
            }
            
            // Wait before retry
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms between retries
            }
        }
        
        isRendering = false
    }
    
    private func prepareAndShare() {
        var items: [Any] = []
        
        if includeImage, let image = renderedImage {
            items.append(image)
        }
        
        if includeText {
            items.append(shareText)
        }
        
        guard !items.isEmpty else { return }
        
        isSharing = true
        
        // Present share sheet via UIKit to avoid SwiftUI scene conflicts
        ShareSheetPresenter.present(items: items) {
            isSharing = false
        }
    }
}

// MARK: - Share Sheet Helper

/// Helper class to present UIActivityViewController directly from UIKit
/// This avoids SwiftUI sheet presentation issues that cause scene conflicts
class ShareSheetPresenter {
    static func present(items: [Any], completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                completion?()
                return
            }
            
            // Find the topmost presented view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
            
            // For iPad support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                completion?()
            }
            
            topController.present(activityVC, animated: true)
        }
    }
}
