import Foundation
import AVFoundation
import Combine

final class AudioRecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var isAuthorized = false
    
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    
    init() {
        checkAuthorization()
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
    
    func stopRecording() -> URL? {
        guard isRecording, let recorder = audioRecorder else {
            return nil
        }
        
        recorder.stop()
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        let url = currentRecordingURL
        currentRecordingURL = nil
        audioRecorder = nil
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
        
        print("✅ Stopped recording, saved to: \(url?.lastPathComponent ?? "unknown")")
        return url
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
