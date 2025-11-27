import Foundation

/// Generates contextual improvement suggestions based on interview analytics
final class ImprovementSuggestionsEngine {
    
    struct Suggestion {
        let category: SuggestionCategory
        let title: String
        let description: String
        let priority: Priority
        
        enum Priority: Int {
            case high = 3
            case medium = 2
            case low = 1
        }
    }
    
    enum SuggestionCategory: String {
        case eyeContact = "Eye Contact"
        case speechPace = "Speech Pace"
        case confidence = "Confidence"
        case pauses = "Pauses"
        case tone = "Tone"
        case content = "Content"
    }
    
    // MARK: - Public Methods
    
    func generateSuggestions(for answer: QuestionAnswer) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        // Eye contact suggestions
        if let eyeContact = answer.eyeContactMetrics {
            suggestions.append(contentsOf: analyzeEyeContact(eyeContact))
        }
        
        // Tone and pace suggestions
        if let tone = answer.toneAnalysis {
            suggestions.append(contentsOf: analyzeTone(tone))
        }
        
        // Confidence suggestions
        if let confidence = answer.confidenceScore {
            suggestions.append(contentsOf: analyzeConfidence(confidence, tone: answer.toneAnalysis))
        }
        
        // Time management suggestions
        if let timeSpent = answer.timeSpent {
            suggestions.append(contentsOf: analyzeTimeSpent(timeSpent))
        }
        
        // Content quality suggestions
        if let evaluation = answer.evaluation {
            suggestions.append(contentsOf: analyzeContent(evaluation, transcription: answer.transcription))
        }
        
        // Sort by priority
        return suggestions.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    func generateSessionSummary(for session: InterviewSession) -> SessionSummary {
        let allSuggestions = session.questions
            .compactMap { $0.answer }
            .flatMap { generateSuggestions(for: $0) }
        
        // Group by category and count
        var categoryFrequency: [SuggestionCategory: Int] = [:]
        for suggestion in allSuggestions {
            categoryFrequency[suggestion.category, default: 0] += 1
        }
        
        // Find top areas for improvement
        let topAreas = categoryFrequency
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        
        // Generate overall recommendations
        let overallRecommendations = generateOverallRecommendations(
            session: session,
            topAreas: Array(topAreas)
        )
        
        return SessionSummary(
            topAreasForImprovement: Array(topAreas),
            overallRecommendations: overallRecommendations,
            strengths: identifyStrengths(session: session)
        )
    }
    
    // MARK: - Private Analysis Methods
    
    private func analyzeEyeContact(_ metrics: EyeContactMetrics) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        switch metrics.percentage {
        case 0..<30:
            suggestions.append(Suggestion(
                category: .eyeContact,
                title: "Improve Eye Contact",
                description: "You maintained eye contact only \(String(format: "%.0f%%", metrics.percentage)) of the time. Try to look directly at the camera more frequently. Practice by placing a small sticky note near your camera lens as a focal point.",
                priority: .high
            ))
        case 30..<50:
            suggestions.append(Suggestion(
                category: .eyeContact,
                title: "Increase Eye Contact",
                description: "Your eye contact was at \(String(format: "%.0f%%", metrics.percentage)). Aim for 60-80% to appear more engaged and confident. Remember to glance at the camera naturally, not continuously.",
                priority: .medium
            ))
        case 50..<60:
            suggestions.append(Suggestion(
                category: .eyeContact,
                title: "Good Eye Contact",
                description: "You maintained \(String(format: "%.0f%%", metrics.percentage)) eye contact. Try to increase this slightly to 60-80% for optimal engagement.",
                priority: .low
            ))
        default:
            break // Good eye contact, no suggestion needed
        }
        
        return suggestions
    }
    
    private func analyzeTone(_ tone: ToneAnalysis) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        // Speech pace analysis
        switch tone.speechPace {
        case 0..<100:
            suggestions.append(Suggestion(
                category: .speechPace,
                title: "Increase Speaking Pace",
                description: "Your pace of \(String(format: "%.0f", tone.speechPace)) words per minute is quite slow. Try to speak a bit faster (120-150 WPM) to maintain engagement and sound more confident.",
                priority: .medium
            ))
        case 100..<120:
            suggestions.append(Suggestion(
                category: .speechPace,
                title: "Slightly Increase Pace",
                description: "Your speaking pace is good but could be slightly faster. Aim for 120-150 words per minute for optimal clarity and engagement.",
                priority: .low
            ))
        case 180..<200:
            suggestions.append(Suggestion(
                category: .speechPace,
                title: "Slow Down Slightly",
                description: "You're speaking at \(String(format: "%.0f", tone.speechPace)) WPM, which is a bit fast. Try to slow down to 120-150 WPM for better clarity.",
                priority: .medium
            ))
        case 200...:
            suggestions.append(Suggestion(
                category: .speechPace,
                title: "Reduce Speaking Speed",
                description: "Your pace of \(String(format: "%.0f", tone.speechPace)) WPM is too fast. Slow down to 120-150 WPM. Take breaths between thoughts and emphasize key points.",
                priority: .high
            ))
        default:
            break // Good pace
        }
        
        // Pause analysis
        if tone.pauseCount == 0 {
            suggestions.append(Suggestion(
                category: .pauses,
                title: "Add Strategic Pauses",
                description: "You didn't pause during your answer. Strategic pauses help emphasize points and give you time to think. Aim for 2-5 natural pauses per minute.",
                priority: .medium
            ))
        } else if tone.pauseCount > 10 && tone.averagePauseDuration > 2.0 {
            suggestions.append(Suggestion(
                category: .pauses,
                title: "Reduce Long Pauses",
                description: "You had \(tone.pauseCount) pauses averaging \(String(format: "%.1f", tone.averagePauseDuration))s. Practice your answers to reduce thinking time and maintain flow.",
                priority: .high
            ))
        }
        
        // Sentiment analysis
        switch tone.sentiment.score {
        case -1.0..<(-0.3):
            suggestions.append(Suggestion(
                category: .tone,
                title: "Use More Positive Language",
                description: "Your tone came across as somewhat negative. Try to frame experiences positively, focusing on learnings and growth even when discussing challenges.",
                priority: .medium
            ))
        case -0.3..<0.1:
            suggestions.append(Suggestion(
                category: .tone,
                title: "Add More Enthusiasm",
                description: "Your tone was neutral. Show more enthusiasm about your experiences and the role. Positive energy is contagious in interviews.",
                priority: .low
            ))
        default:
            break // Good sentiment
        }
        
        return suggestions
    }
    
    private func analyzeConfidence(_ score: Double, tone: ToneAnalysis?) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        switch score {
        case 1..<4:
            suggestions.append(Suggestion(
                category: .confidence,
                title: "Build Confidence",
                description: "Your confidence score was low (\(String(format: "%.1f", score))/10). Practice your answers, maintain eye contact, and use assertive language. Remember your achievements and speak about them with pride.",
                priority: .high
            ))
        case 4..<6:
            suggestions.append(Suggestion(
                category: .confidence,
                title: "Boost Your Confidence",
                description: "Your confidence score was \(String(format: "%.1f", score))/10. Use more definitive statements ('I will' vs 'I might'), maintain better eye contact, and reduce filler words.",
                priority: .medium
            ))
        case 6..<7:
            suggestions.append(Suggestion(
                category: .confidence,
                title: "Good Confidence Level",
                description: "Your confidence score of \(String(format: "%.1f", score))/10 is good. Continue practicing to reach 8+ by refining your delivery and maintaining strong eye contact.",
                priority: .low
            ))
        default:
            break // Excellent confidence
        }
        
        return suggestions
    }
    
    private func analyzeTimeSpent(_ timeSpent: TimeInterval) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        switch timeSpent {
        case 0..<30:
            suggestions.append(Suggestion(
                category: .content,
                title: "Provide More Detail",
                description: "Your answer was quite brief (\(Int(timeSpent))s). Aim for 60-90 seconds per answer. Use the STAR method (Situation, Task, Action, Result) to structure longer, more detailed responses.",
                priority: .medium
            ))
        case 120...:
            suggestions.append(Suggestion(
                category: .content,
                title: "Be More Concise",
                description: "Your answer took \(Int(timeSpent))s. Aim for 60-90 seconds. Practice condensing your thoughts and focusing on the most relevant points.",
                priority: .medium
            ))
        default:
            break // Good timing
        }
        
        return suggestions
    }
    
    private func analyzeContent(_ evaluation: AnswerEvaluation, transcription: String) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        // Based on evaluation score
        if evaluation.score < 70 {
            suggestions.append(Suggestion(
                category: .content,
                title: "Strengthen Your Content",
                description: "Your answer scored \(evaluation.score)/100. Review the feedback and focus on: \(evaluation.improvements.first ?? "providing more specific examples and details").",
                priority: .high
            ))
        }
        
        // Check for filler words
        let fillerWords = ["um", "uh", "like", "you know"]
        let fillerCount = fillerWords.reduce(0) { count, word in
            count + (transcription.lowercased().components(separatedBy: word).count - 1)
        }
        
        if fillerCount > 5 {
            suggestions.append(Suggestion(
                category: .confidence,
                title: "Reduce Filler Words",
                description: "You used \(fillerCount) filler words (um, uh, like, you know). Practice pausing silently instead of using fillers. This will make you sound more confident and polished.",
                priority: .medium
            ))
        }
        
        return suggestions
    }
    
    private func generateOverallRecommendations(session: InterviewSession, topAreas: [SuggestionCategory]) -> [String] {
        var recommendations: [String] = []
        
        // Based on top areas for improvement
        for area in topAreas.prefix(3) {
            switch area {
            case .eyeContact:
                recommendations.append("Practice maintaining eye contact by recording yourself and reviewing the footage. Place a small marker near your camera as a focal point.")
            case .speechPace:
                recommendations.append("Record yourself speaking and time your pace. Practice with a metronome or timer to maintain 120-150 words per minute.")
            case .confidence:
                recommendations.append("Prepare and rehearse your key stories using the STAR method. Practice with friends or mentors to build confidence.")
            case .pauses:
                recommendations.append("Practice strategic pausing. Use pauses to emphasize key points rather than as thinking time. Prepare your answers in advance.")
            case .tone:
                recommendations.append("Focus on positive framing. Even when discussing challenges, emphasize learnings and growth. Show enthusiasm for the role and company.")
            case .content:
                recommendations.append("Use the STAR method for behavioral questions. Prepare 5-7 key stories that demonstrate your skills and achievements.")
            }
        }
        
        // Add general recommendations based on overall performance
        if session.averageScore < 70 {
            recommendations.append("Review common interview questions for your role and prepare structured answers. Focus on specific examples and quantifiable results.")
        }
        
        if session.averageEyeContact < 50 {
            recommendations.append("Eye contact is crucial for building rapport. Practice video calls with friends to get comfortable looking at the camera.")
        }
        
        return recommendations
    }
    
    private func identifyStrengths(session: InterviewSession) -> [String] {
        var strengths: [String] = []
        
        if session.averageEyeContact >= 60 {
            strengths.append("Excellent eye contact - you maintained \(String(format: "%.0f%%", session.averageEyeContact)) throughout the interview")
        }
        
        if session.averageConfidenceScore >= 7 {
            strengths.append("Strong confidence level - your delivery was assured and professional")
        }
        
        if session.averageScore >= 80 {
            strengths.append("High-quality answers - your responses were well-structured and comprehensive")
        }
        
        if session.averageSpeechPace >= 120 && session.averageSpeechPace <= 150 {
            strengths.append("Optimal speaking pace - clear and easy to follow")
        }
        
        // Check for consistent performance
        let scores = session.questions.compactMap { $0.answer?.evaluation?.score }
        if scores.count >= 3 {
            let variance = calculateVariance(scores)
            if variance < 100 {
                strengths.append("Consistent performance across all questions")
            }
        }
        
        return strengths
    }
    
    private func calculateVariance(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let squaredDiffs = values.map { pow(Double($0) - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Supporting Types

struct SessionSummary {
    let topAreasForImprovement: [ImprovementSuggestionsEngine.SuggestionCategory]
    let overallRecommendations: [String]
    let strengths: [String]
}

