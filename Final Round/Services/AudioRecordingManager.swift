import Foundation
import AVFoundation
import Combine

final class AudioRecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var isAuthorized = false
    
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var wasInterrupted = false
    
    init() {
        checkAuthorization()
        setupInterruptionHandling()
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
        
        // Stop any existing recording
        stopRecording()
        
        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(questionId.uuidString).m4a")
        currentRecordingURL = audioFilename
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("❌ Failed to set up audio session: \(error.localizedDescription)")
            return nil
        }
        
        // Configure recorder settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,  // Whisper works well with 16kHz
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            DispatchQueue.main.async {
                self.isRecording = true
            }
            print("✅ Started recording to: \(audioFilename.lastPathComponent)")
            return audioFilename
        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
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
        
        // Stop the recorder
        if recorder.isRecording {
            recorder.stop()
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        let url = currentRecordingURL
        currentRecordingURL = nil
        audioRecorder = nil
        wasInterrupted = false
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
        
        // Verify the file exists and has content
        if let url = url {
            if FileManager.default.fileExists(atPath: url.path) {
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
}
