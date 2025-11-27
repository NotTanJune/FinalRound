import SwiftUI
import AVKit
import AVFoundation
import Combine

struct SessionSummaryView: View {
    let session: InterviewSession
    let answeredQuestions: Int
    let startTime: Date
    let endTime: Date
    let onDismiss: () -> Void
    let onGoHome: () -> Void
    let onViewResults: () -> Void
    var isFromHistory: Bool = false
    
    @State private var showingAnalytics = true
    private let suggestionsEngine = ImprovementSuggestionsEngine()
    
    var gradeBackgroundColor: Color {
        let score = Int(session.averageScore)
        switch score {
        case 90...100: return AppTheme.primary // Green
        case 80..<90: return Color.blue
        case 70..<80: return Color.orange
        default: return AppTheme.softRed
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.cardBackground)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Text("Feedback")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
                
                Button {
                    // Share action
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.cardBackground)
                        .clipShape(Circle())
                }
            }
            .padding(20)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // Top Summary Card
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Great Job!")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("You've completed the interview.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(gradeBackgroundColor)
                                    .frame(width: 80, height: 80)
                                VStack(spacing: 2) {
                                    Text(session.overallGrade)
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("\(Int(session.averageScore))")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            SummaryStat(label: "Role", value: session.role)
                            SummaryStat(label: "Duration", value: session.formattedDuration)
                            SummaryStat(label: "Questions", value: "\(answeredQuestions)/\(session.questions.count)")
                        }
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(24)
                    .padding(.horizontal, 20)
                    
                    // Analytics Overview Cards
                    AnalyticsOverviewCards(session: session)
                        .padding(.horizontal, 20)
                    
                    // Analytics Charts Section
                    if showingAnalytics && hasAnalyticsData {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Performance Analytics")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Button {
                                    withAnimation {
                                        showingAnalytics.toggle()
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Charts
                            VStack(spacing: 16) {
                                TimeSpentChart(questions: session.questions)
                                    .padding(.horizontal, 20)
                                
                                EyeContactChart(questions: session.questions)
                                    .padding(.horizontal, 20)
                                
                                ConfidenceScoreChart(questions: session.questions)
                                    .padding(.horizontal, 20)
                            }
                        }
                    } else if hasAnalyticsData {
                        Button {
                            withAnimation {
                                showingAnalytics.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Show Performance Analytics")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.primary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .padding(16)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Improvement Suggestions
                    if let sessionSummary = generateSessionSummary() {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Key Insights")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 20)
                            
                            // Strengths
                            if !sessionSummary.strengths.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(AppTheme.primary)
                                        Text("Strengths")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                    
                                    ForEach(sessionSummary.strengths, id: \.self) { strength in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppTheme.primary)
                                            Text(strength)
                                                .font(.system(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(AppTheme.lightGreen)
                                .cornerRadius(16)
                                .padding(.horizontal, 20)
                            }
                            
                            // Recommendations
                            if !sessionSummary.overallRecommendations.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundStyle(Color.orange)
                                        Text("Recommendations")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                    
                                    ForEach(Array(sessionSummary.overallRecommendations.enumerated()), id: \.offset) { index, recommendation in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(index + 1).")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.orange)
                                            Text(recommendation)
                                                .font(.system(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(16)
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // Questions List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Questions Analysis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 20)
                        
                        ForEach(Array(session.questions.enumerated()), id: \.offset) { index, question in
                            EnhancedFeedbackQuestionRow(
                                index: index + 1,
                                question: question,
                                suggestionsEngine: suggestionsEngine
                            )
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            
            // Floating Bottom Action
            VStack {
                if isFromHistory {
                    // When viewing from Preps tab, just show Dismiss
                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .shadow(color: AppTheme.primary.opacity(0.3), radius: 12, x: 0, y: 6)
                } else {
                    // When viewing after completing a session, show navigation options
                    HStack(spacing: 12) {
                        Button {
                            onViewResults() // This should go to Preps
                        } label: {
                            Text("Go to Preps")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        
                        Button {
                            onGoHome() // This should go to Home
                        } label: {
                            Text("Back to Home")
                        }
                        .buttonStyle(PrimaryButtonStyle())
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
}

struct SummaryStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
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

struct FeedbackQuestionRow: View {
    let index: Int
    let question: InterviewQuestion
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.lightGreen)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    HStack {
                        if let evaluation = question.answer?.evaluation {
                            Text("Score: \(evaluation.score)/100")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(scoreColor(for: evaluation.score))
                        } else if question.answer != nil {
                            Text("Score: Pending")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        } else {
                            Text("Not answered")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            withAnimation { isExpanded.toggle() }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Audio Player
                    if let audioURL = question.answer?.audioURL,
                       let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let fullAudioURL = documentsPath.appendingPathComponent(audioURL)
                        if FileManager.default.fileExists(atPath: fullAudioURL.path) {
                            AudioPlayerView(audioURL: fullAudioURL)
                        } else {
                            // Audio file not found
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.1))
                                .frame(height: 80)
                                .overlay(
                                    HStack(spacing: 12) {
                                        Image(systemName: "waveform.slash")
                                            .font(.system(size: 24))
                                            .foregroundStyle(AppTheme.textSecondary)
                                        Text("Audio not available")
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                )
                        }
                    } else {
                        // No audio recorded
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.1))
                            .frame(height: 80)
                            .overlay(
                                HStack(spacing: 12) {
                                    Image(systemName: "waveform.slash")
                                        .font(.system(size: 24))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    Text("No audio recorded")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            )
                    }
                    
                    // Transcription
                    if let transcription = question.answer?.transcription, transcription != "No audio recorded" {
                        Text("Transcription")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text(transcription)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineSpacing(4)
                            .padding(12)
                            .background(AppTheme.background)
                            .cornerRadius(8)
                    }
                    
                    Text("Feedback")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    if let feedback = question.answer?.evaluation?.feedback {
                        Text(feedback)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineSpacing(4)
                    } else {
                        Text("No feedback available")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineSpacing(4)
                    }
                }
                .padding(.leading, 44) // Indent to align with text
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100: return AppTheme.primary // Green
        case 80..<90: return Color.blue
        case 70..<80: return Color.orange
        default: return AppTheme.softRed
        }
    }
}

// MARK: - Enhanced Feedback Question Row with Analytics

struct EnhancedFeedbackQuestionRow: View {
    let index: Int
    let question: InterviewQuestion
    let suggestionsEngine: ImprovementSuggestionsEngine
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.lightGreen)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    // Metrics Row - Use flexible wrapping layout
                    HStack(spacing: 8) {
                        // First row of metrics
                        HStack(spacing: 6) {
                            if let evaluation = question.answer?.evaluation {
                                MetricBadge(
                                    icon: "star.fill",
                                    value: "\(evaluation.score)",
                                    color: scoreColor(for: evaluation.score)
                                )
                            }
                            
                            if let confidence = question.answer?.confidenceScore {
                                MetricBadge(
                                    icon: "chart.line.uptrend.xyaxis",
                                    value: String(format: "%.1f", confidence),
                                    color: confidenceColor(for: confidence)
                                )
                            }
                            
                            if let eyeContact = question.answer?.eyeContactMetrics {
                                MetricBadge(
                                    icon: "eye.fill",
                                    value: "\(Int(eyeContact.percentage))%",
                                    color: eyeContactColor(for: eyeContact.percentage)
                                )
                            }
                            
                            if let timeSpent = question.answer?.timeSpent {
                                MetricBadge(
                                    icon: "clock.fill",
                                    value: "\(Int(timeSpent))s",
                                    color: AppTheme.textSecondary
                                )
                            }
                        }
                        
                        Spacer(minLength: 0)
                        
                        Button {
                            withAnimation { isExpanded.toggle() }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Analytics Metrics
                    if let answer = question.answer {
                        VStack(alignment: .leading, spacing: 12) {
                            // Tone Analysis
                            if let tone = answer.toneAnalysis {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Speech Analysis")
                                        .font(.system(size: 14, weight: .semibold))
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
                            if let answer = question.answer {
                                let suggestions = suggestionsEngine.generateSuggestions(for: answer)
                                if !suggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Improvement Tips")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        
                                        ForEach(suggestions.prefix(3), id: \.title) { suggestion in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "lightbulb.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(Color.orange)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(suggestion.title)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(AppTheme.textPrimary)
                                                    Text(suggestion.description)
                                                        .font(.system(size: 12))
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
                    if let transcription = question.answer?.transcription, transcription != "No audio recorded" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcription")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text(transcription)
                                .font(.system(size: 14))
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text(feedback)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
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

struct MetricBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 10, height: 10)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 10))
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
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatTime(audioPlayer.currentTime))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Text(formatTime(audioPlayer.duration))
                        .font(.system(size: 12, weight: .medium))
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
            // Configure audio session to play through speakers
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
        
        // Deactivate audio session
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
