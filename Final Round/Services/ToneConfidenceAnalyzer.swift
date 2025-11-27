import Foundation
import AVFoundation
import SoundAnalysis
import NaturalLanguage
import Accelerate

/// Analyzes audio tone and text sentiment to generate confidence scores
/// Uses ARM-optimized frameworks: SoundAnalysis (Neural Engine), Accelerate (NEON SIMD), NaturalLanguage (CoreML)
final class ToneConfidenceAnalyzer {
    
    // MARK: - Audio Analysis
    
    /// Analyzes audio features using SoundAnalysis and Accelerate frameworks
    func analyzeAudioTone(audioURL: URL, transcription: String) async throws -> ToneAnalysis {
        // Load audio file
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AnalysisError.bufferCreationFailed
        }
        
        try audioFile.read(into: buffer)
        
        // Extract audio features using Accelerate framework (ARM NEON optimized)
        let audioFeatures = extractAudioFeatures(from: buffer)
        
        // Calculate speech pace from transcription
        let wordCount = transcription.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let duration = Double(frameCount) / format.sampleRate
        let speechPace = duration > 0 ? (Double(wordCount) / duration) * 60 : 0 // WPM
        
        // Analyze sentiment from transcription
        let sentiment = analyzeSentiment(text: transcription)
        
        return ToneAnalysis(
            speechPace: speechPace,
            pauseCount: audioFeatures.pauseCount,
            averagePauseDuration: audioFeatures.averagePauseDuration,
            volumeVariation: audioFeatures.volumeVariation,
            sentiment: sentiment
        )
    }
    
    /// Calculates confidence score (1-10) based on tone analysis
    func calculateConfidenceScore(toneAnalysis: ToneAnalysis, eyeContactPercentage: Double) -> Double {
        var score = 5.0 // Base score
        
        // Speech pace contribution (±2 points)
        // Ideal pace: 120-150 WPM
        let paceScore: Double
        switch toneAnalysis.speechPace {
        case 120...150:
            paceScore = 2.0
        case 100..<120, 150..<180:
            paceScore = 1.0
        case 90..<100, 180..<200:
            paceScore = 0.0
        default:
            paceScore = -1.0
        }
        score += paceScore
        
        // Pause analysis contribution (±1 point)
        // Moderate pauses are good (2-5 per minute)
        let pausesPerMinute = Double(toneAnalysis.pauseCount) / (toneAnalysis.averagePauseDuration * Double(toneAnalysis.pauseCount) / 60)
        let pauseScore: Double
        switch pausesPerMinute {
        case 2...5:
            pauseScore = 1.0
        case 1..<2, 5..<8:
            pauseScore = 0.5
        default:
            pauseScore = 0.0
        }
        score += pauseScore
        
        // Volume variation contribution (±1 point)
        // Moderate variation shows engagement
        let volumeScore: Double
        switch toneAnalysis.volumeVariation {
        case 0.3...0.7:
            volumeScore = 1.0
        case 0.2..<0.3, 0.7..<0.8:
            volumeScore = 0.5
        default:
            volumeScore = 0.0
        }
        score += volumeScore
        
        // Sentiment contribution (±1.5 points)
        let sentimentScore = (toneAnalysis.sentiment.score + 1) / 2 * 1.5 // Map -1...1 to 0...1.5
        score += sentimentScore
        
        // Eye contact contribution (±1.5 points)
        let eyeContactScore = eyeContactPercentage / 100 * 1.5
        score += eyeContactScore
        
        // Clamp to 1-10 range
        return min(10, max(1, score))
    }
    
    // MARK: - Private Audio Processing (ARM Accelerate Framework)
    
    private struct AudioFeatures {
        let pauseCount: Int
        let averagePauseDuration: TimeInterval
        let volumeVariation: Double
    }
    
    private func extractAudioFeatures(from buffer: AVAudioPCMBuffer) -> AudioFeatures {
        guard let channelData = buffer.floatChannelData?[0] else {
            return AudioFeatures(pauseCount: 0, averagePauseDuration: 0, volumeVariation: 0)
        }
        
        let frameLength = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        
        // Calculate RMS (Root Mean Square) for volume analysis using Accelerate
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        
        // Detect pauses by analyzing amplitude over time
        let windowSize = Int(sampleRate * 0.1) // 100ms windows
        var pauseCount = 0
        var pauseDurations: [TimeInterval] = []
        var currentPauseDuration: TimeInterval = 0
        var volumes: [Float] = []
        
        for i in stride(from: 0, to: frameLength, by: windowSize) {
            let length = min(windowSize, frameLength - i)
            var windowRMS: Float = 0
            vDSP_rmsqv(channelData.advanced(by: i), 1, &windowRMS, vDSP_Length(length))
            
            volumes.append(windowRMS)
            
            // Pause threshold (adjust based on testing)
            let pauseThreshold: Float = 0.02
            if windowRMS < pauseThreshold {
                currentPauseDuration += Double(windowSize) / sampleRate
            } else if currentPauseDuration > 0.3 { // Minimum pause duration: 300ms
                pauseCount += 1
                pauseDurations.append(currentPauseDuration)
                currentPauseDuration = 0
            } else {
                currentPauseDuration = 0
            }
        }
        
        // Calculate volume variation (standard deviation)
        let volumeVariation: Double
        if volumes.count > 1 {
            var mean: Float = 0
            var stdDev: Float = 0
            vDSP_normalize(volumes, 1, nil, 1, &mean, &stdDev, vDSP_Length(volumes.count))
            volumeVariation = min(1.0, Double(stdDev))
        } else {
            volumeVariation = 0
        }
        
        let averagePauseDuration = pauseDurations.isEmpty ? 0 : pauseDurations.reduce(0, +) / Double(pauseDurations.count)
        
        return AudioFeatures(
            pauseCount: pauseCount,
            averagePauseDuration: averagePauseDuration,
            volumeVariation: volumeVariation
        )
    }
    
    // MARK: - Text Sentiment Analysis (NaturalLanguage Framework)
    
    private func analyzeSentiment(text: String) -> SentimentScore {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        // NaturalLanguage returns sentiment as string "-1.0" to "1.0"
        let score = Double(sentiment?.rawValue ?? "0") ?? 0
        
        // Calculate confidence based on text length and clarity
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let confidence = min(1.0, Double(wordCount) / 50.0) // More words = higher confidence
        
        return SentimentScore(score: score, confidence: confidence)
    }
    
    // MARK: - Filler Word Detection
    
    func detectFillerWords(in transcription: String) -> [String: Int] {
        let fillerWords = [
            "um", "uh", "like", "you know", "actually", "basically",
            "literally", "sort of", "kind of", "i mean", "so", "well"
        ]
        
        let lowercased = transcription.lowercased()
        var fillerCounts: [String: Int] = [:]
        
        for filler in fillerWords {
            let count = lowercased.components(separatedBy: filler).count - 1
            if count > 0 {
                fillerCounts[filler] = count
            }
        }
        
        return fillerCounts
    }
    
    // MARK: - Confidence Indicators
    
    func analyzeConfidenceIndicators(in transcription: String) -> ConfidenceIndicators {
        let lowercased = transcription.lowercased()
        
        // Positive indicators
        let assertiveWords = ["will", "can", "definitely", "certainly", "confident", "sure", "absolutely"]
        let assertiveCount = assertiveWords.reduce(0) { count, word in
            count + (lowercased.components(separatedBy: word).count - 1)
        }
        
        // Negative indicators
        let hesitantWords = ["maybe", "perhaps", "might", "possibly", "i think", "i guess", "not sure"]
        let hesitantCount = hesitantWords.reduce(0) { count, word in
            count + (lowercased.components(separatedBy: word).count - 1)
        }
        
        let wordCount = transcription.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        
        return ConfidenceIndicators(
            assertiveWordCount: assertiveCount,
            hesitantWordCount: hesitantCount,
            assertivePercentage: wordCount > 0 ? Double(assertiveCount) / Double(wordCount) * 100 : 0,
            hesitantPercentage: wordCount > 0 ? Double(hesitantCount) / Double(wordCount) * 100 : 0
        )
    }
}

// MARK: - Supporting Types

struct ConfidenceIndicators {
    let assertiveWordCount: Int
    let hesitantWordCount: Int
    let assertivePercentage: Double
    let hesitantPercentage: Double
}

enum AnalysisError: LocalizedError {
    case bufferCreationFailed
    case audioFileReadFailed
    case invalidAudioFormat
    
    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .audioFileReadFailed:
            return "Failed to read audio file"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
}

