import Foundation
import AVFoundation
import Combine
import Accelerate  // ARM NEON optimizations

final class AudioRecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var isAuthorized = false
    
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var wasInterrupted = false
    
    // Pre-configured audio session for faster start
    private var isAudioSessionConfigured = false
    
    // Background queue for file operations (ARM optimized)
    private let fileQueue = DispatchQueue(label: "com.finalround.audio.file", qos: .userInitiated)
    
    init() {
        checkAuthorization()
        setupInterruptionHandling()
        // Pre-configure audio session on init for faster recording start
        preconfigureAudioSession()
    }
    
    /// Pre-configure audio session to reduce latency on first recording
    private func preconfigureAudioSession() {
        // Don't pre-configure on init - this can conflict with AVCaptureSession
        // The audio session will be configured when recording starts
        // This allows the camera to set up first without interference
        print("🎙️ Audio recording manager initialized, session will be configured on first recording")
    }
    
    private func setupInterruptionHandling() {
        // Handle audio session interruptions (e.g., from screen recording, phone calls)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("⚠️ Audio session interrupted (screen recording or other app)")
            wasInterrupted = true
            // Don't stop recording here - let it continue if possible
        case .ended:
            print("✅ Audio session interruption ended")
            wasInterrupted = false
            // Try to resume if we have an active recorder
            if let recorder = audioRecorder, !recorder.isRecording {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    recorder.record()
                    print("✅ Resumed recording after interruption")
                } catch {
                    print("⚠️ Could not resume recording: \(error.localizedDescription)")
                }
            }
        @unknown default:
            break
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func checkAuthorization() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
        case .denied:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                }
            }
        @unknown default:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }
    
    func startRecording(for questionId: UUID) -> URL? {
        guard isAuthorized else {
            print("❌ Audio recording not authorized")
            return nil
        }
        
        // Stop any existing recording first
        if audioRecorder != nil {
            stopRecording()
        }
        
        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(questionId.uuidString).m4a")
        
        // Delete existing file if it exists (prevents prepare failure)
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            try? FileManager.default.removeItem(at: audioFilename)
        }
        
        currentRecordingURL = audioFilename
        
        // Configure audio session - MUST be done carefully to coexist with AVCaptureSession
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use .default mode (not .videoRecording) to avoid conflicts with camera
            // .mixWithOthers is critical for coexisting with AVCaptureSession
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try audioSession.setActive(true)
            isAudioSessionConfigured = true
            
            print("🎙️ Audio session configured:")
            print("   - Category: \(audioSession.category.rawValue)")
            print("   - Mode: \(audioSession.mode.rawValue)")
            print("   - Input: \(audioSession.currentRoute.inputs.first?.portName ?? "none")")
        } catch {
            print("❌ Failed to set up audio session: \(error.localizedDescription)")
            return nil
        }
        
        // ARM-optimized recorder settings for Apple Silicon
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,  // Standard sample rate - more compatible
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            guard let recorder = audioRecorder else {
                print("❌ Failed to create audio recorder")
                return nil
            }
            
            recorder.isMeteringEnabled = true
            
            // prepareToRecord allocates resources - check for failure
            if !recorder.prepareToRecord() {
                print("⚠️ Audio recorder failed to prepare")
                print("   - URL valid: \(audioFilename.isFileURL)")
                print("   - Can write: \(FileManager.default.isWritableFile(atPath: documentsPath.path))")
                // Try to record anyway - sometimes prepare fails but record works
            }
            
            // Start recording
            if !recorder.record() {
                print("❌ Audio recorder failed to start recording")
                // Try one more time after a brief delay
                Thread.sleep(forTimeInterval: 0.1)
                if !recorder.record() {
                    print("❌ Audio recorder retry also failed")
                    audioRecorder = nil
                    return nil
                }
            }
            
            print("✅ Started recording to: \(audioFilename.lastPathComponent)")
            print("   - Recording: \(recorder.isRecording)")
            print("   - Format: \(recorder.format)")
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
            return audioFilename
        } catch {
            print("❌ Failed to create audio recorder: \(error.localizedDescription)")
            return nil
        }
    }
    
    @discardableResult
    func stopRecording() -> URL? {
        // Be more lenient - try to stop even if isRecording is out of sync
        // This can happen during screen recording interruptions
        guard let recorder = audioRecorder else {
            // Check if we have a URL from a previous recording that might still be valid
            if let url = currentRecordingURL, FileManager.default.fileExists(atPath: url.path) {
                print("⚠️ Recorder was nil but found existing recording file")
                let savedURL = url
                currentRecordingURL = nil
                DispatchQueue.main.async {
                    self.isRecording = false
                }
                return savedURL
            }
            print("⚠️ No active recorder to stop")
            return nil
        }
        
        // Stop the recorder immediately
        if recorder.isRecording {
            recorder.stop()
        }
        
        // Update UI state immediately for responsiveness
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        let url = currentRecordingURL
        currentRecordingURL = nil
        audioRecorder = nil
        wasInterrupted = false
        
        // DON'T deactivate audio session between recordings
        // Keeping it active prevents conflicts when starting the next recording
        // The session will be properly cleaned up when the interview ends
        
        // Verify the file exists and has content (fast check)
        if let url = url {
            if FileManager.default.fileExists(atPath: url.path) {
                // Use autoreleasepool for efficient memory handling on ARM
                return autoreleasepool {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        if fileSize > 0 {
                            print("✅ Stopped recording, saved to: \(url.lastPathComponent) (\(fileSize) bytes)")
                            return url
                        } else {
                            print("⚠️ Recording file is empty (screen recording may have interfered)")
                            return nil
                        }
                    } catch {
                        print("⚠️ Could not check recording file: \(error.localizedDescription)")
                        return url // Return it anyway, let caller handle
                    }
                }
            } else {
                print("⚠️ Recording file does not exist")
                return nil
            }
        }
        
        return nil
    }
    
    func deleteRecording(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("✅ Deleted recording: \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to delete recording: \(error.localizedDescription)")
        }
    }
    
    func cleanupAllRecordings() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            let recordings = files.filter { $0.lastPathComponent.hasPrefix("recording_") }
            for recording in recordings {
                try FileManager.default.removeItem(at: recording)
            }
            print("✅ Cleaned up \(recordings.count) recordings")
        } catch {
            print("❌ Failed to cleanup recordings: \(error.localizedDescription)")
        }
    }
    
    /// Call this when the interview session ends to properly cleanup audio session
    func endSession() {
        // Stop any active recording
        stopRecording()
        
        // Now deactivate the audio session since interview is over
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionConfigured = false
            print("✅ Audio session deactivated (interview ended)")
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
}
