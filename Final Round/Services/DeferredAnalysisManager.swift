import Foundation
import Combine
import SwiftUI

// MARK: - Pending Answer Model

/// Stores data needed for deferred analysis after the interview ends
struct PendingAnswer: Identifiable {
    let id: UUID
    let questionIndex: Int
    let audioURL: URL?
    let eyeContactMetrics: EyeContactMetrics?
    let timeSpent: TimeInterval?
    let questionText: String
    let questionId: UUID
    let experienceLevel: String
    
    init(
        id: UUID = UUID(),
        questionIndex: Int,
        audioURL: URL?,
        eyeContactMetrics: EyeContactMetrics?,
        timeSpent: TimeInterval?,
        questionText: String,
        questionId: UUID,
        experienceLevel: String = "Mid Level"
    ) {
        self.id = id
        self.questionIndex = questionIndex
        self.audioURL = audioURL
        self.eyeContactMetrics = eyeContactMetrics
        self.timeSpent = timeSpent
        self.questionText = questionText
        self.questionId = questionId
        self.experienceLevel = experienceLevel
    }
}

// MARK: - Analysis State

/// Represents the current state of analysis for a single question
enum QuestionAnalysisState {
    case pending
    case queued          // Added to background queue
    case transcribing
    case analyzingTone
    case evaluating
    case complete(QuestionAnswer)
    case failed(String)
    case skipped
    
    var displayText: String {
        switch self {
        case .pending: return "Waiting..."
        case .queued: return "In queue..."
        case .transcribing: return "Transcribing audio..."
        case .analyzingTone: return "Analyzing speech patterns..."
        case .evaluating: return "Evaluating response..."
        case .complete: return "Complete"
        case .failed(let error): return "Failed: \(error)"
        case .skipped: return "Skipped"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .queued, .transcribing, .analyzingTone, .evaluating:
            return true
        default:
            return false
        }
    }
    
    var isComplete: Bool {
        switch self {
        case .complete, .failed, .skipped:
            return true
        default:
            return false
        }
    }
}

// Custom Equatable conformance - compare by case, not by associated value contents
extension QuestionAnalysisState: Equatable {
    static func == (lhs: QuestionAnalysisState, rhs: QuestionAnalysisState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.queued, .queued),
             (.transcribing, .transcribing),
             (.analyzingTone, .analyzingTone),
             (.evaluating, .evaluating),
             (.complete, .complete),
             (.skipped, .skipped):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Overall Analysis Progress

struct AnalysisProgress {
    let currentQuestionIndex: Int
    let totalQuestions: Int
    let currentState: QuestionAnalysisState
    
    var progressFraction: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(currentQuestionIndex) / Double(totalQuestions)
    }
    
    var progressText: String {
        "Analyzing \(currentQuestionIndex + 1) of \(totalQuestions) questions..."
    }
}

// MARK: - Deferred Analysis Manager

/// Manages background processing of interview answers
/// Processes answers immediately in the background as they're submitted
/// Only unprocessed answers show loading animations in the summary view
final class DeferredAnalysisManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current analysis state for each question (indexed by question index)
    @Published private(set) var questionStates: [Int: QuestionAnalysisState] = [:]
    
    /// Overall progress of the analysis
    @Published private(set) var progress: AnalysisProgress?
    
    /// Whether analysis is currently in progress (any question being processed)
    @Published private(set) var isAnalyzing = false
    
    /// Number of completed analyses
    @Published private(set) var completedCount = 0
    
    /// Total number of questions to analyze
    @Published private(set) var totalCount = 0
    
    // MARK: - Private Properties
    
    private let groqService = GroqService.shared
    private let toneAnalyzer = ToneConfidenceAnalyzer()
    private var role: String = ""
    
    // Serial queue for processing answers one at a time
    private var processingQueue: [PendingAnswer] = []
    private var isProcessingQueue = false
    private var currentProcessingTask: Task<Void, Never>?
    
    // Callback to update session when analysis completes
    private var sessionUpdateCallback: ((Int, QuestionAnswer) -> Void)?
    
    // MARK: - Public Methods
    
    /// Set the role for evaluation context
    func setRole(_ role: String) {
        self.role = role
    }
    
    /// Set callback for when analysis completes (to update session)
    func setSessionUpdateCallback(_ callback: @escaping (Int, QuestionAnswer) -> Void) {
        self.sessionUpdateCallback = callback
    }
    
    /// Submit a single answer for immediate background processing
    /// Called right after each question is answered (during the interview)
    @MainActor
    func submitForBackgroundProcessing(_ pending: PendingAnswer) {
        totalCount += 1
        questionStates[pending.questionIndex] = .queued
        processingQueue.append(pending)
        
        print("📥 Queued question \(pending.questionIndex + 1) for background analysis")
        
        // Start processing if not already running
        startProcessingIfNeeded()
    }
    
    /// Get the current state for a specific question
    func stateForQuestion(_ index: Int) -> QuestionAnalysisState {
        return questionStates[index] ?? .pending
    }
    
    /// Get the completed answer for a question if available
    func completedAnswer(for index: Int) -> QuestionAnswer? {
        if case .complete(let answer) = questionStates[index] {
            return answer
        }
        return nil
    }
    
    /// Check if all queued items have been processed
    var allProcessingComplete: Bool {
        processingQueue.isEmpty && !isProcessingQueue
    }
    
    /// Process any remaining items in the queue (called when entering summary view)
    /// This ensures any last-minute items get processed
    @MainActor
    func finishRemainingAnalysis() async {
        // Wait for current processing to complete
        while isProcessingQueue || !processingQueue.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // Update isAnalyzing state
        isAnalyzing = false
        progress = nil
        print("✅ All background analysis complete")
    }
    
    /// Mark a question as skipped (no analysis needed)
    @MainActor
    func markAsSkipped(_ questionIndex: Int) {
        questionStates[questionIndex] = .skipped
    }
    
    /// Initialize states from existing session data (for viewing historical sessions)
    /// This marks questions with existing answers as complete
    func initializeFromSession(_ session: InterviewSession) {
        for (index, question) in session.questions.enumerated() {
            if let answer = question.answer {
                questionStates[index] = .complete(answer)
                completedCount += 1
            } else {
                questionStates[index] = .skipped
            }
        }
        totalCount = session.questions.count
    }
    
    /// Reset the manager for a new session
    @MainActor
    func reset() {
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        processingQueue = []
        questionStates = [:]
        progress = nil
        isAnalyzing = false
        isProcessingQueue = false
        completedCount = 0
        totalCount = 0
        role = ""
        sessionUpdateCallback = nil
    }
    
    // MARK: - Legacy Support (for summary view that expects queuePendingAnswers)
    
    /// Queue pending answers - for backwards compatibility
    /// Now just processes any that aren't already complete
    @MainActor
    func queuePendingAnswers(_ answers: [PendingAnswer], role: String) {
        self.role = role
        
        // Only queue answers that haven't been processed yet
        for answer in answers {
            if questionStates[answer.questionIndex] == nil {
                totalCount += 1
                questionStates[answer.questionIndex] = .queued
                processingQueue.append(answer)
            }
        }
        
        startProcessingIfNeeded()
    }
    
    /// Process all pending answers - for backwards compatibility with summary view
    @MainActor
    func processAllPendingAnswers(
        updateSession: @escaping (Int, QuestionAnswer) -> Void
    ) async {
        self.sessionUpdateCallback = updateSession
        
        // Start processing if not already running
        startProcessingIfNeeded()
        
        // Wait for all processing to complete
        await finishRemainingAnalysis()
    }
    
    // MARK: - Private Processing Methods
    
    @MainActor
    private func startProcessingIfNeeded() {
        guard !isProcessingQueue else { return }
        guard !processingQueue.isEmpty else { return }
        
        isProcessingQueue = true
        isAnalyzing = true
        
        currentProcessingTask = Task {
            await processQueueSequentially()
        }
    }
    
    @MainActor
    private func processQueueSequentially() async {
        while !processingQueue.isEmpty {
            let pending = processingQueue.removeFirst()
            
            // Update progress
            let remainingCount = processingQueue.count
            progress = AnalysisProgress(
                currentQuestionIndex: totalCount - remainingCount - 1,
                totalQuestions: totalCount,
                currentState: .transcribing
            )
            
            do {
                let answer = try await processAnswer(pending)
                
                // Update session with completed answer
                sessionUpdateCallback?(pending.questionIndex, answer)
                
                // Mark as complete with animation
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    questionStates[pending.questionIndex] = .complete(answer)
                    completedCount += 1
                }
                
                print("✅ Background analysis complete for question \(pending.questionIndex + 1)")
                
            } catch {
                print("❌ Background analysis failed for question \(pending.questionIndex + 1): \(error.localizedDescription)")
                
                // Create a minimal answer with error info
                let failedAnswer = QuestionAnswer(
                    transcription: "Analysis failed",
                    audioURL: pending.audioURL?.lastPathComponent,
                    evaluation: AnswerEvaluation(
                        score: 0,
                        strengths: [],
                        improvements: ["Analysis could not be completed: \(error.localizedDescription)"],
                        feedback: "Unable to analyze this response. Please try again."
                    ),
                    eyeContactMetrics: pending.eyeContactMetrics,
                    timeSpent: pending.timeSpent
                )
                
                sessionUpdateCallback?(pending.questionIndex, failedAnswer)
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    questionStates[pending.questionIndex] = .failed(error.localizedDescription)
                    completedCount += 1
                }
            }
            
            // Small delay between questions to prevent rate limiting
            if !processingQueue.isEmpty {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        isProcessingQueue = false
        
        // Only set isAnalyzing to false if we're done (no more items queued)
        if processingQueue.isEmpty {
            isAnalyzing = false
            progress = nil
        }
    }
    
    @MainActor
    private func processAnswer(_ pending: PendingAnswer) async throws -> QuestionAnswer {
        var transcription = "No audio recorded"
        var evaluation: AnswerEvaluation?
        var toneAnalysis: ToneAnalysis?
        var confidenceScore: Double?
        
        // Stage 1: Transcription
        if let audioURL = pending.audioURL {
            withAnimation(.easeInOut(duration: 0.2)) {
                questionStates[pending.questionIndex] = .transcribing
            }
            
            print("🎤 [BG] Transcribing audio for question \(pending.questionIndex + 1)...")
            transcription = try await groqService.transcribeAudio(audioURL: audioURL)
            print("✅ [BG] Transcription complete: \(transcription.prefix(50))...")
            
            // Check for silent audio
            if transcription == "[No speech detected]" {
                return QuestionAnswer(
                    transcription: transcription,
                    audioURL: audioURL.lastPathComponent,
                    evaluation: AnswerEvaluation(
                        score: 0,
                        strengths: [],
                        improvements: ["No speech was detected in your answer. Please speak clearly into the microphone."],
                        feedback: "No speech was detected. Make sure your microphone is working and speak clearly during your answer."
                    ),
                    eyeContactMetrics: pending.eyeContactMetrics,
                    timeSpent: pending.timeSpent
                )
            }
            
            // Stage 2: Tone Analysis
            withAnimation(.easeInOut(duration: 0.2)) {
                questionStates[pending.questionIndex] = .analyzingTone
            }
            
            print("🎵 [BG] Analyzing tone for question \(pending.questionIndex + 1)...")
            toneAnalysis = try await toneAnalyzer.analyzeAudioTone(
                audioURL: audioURL,
                transcription: transcription
            )
            
            if let tone = toneAnalysis, let eyeContact = pending.eyeContactMetrics {
                confidenceScore = toneAnalyzer.calculateConfidenceScore(
                    toneAnalysis: tone,
                    eyeContactPercentage: eyeContact.percentage
                )
                print("✅ [BG] Confidence score: \(String(format: "%.1f", confidenceScore ?? 0))/10")
            }
            
            // Stage 3: Answer Evaluation
            withAnimation(.easeInOut(duration: 0.2)) {
                questionStates[pending.questionIndex] = .evaluating
            }
            
            print("🤔 [BG] Evaluating answer for question \(pending.questionIndex + 1) (experience: \(pending.experienceLevel))...")
            evaluation = try await groqService.evaluateAnswer(
                question: pending.questionText,
                answer: transcription,
                role: role,
                experienceLevel: pending.experienceLevel
            )
            print("✅ [BG] Evaluation score: \(evaluation?.score ?? 0)")
        }
        
        return QuestionAnswer(
            transcription: transcription,
            audioURL: pending.audioURL?.lastPathComponent,
            evaluation: evaluation,
            eyeContactMetrics: pending.eyeContactMetrics,
            confidenceScore: confidenceScore,
            toneAnalysis: toneAnalysis,
            timeSpent: pending.timeSpent
        )
    }
}
