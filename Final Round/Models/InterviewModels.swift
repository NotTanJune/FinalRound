import Foundation

struct InterviewQuestion: Identifiable, Codable {
    let id: UUID
    let text: String
    let category: QuestionCategory
    let difficulty: Difficulty
    var answer: QuestionAnswer?
    
    init(id: UUID = UUID(), text: String, category: QuestionCategory, difficulty: Difficulty, answer: QuestionAnswer? = nil) {
        self.id = id
        self.text = text
        self.category = category
        self.difficulty = difficulty
        self.answer = answer
    }
}

struct QuestionAnswer: Codable {
    let transcription: String
    let audioURL: String?
    let videoURL: String?
    let evaluation: AnswerEvaluation?
    let timestamp: Date
    let eyeContactMetrics: EyeContactMetrics?
    let confidenceScore: Double?
    let toneAnalysis: ToneAnalysis?
    let timeSpent: TimeInterval?
    
    init(transcription: String, audioURL: String? = nil, videoURL: String? = nil, evaluation: AnswerEvaluation? = nil, timestamp: Date = Date(), eyeContactMetrics: EyeContactMetrics? = nil, confidenceScore: Double? = nil, toneAnalysis: ToneAnalysis? = nil, timeSpent: TimeInterval? = nil) {
        self.transcription = transcription
        self.audioURL = audioURL
        self.videoURL = videoURL
        self.evaluation = evaluation
        self.timestamp = timestamp
        self.eyeContactMetrics = eyeContactMetrics
        self.confidenceScore = confidenceScore
        self.toneAnalysis = toneAnalysis
        self.timeSpent = timeSpent
    }
}

// MARK: - Analytics Data Structures

struct EyeContactMetrics: Codable {
    let percentage: Double // 0-100
    let totalDuration: TimeInterval
    let lookingAtCameraDuration: TimeInterval
    let timestamps: [EyeContactTimestamp]
    
    var formattedPercentage: String {
        return String(format: "%.1f%%", percentage)
    }
}

struct EyeContactTimestamp: Codable {
    let time: TimeInterval
    let isLookingAtCamera: Bool
}

struct ToneAnalysis: Codable {
    let speechPace: Double // words per minute
    let pauseCount: Int
    let averagePauseDuration: TimeInterval
    let volumeVariation: Double // 0-1 scale
    let sentiment: SentimentScore
    
    var paceDescription: String {
        switch speechPace {
        case 0..<100: return "Slow"
        case 100..<140: return "Moderate"
        case 140..<180: return "Fast"
        default: return "Very Fast"
        }
    }
    
    var formattedPace: String {
        return String(format: "%.0f WPM", speechPace)
    }
}

struct SentimentScore: Codable {
    let score: Double // -1 (negative) to 1 (positive)
    let confidence: Double // 0-1
    
    var label: String {
        switch score {
        case 0.5...1.0: return "Very Positive"
        case 0.1..<0.5: return "Positive"
        case -0.1...0.1: return "Neutral"
        case -0.5..<(-0.1): return "Negative"
        default: return "Very Negative"
        }
    }
}

struct AnswerEvaluation: Codable {
    let score: Int
    let strengths: [String]
    let improvements: [String]
    let feedback: String
    
    var grade: String {
        switch score {
        case 95...100: return "A+"
        case 90..<95: return "A"
        case 85..<90: return "A-"
        case 80..<85: return "B+"
        case 75..<80: return "B"
        case 70..<75: return "B-"
        case 65..<70: return "C+"
        case 60..<65: return "C"
        case 55..<60: return "C-"
        default: return "D"
        }
    }
    
    var gradeColor: String {
        switch score {
        case 90...100: return "green"
        case 80..<90: return "blue"
        case 70..<80: return "orange"
        default: return "red"
        }
    }
}

enum QuestionCategory: String, CaseIterable, Codable {
    case behavioral = "Behavioral"
    case technical = "Technical"
    case situational = "Situational"
    case general = "General"
}

enum Difficulty: String, CaseIterable, Codable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

struct InterviewSession: Identifiable, Codable {
    let id: UUID
    let role: String
    let difficulty: Difficulty
    let categories: [QuestionCategory]
    let duration: Int // in minutes
    var questions: [InterviewQuestion]
    var answeredCount: Int
    var skippedCount: Int
    var startTime: Date?
    var endTime: Date?
    var userEmail: String?
    var enableAudioRecording: Bool
    var experienceLevel: String // User's experience level for evaluation context
    
    init(id: UUID = UUID(), role: String, difficulty: Difficulty, categories: [QuestionCategory], duration: Int = 0, questions: [InterviewQuestion], answeredCount: Int = 0, skippedCount: Int = 0, startTime: Date? = nil, endTime: Date? = nil, userEmail: String? = nil, enableAudioRecording: Bool = true, experienceLevel: String = "Mid Level") {
        self.id = id
        self.role = role
        self.difficulty = difficulty
        self.categories = categories
        self.duration = duration // Legacy field, actual duration computed from startTime/endTime
        self.questions = questions
        self.answeredCount = answeredCount
        self.skippedCount = skippedCount
        self.startTime = startTime
        self.endTime = endTime
        self.userEmail = userEmail
        self.enableAudioRecording = enableAudioRecording
        self.experienceLevel = experienceLevel
    }
    
    var totalQuestions: Int {
        questions.count
    }
    
    var attemptedQuestions: Int {
        answeredCount + skippedCount
    }
    
    var remainingQuestions: Int {
        totalQuestions - attemptedQuestions
    }
    
    var sessionDuration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var completionRate: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(answeredCount) / Double(totalQuestions)
    }
    
    var averageScore: Double {
        let evaluatedQuestions = questions.compactMap { $0.answer?.evaluation }
        guard !evaluatedQuestions.isEmpty else { return 0 }
        let totalScore = evaluatedQuestions.reduce(0) { $0 + $1.score }
        return Double(totalScore) / Double(evaluatedQuestions.count)
    }
    
    var overallGrade: String {
        let score = Int(averageScore)
        switch score {
        case 95...100: return "A+"
        case 90..<95: return "A"
        case 85..<90: return "A-"
        case 80..<85: return "B+"
        case 75..<80: return "B"
        case 70..<75: return "B-"
        case 65..<70: return "C+"
        case 60..<65: return "C"
        case 55..<60: return "C-"
        default: return "D"
        }
    }
    
    var gradeColor: String {
        let score = Int(averageScore)
        switch score {
        case 90...100: return "green"
        case 80..<90: return "blue"
        case 70..<80: return "orange"
        default: return "red"
        }
    }
    
    var answerRate: Double {
        guard attemptedQuestions > 0 else { return 0 }
        return Double(answeredCount) / Double(attemptedQuestions)
    }
    
    var formattedDuration: String {
        guard let duration = sessionDuration else { return "N/A" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    var formattedDate: String {
        guard let start = startTime else { return "N/A" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: start, relativeTo: Date())
    }
    
    // MARK: - Analytics Computed Properties
    
    var averageEyeContact: Double {
        let answeredQuestions = questions.compactMap { $0.answer }
        let eyeContactMetrics = answeredQuestions.compactMap { $0.eyeContactMetrics }
        guard !eyeContactMetrics.isEmpty else { return 0 }
        let total = eyeContactMetrics.reduce(0.0) { $0 + $1.percentage }
        return total / Double(eyeContactMetrics.count)
    }
    
    var averageConfidenceScore: Double {
        let answeredQuestions = questions.compactMap { $0.answer }
        let confidenceScores = answeredQuestions.compactMap { $0.confidenceScore }
        guard !confidenceScores.isEmpty else { return 0 }
        let total = confidenceScores.reduce(0.0) { $0 + $1 }
        return total / Double(confidenceScores.count)
    }
    
    var averageSpeechPace: Double {
        let answeredQuestions = questions.compactMap { $0.answer }
        let toneAnalyses = answeredQuestions.compactMap { $0.toneAnalysis }
        guard !toneAnalyses.isEmpty else { return 0 }
        let total = toneAnalyses.reduce(0.0) { $0 + $1.speechPace }
        return total / Double(toneAnalyses.count)
    }
}

// Supabase table model
struct InterviewSessionRecord: Codable {
    let id: UUID?
    let user_email: String
    let role: String
    let difficulty: String
    let categories: [String]
    let duration: Int
    let questions: String // JSON string
    let answered_count: Int
    let skipped_count: Int
    let start_time: String?
    let end_time: String?
    let created_at: String?
    
    init(from session: InterviewSession, userEmail: String) throws {
        self.id = session.id
        self.user_email = userEmail
        self.role = session.role
        self.difficulty = session.difficulty.rawValue
        self.categories = session.categories.map { $0.rawValue }
        self.duration = session.duration
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let questionsData = try encoder.encode(session.questions)
        self.questions = String(data: questionsData, encoding: .utf8) ?? "[]"
        
        self.answered_count = session.answeredCount
        self.skipped_count = session.skippedCount
        
        let dateFormatter = ISO8601DateFormatter()
        self.start_time = session.startTime.map { dateFormatter.string(from: $0) }
        self.end_time = session.endTime.map { dateFormatter.string(from: $0) }
        self.created_at = dateFormatter.string(from: Date())
    }
    
    func toSession() throws -> InterviewSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let questionsData = questions.data(using: .utf8) else {
            throw NSError(domain: "InterviewModels", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid questions data"])
        }
        
        let decodedQuestions = try decoder.decode([InterviewQuestion].self, from: questionsData)
        
        let dateFormatter = ISO8601DateFormatter()
        
        return InterviewSession(
            id: id ?? UUID(),
            role: role,
            difficulty: Difficulty(rawValue: difficulty) ?? .medium,
            categories: categories.compactMap { QuestionCategory(rawValue: $0) },
            duration: duration,
            questions: decodedQuestions,
            answeredCount: answered_count,
            skippedCount: skipped_count,
            startTime: start_time.flatMap { dateFormatter.date(from: $0) },
            endTime: end_time.flatMap { dateFormatter.date(from: $0) },
            userEmail: user_email
        )
    }
}

class InterviewQuestionBank {
    static let shared = InterviewQuestionBank()
    
    let allQuestions: [InterviewQuestion] = [
        // Behavioral - Easy
        InterviewQuestion(text: "Tell me about yourself and your background.", category: .behavioral, difficulty: .easy),
        InterviewQuestion(text: "What are your greatest strengths?", category: .behavioral, difficulty: .easy),
        InterviewQuestion(text: "Why do you want to work here?", category: .behavioral, difficulty: .easy),
        InterviewQuestion(text: "Where do you see yourself in 5 years?", category: .behavioral, difficulty: .easy),
        
        // Behavioral - Medium
        InterviewQuestion(text: "Tell me about a time when you had to work under pressure.", category: .behavioral, difficulty: .medium),
        InterviewQuestion(text: "Describe a situation where you had to deal with a difficult colleague.", category: .behavioral, difficulty: .medium),
        InterviewQuestion(text: "Give me an example of when you showed leadership.", category: .behavioral, difficulty: .medium),
        InterviewQuestion(text: "Tell me about a time when you failed and what you learned from it.", category: .behavioral, difficulty: .medium),
        
        // Behavioral - Hard
        InterviewQuestion(text: "Describe a time when you had to make a difficult decision with incomplete information.", category: .behavioral, difficulty: .hard),
        InterviewQuestion(text: "Tell me about a time when you had to influence someone without authority.", category: .behavioral, difficulty: .hard),
        
        // Technical - Easy
        InterviewQuestion(text: "What programming languages are you most comfortable with?", category: .technical, difficulty: .easy),
        InterviewQuestion(text: "Explain what version control is and why it's important.", category: .technical, difficulty: .easy),
        InterviewQuestion(text: "What is your development workflow?", category: .technical, difficulty: .easy),
        
        // Technical - Medium
        InterviewQuestion(text: "Explain the difference between synchronous and asynchronous programming.", category: .technical, difficulty: .medium),
        InterviewQuestion(text: "How would you optimize a slow-running database query?", category: .technical, difficulty: .medium),
        InterviewQuestion(text: "Describe the SOLID principles and give examples.", category: .technical, difficulty: .medium),
        
        // Technical - Hard
        InterviewQuestion(text: "Design a URL shortening service like bit.ly. How would you handle scale?", category: .technical, difficulty: .hard),
        InterviewQuestion(text: "Explain how you would implement a rate limiter for an API.", category: .technical, difficulty: .hard),
        
        // Situational - Easy
        InterviewQuestion(text: "How do you prioritize your tasks when you have multiple deadlines?", category: .situational, difficulty: .easy),
        InterviewQuestion(text: "What would you do if you disagreed with a manager's decision?", category: .situational, difficulty: .easy),
        
        // Situational - Medium
        InterviewQuestion(text: "If you discovered a bug in production right before a major release, what would you do?", category: .situational, difficulty: .medium),
        InterviewQuestion(text: "How would you handle a situation where a team member isn't contributing equally?", category: .situational, difficulty: .medium),
        
        // Situational - Hard
        InterviewQuestion(text: "You notice a critical security vulnerability in a legacy system. How do you approach this?", category: .situational, difficulty: .hard),
        
        // General - Easy
        InterviewQuestion(text: "What motivates you in your work?", category: .general, difficulty: .easy),
        InterviewQuestion(text: "How do you handle feedback and criticism?", category: .general, difficulty: .easy),
        InterviewQuestion(text: "What's your ideal work environment?", category: .general, difficulty: .easy),
        
        // General - Medium
        InterviewQuestion(text: "How do you stay current with industry trends and technologies?", category: .general, difficulty: .medium),
        InterviewQuestion(text: "Describe your approach to learning new technologies.", category: .general, difficulty: .medium),
    ]
    
    func getQuestions(categories: [QuestionCategory], difficulty: Difficulty, count: Int) -> [InterviewQuestion] {
        let filtered = allQuestions.filter { question in
            categories.contains(question.category) && question.difficulty == difficulty
        }
        
        return Array(filtered.shuffled().prefix(count))
    }
}
