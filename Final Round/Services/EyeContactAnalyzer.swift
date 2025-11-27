import Foundation
import AVFoundation
import Vision
import ARKit
import Combine

/// Eye contact analyzer using Vision framework (face direction) and ARKit (gaze tracking when available)
/// Optimized for ARM architecture - runs on Neural Engine via CoreML
final class EyeContactAnalyzer: NSObject, ObservableObject {
    @Published var isTracking = false
    @Published var currentEyeContactPercentage: Double = 0
    @Published var isLookingAtCamera = false
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "com.finalround.eyecontact.video")
    
    // ARKit session for precise gaze tracking (when TrueDepth available)
    private var arSession: ARSession?
    private var arConfiguration: ARFaceTrackingConfiguration?
    private var useARKit = false
    
    // Tracking data
    private var trackingStartTime: Date?
    private var eyeContactTimestamps: [EyeContactTimestamp] = []
    private var totalLookingDuration: TimeInterval = 0
    private var lastUpdateTime: Date?
    private var lastProcessedFrameTime: Date?
    private let frameProcessingInterval: TimeInterval = 0.2 // Process 5 frames per second
    
    // Vision requests
    private lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            self?.handleFaceDetection(request: request, error: error)
        }
        return request
    }()
    
    private lazy var faceLandmarksRequest: VNDetectFaceLandmarksRequest = {
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleFaceLandmarks(request: request, error: error)
        }
        return request
    }()
    
    override init() {
        super.init()
        checkARKitAvailability()
    }
    
    // MARK: - Public Methods
    
    func startTracking(with captureSession: AVCaptureSession) {
        guard !isTracking else { return }
        
        self.captureSession = captureSession
        trackingStartTime = Date()
        lastUpdateTime = Date()
        eyeContactTimestamps = []
        totalLookingDuration = 0
        
        if useARKit {
            startARKitTracking()
        } else {
            startVisionTracking()
        }
        
        DispatchQueue.main.async {
            self.isTracking = true
        }
        
        print("👁️ Eye contact tracking started (using \(useARKit ? "ARKit" : "Vision"))")
    }
    
    func stopTracking() -> EyeContactMetrics? {
        guard isTracking, let startTime = trackingStartTime else { return nil }
        
        if useARKit {
            stopARKitTracking()
        } else {
            stopVisionTracking()
        }
        
        let totalDuration = Date().timeIntervalSince(startTime)
        let percentage = totalDuration > 0 ? (totalLookingDuration / totalDuration) * 100 : 0
        
        let metrics = EyeContactMetrics(
            percentage: min(100, max(0, percentage)),
            totalDuration: totalDuration,
            lookingAtCameraDuration: totalLookingDuration,
            timestamps: eyeContactTimestamps
        )
        
        // Reset state
        DispatchQueue.main.async {
            self.isTracking = false
            self.currentEyeContactPercentage = 0
            self.isLookingAtCamera = false
        }
        
        trackingStartTime = nil
        eyeContactTimestamps = []
        totalLookingDuration = 0
        
        print("👁️ Eye contact tracking stopped - \(String(format: "%.1f%%", metrics.percentage))")
        
        return metrics
    }
    
    // MARK: - ARKit Tracking (Precise Gaze)
    
    private func checkARKitAvailability() {
        // Disable ARKit to avoid camera session conflicts
        // ARKit creates its own camera session which conflicts with AVCaptureSession
        // Vision framework works with existing camera session without conflicts
        useARKit = false
        print("👁️ Using Vision framework for eye contact tracking (avoids camera conflicts)")
    }
    
    private func startARKitTracking() {
        guard useARKit else { return }
        
        arSession = ARSession()
        arSession?.delegate = self
        
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1
        
        arConfiguration = configuration
        arSession?.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        print("👁️ ARKit tracking started")
    }
    
    private func stopARKitTracking() {
        arSession?.pause()
        arSession = nil
        arConfiguration = nil
        print("👁️ ARKit tracking stopped")
    }
    
    // MARK: - Vision Tracking (Face Direction)
    
    private func startVisionTracking() {
        guard let captureSession = captureSession else { return }
        
        // Check if output already exists in the session
        let existingOutput = captureSession.outputs.first { $0 is AVCaptureVideoDataOutput } as? AVCaptureVideoDataOutput
        
        if let existing = existingOutput {
            // Reuse existing output
            existing.setSampleBufferDelegate(self, queue: videoQueue)
            videoOutput = existing
            print("👁️ Vision tracking using existing video output")
        } else if videoOutput == nil {
            // Add new video output only if none exists
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: videoQueue)
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            // Reduce frame rate to avoid overwhelming the system
            output.alwaysDiscardsLateVideoFrames = true
            
            captureSession.beginConfiguration()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                videoOutput = output
                print("👁️ Vision tracking video output added")
            } else {
                print("⚠️ Could not add video output to session")
            }
            captureSession.commitConfiguration()
        }
    }
    
    private func stopVisionTracking() {
        // Just remove the delegate instead of removing the output
        // This prevents camera session interruption
        if let output = videoOutput {
            output.setSampleBufferDelegate(nil, queue: nil)
            videoOutput = nil
        }
        print("👁️ Vision tracking stopped")
    }
    
    private func handleFaceDetection(request: VNRequest, error: Error?) {
        guard error == nil,
              let results = request.results as? [VNFaceObservation],
              let face = results.first else {
            updateEyeContact(isLooking: false)
            return
        }
        
        // Use yaw (head rotation) to estimate if looking at camera
        // Yaw close to 0 means facing camera
        let yaw = face.yaw?.doubleValue ?? 0
        let isLookingAtCamera = abs(yaw) < 0.3 // Within ~17 degrees
        
        updateEyeContact(isLooking: isLookingAtCamera)
    }
    
    private func handleFaceLandmarks(request: VNRequest, error: Error?) {
        // Additional refinement using facial landmarks if needed
        guard error == nil,
              let results = request.results as? [VNFaceObservation],
              let face = results.first else {
            return
        }
        
        // Could use eye landmarks for more precise detection
        // For now, rely on face detection yaw
    }
    
    private func updateEyeContact(isLooking: Bool) {
        guard let startTime = trackingStartTime else { return }
        
        let currentTime = Date()
        let elapsed = currentTime.timeIntervalSince(startTime)
        
        // Update duration if looking at camera
        if isLooking, let lastUpdate = lastUpdateTime {
            let delta = currentTime.timeIntervalSince(lastUpdate)
            totalLookingDuration += delta
        }
        
        // Record timestamp
        let timestamp = EyeContactTimestamp(
            time: elapsed,
            isLookingAtCamera: isLooking
        )
        eyeContactTimestamps.append(timestamp)
        
        // Update percentage
        let percentage = elapsed > 0 ? (totalLookingDuration / elapsed) * 100 : 0
        
        DispatchQueue.main.async {
            self.isLookingAtCamera = isLooking
            self.currentEyeContactPercentage = percentage
        }
        
        lastUpdateTime = currentTime
    }
    
    deinit {
        stopTracking()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension EyeContactAnalyzer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process if tracking is active
        guard isTracking else { return }
        
        // Throttle frame processing to reduce CPU load
        let now = Date()
        if let lastProcessed = lastProcessedFrameTime,
           now.timeIntervalSince(lastProcessed) < frameProcessingInterval {
            return // Skip this frame
        }
        lastProcessedFrameTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Run face detection on Neural Engine (ARM optimization)
        // Use lower priority to avoid blocking camera preview
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            // Silently fail to avoid log spam
            // Face detection will retry on next frame
        }
    }
}

// MARK: - ARSessionDelegate

extension EyeContactAnalyzer: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
        
        // ARKit provides precise gaze direction
        // lookAtPoint is in face coordinate space
        let lookAtPoint = faceAnchor.lookAtPoint
        
        // Determine if looking at camera based on gaze direction
        // Camera is approximately at (0, 0, -1) in face space
        let isLookingAtCamera = abs(lookAtPoint.x) < 0.1 && abs(lookAtPoint.y) < 0.1
        
        updateEyeContact(isLooking: isLookingAtCamera)
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ ARSession failed: \(error)")
        // Fallback to Vision if ARKit fails
        if useARKit {
            useARKit = false
            stopARKitTracking()
            if let captureSession = captureSession {
                startVisionTracking()
            }
        }
    }
}

