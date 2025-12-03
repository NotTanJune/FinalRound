import SwiftUI
import AVFoundation
import Combine

struct InterviewSessionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var session: InterviewSession
    @State private var hasStarted = false
    @State private var currentQuestionIndex = 0
    @State private var showingSummary = false
    @State private var sessionStartTime: Date?
    @State private var sessionEndTime: Date?
    @State private var isTransitioning = false
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var audioManager = AudioRecordingManager()
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var eyeContactAnalyzer = EyeContactAnalyzer()
    @StateObject private var analysisManager = DeferredAnalysisManager()
    @State private var isSavingSession = false
    @State private var isEndingSession = false
    @State private var answeredQuestions: Set<Int> = []
    @State private var skippedQuestions: Set<Int> = []
    @State private var currentRecordingURL: URL?
    @State private var isProcessingAnswer = false
    @State private var questionStartTime: Date?
    @State private var pausedTimeDisplay: String?
    @State private var pendingAnswers: [PendingAnswer] = []
    
    private let accent = AppTheme.accent
    
    init(session: InterviewSession) {
        _session = State(initialValue: session)
    }
    
    var currentQuestion: InterviewQuestion? {
        guard currentQuestionIndex < session.questions.count else { return nil }
        return session.questions[currentQuestionIndex]
    }
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(12)
                            .background(AppTheme.cardBackground)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Interview")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    // Timer
                    if hasStarted {
                        HStack(spacing: 4) {
                            if isEndingSession, let pausedTime = pausedTimeDisplay {
                                // Show paused time when ending session
                                Text(pausedTime)
                                    .font(.system(size: 14, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textSecondary)
                            } else {
                                // Live updating timer
                                TimelineView(.periodic(from: Date(), by: 1.0)) { _ in
                                    Text(timeElapsed())
                                        .font(.system(size: 14, weight: .medium))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isEndingSession ? AppTheme.cardBackground.opacity(0.6) : AppTheme.cardBackground)
                        .cornerRadius(20)
                        .animation(.easeInOut(duration: 0.2), value: isEndingSession)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // Video Card
                ZStack {
                    // Camera Feed
                    if cameraManager.isAuthorized && cameraManager.isConfigured {
                        CameraPreview(session: cameraManager.captureSession)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    } else {
                        Color.black
                        if !cameraManager.isAuthorized {
                            VStack(spacing: 12) {
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("Camera Access Required")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    // Overlay Elements
                    VStack {
                        HStack {
                            // Audio Indicator
                            if audioManager.isRecording {
                                Image(systemName: "waveform")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .padding(12)
                                    .background(AppTheme.primary)
                                    .clipShape(Circle())
                            }
                            Spacer()
                            
                            // Eye Contact Indicator
                            if eyeContactAnalyzer.isTracking {
                                HStack(spacing: 6) {
                                    Image(systemName: eyeContactAnalyzer.isLookingAtCamera ? "eye.fill" : "eye.slash.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                    Text("\(Int(eyeContactAnalyzer.currentEyeContactPercentage))%")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(eyeContactAnalyzer.isLookingAtCamera ? AppTheme.primary : Color.orange)
                                .cornerRadius(20)
                            }
                        }
                        .padding(20)
                        
                        Spacer()
                        
                        // Question Text Overlay
                        if hasStarted {
                            if let question = currentQuestion {
                                VStack(spacing: 12) {
                                    ScrollView(.vertical, showsIndicators: false) {
                                        Text(question.text)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .multilineTextAlignment(.center)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                    }
                                    .frame(maxHeight: 100) // Allow scrolling for long questions
                                    .frame(maxWidth: .infinity)
                                    .background(AppTheme.cardBackground.opacity(0.92))
                                    .cornerRadius(16)
                                    .padding(.horizontal, 24)
                                }
                                .padding(.bottom, 20)
                            }
                        } else {
                            // Start Button Overlay
                            Button {
                                startSession()
                            } label: {
                                Text("Start")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 16)
                                    .background(AppTheme.primary)
                                    .cornerRadius(30)
                                    .shadow(color: AppTheme.primary.opacity(0.4), radius: 10, y: 5)
                            }
                            .padding(.bottom, 40)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(AppTheme.primary, lineWidth: 2)
                )
                .padding(.horizontal, 20)
                
                // Controls Below Camera
                if hasStarted {
                    let isButtonsDisabled = isEndingSession || isTransitioning
                    
                    HStack(spacing: 20) {
                        Button {
                            skipQuestion()
                        } label: {
                            Text("Skip")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isButtonsDisabled ? AppTheme.textSecondary : AppTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.cardBackground)
                                .cornerRadius(16)
                        }
                        .disabled(isButtonsDisabled)
                        .opacity(isButtonsDisabled ? 0.5 : 1)
                        
                        Button {
                            answerQuestion()
                        } label: {
                            HStack(spacing: 8) {
                                if isTransitioning && !isEndingSession {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(currentQuestionIndex < session.questions.count - 1 ? "Next" : "Finish")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isButtonsDisabled ? AppTheme.primary.opacity(0.5) : AppTheme.primary)
                            .cornerRadius(16)
                        }
                        .disabled(isButtonsDisabled)
                        .opacity(isButtonsDisabled ? 0.5 : 1)
                    }
                    .padding(.horizontal, 20)
                    .animation(.easeInOut(duration: 0.2), value: isButtonsDisabled)
                }
                
                // End Call Button (Smaller)
                Button {
                    endSession()
                } label: {
                    if isEndingSession {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 56, height: 56)
                            .background(AppTheme.softRed.opacity(0.6))
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(isTransitioning ? AppTheme.softRed.opacity(0.5) : AppTheme.softRed)
                            .clipShape(Circle())
                    }
                }
                .disabled(isEndingSession || isTransitioning)
                .padding(.bottom, 20)
            }
        }
        .onAppear { cameraManager.start() }
        .onDisappear { cameraManager.stop() }
        .sheet(isPresented: $showingSummary) {
            SessionSummaryView(
                session: $session,
                analysisManager: analysisManager,
                answeredQuestions: session.answeredCount,
                startTime: sessionStartTime ?? Date(),
                endTime: sessionEndTime ?? Date(),
                onDismiss: { 
                    showingSummary = false
                    dismiss()
                },
                onGoHome: {
                    navigateToTab(0)
                },
                onViewResults: {
                    navigateToTab(1)
                }
            )
        }
    }
    
    private func startSession() {
        hasStarted = true
        sessionStartTime = Date()
        session.startTime = Date()
        questionStartTime = Date()
        
        // Configure the analysis manager with role and session update callback
        analysisManager.setRole(session.role)
        analysisManager.setSessionUpdateCallback { [self] questionIndex, answer in
            // Update the session when background analysis completes
            session.questions[questionIndex].answer = answer
        }
        
        // Start eye contact tracking
        eyeContactAnalyzer.startTracking(with: cameraManager.captureSession)
        
        // Start audio recording for the first question if enabled
        if session.enableAudioRecording, let question = currentQuestion {
            currentRecordingURL = audioManager.startRecording(for: question.id)
        }
    }

struct ControlCircleButton: View {
    let icon: String
    let color: Color
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 56, height: 56)
                .background(color)
                .clipShape(Circle())
        }
    }
}
    
    private func answerQuestion() {
        guard !isTransitioning, let question = currentQuestion else { return }
        isTransitioning = true
        
        // Capture time spent synchronously (lightweight)
        let timeSpent = questionStartTime.map { Date().timeIntervalSince($0) }
        
        // IMPORTANT: Stop audio and eye tracking on main thread - AVAudioRecorder requires this
        // These are fast, synchronous operations
        let eyeContactMetrics = eyeContactAnalyzer.stopTracking()
        
        // Stop audio recording if enabled - MUST be on main thread
        let recordingURL: URL?
        if session.enableAudioRecording {
            recordingURL = audioManager.stopRecording()
            if recordingURL == nil {
                print("⚠️ No audio recording available (screen recording may be interfering)")
            }
        } else {
            recordingURL = nil
        }
        
        // IMMEDIATE BACKGROUND PROCESSING: Submit for analysis right away
        // Processing happens in background while user continues to next question
        let pending = PendingAnswer(
            questionIndex: currentQuestionIndex,
            audioURL: recordingURL,
            eyeContactMetrics: eyeContactMetrics,
            timeSpent: timeSpent,
            questionText: question.text,
            questionId: question.id,
            experienceLevel: session.experienceLevel
        )
        pendingAnswers.append(pending)
        
        // Submit for immediate background processing (non-blocking)
        analysisManager.submitForBackgroundProcessing(pending)
        
        print("📥 Submitted answer \(currentQuestionIndex + 1) for background analysis (audio: \(recordingURL != nil ? "yes" : "no"))")
        
        // Mark question as answered (actual analysis happens after session ends)
        answeredQuestions.insert(currentQuestionIndex)
        
        // IMMEDIATELY move to next question - no async processing!
        if currentQuestionIndex < session.questions.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentQuestionIndex += 1
            }
            
            // Start recording and tracking for next question after brief animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                questionStartTime = Date()
                eyeContactAnalyzer.startTracking(with: cameraManager.captureSession)
                
                if session.enableAudioRecording, let nextQuestion = currentQuestion {
                    currentRecordingURL = audioManager.startRecording(for: nextQuestion.id)
                }
                isTransitioning = false
            }
        } else {
            // Last question answered, end session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTransitioning = false
                endSession()
            }
        }
    }
    
    private func skipQuestion() {
        guard !isTransitioning else { return }
        isTransitioning = true
        
        // Stop tracking
        _ = eyeContactAnalyzer.stopTracking()
        
        // Stop and discard current audio recording if enabled
        if session.enableAudioRecording {
            if let recordingURL = audioManager.stopRecording() {
                audioManager.deleteRecording(at: recordingURL)
            }
        }
        
        // Mark as skipped (both locally and in the analysis manager)
        skippedQuestions.insert(currentQuestionIndex)
        analysisManager.markAsSkipped(currentQuestionIndex)
        
        if currentQuestionIndex < session.questions.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentQuestionIndex += 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Restart tracking for next question
                questionStartTime = Date()
                eyeContactAnalyzer.startTracking(with: cameraManager.captureSession)
                
                // Start recording for next question
                if session.enableAudioRecording, let nextQuestion = currentQuestion {
                    currentRecordingURL = audioManager.startRecording(for: nextQuestion.id)
                }
                isTransitioning = false
            }
        } else {
            // Last question skipped, end session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTransitioning = false
                endSession()
            }
        }
    }
    
    private func nextQuestion() {
        guard !isTransitioning else { return }
        isTransitioning = true
        
        if currentQuestionIndex < session.questions.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentQuestionIndex += 1
                session.answeredCount = currentQuestionIndex
            }
            
            // Reset transition flag after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTransitioning = false
            }
        }
    }
    
    private func endSession() {
        // Use dedicated flag to prevent double-tapping end button
        // This allows ending the session even while a question is being processed
        guard !isEndingSession else { return }
        isEndingSession = true
        
        // Capture the current time to pause the timer display
        pausedTimeDisplay = timeElapsed()
        
        // Cancel any ongoing question processing
        isTransitioning = false
        isProcessingAnswer = false
        
        // Stop eye contact tracking
        _ = eyeContactAnalyzer.stopTracking()
        
        // Stop any active recording (discard if session ended mid-question)
        if audioManager.isRecording {
            if let recordingURL = audioManager.stopRecording() {
                audioManager.deleteRecording(at: recordingURL)
            }
        }
        
        sessionEndTime = Date()
        session.endTime = Date()
        
        // Update final counts
        session.answeredCount = answeredQuestions.count
        session.skippedCount = skippedQuestions.count
        
        // Any remaining questions are counted as skipped
        let remainingQuestions = Set(0..<session.questions.count)
            .subtracting(answeredQuestions)
            .subtracting(skippedQuestions)
        session.skippedCount += remainingQuestions.count
        
        // Mark remaining questions as skipped in the analysis manager
        for questionIndex in remainingQuestions {
            analysisManager.markAsSkipped(questionIndex)
        }
        
        print("📊 Session Stats: Answered: \(session.answeredCount), Skipped: \(session.skippedCount), Total: \(session.totalQuestions)")
        print("📥 Background analysis status: \(analysisManager.completedCount)/\(analysisManager.totalCount) complete")
        
        // Analysis is already happening in the background!
        // The summary view will show progress for any remaining items
        // Note: We save to Supabase AFTER analysis completes (in SessionSummaryView)
        isSavingSession = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showingSummary = true
            isEndingSession = false
        }
    }
    
    private func timeElapsed() -> String {
        guard let start = sessionStartTime else { return "00:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func navigateToTab(_ tab: Int) {
        // Signal that we're navigating from a session (for smooth transition)
        appState.isNavigatingFromSession = true
        
        // Pre-set the target tab with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            appState.selectedTab = tab
        }
        
        // Step 1: Dismiss the summary sheet with a slight delay for visual smoothness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.35)) {
                showingSummary = false
            }
        }
        
        // Step 2: Wait for sheet dismiss animation, then dismiss InterviewSessionView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            dismiss()
            
            // Step 3: Wait for fullScreenCover to dismiss, then trigger outer dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                appState.overlayDismissToken += 1
                
                // Reset navigation state after all transitions complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.isNavigatingFromSession = false
                }
            }
        }
    }
}

// MARK: - Camera Integration (Preview Only)

final class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var isAuthorized: Bool = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published var isConfigured: Bool = false
    @Published var isRecording: Bool = false
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isStarting = false
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentVideoURL: URL?
    
    override init() {
        super.init()
        // Set to high quality by default
        captureSession.sessionPreset = .high
        
        // Observe runtime errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
        
        // Observe interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
    }
    
    @objc private func handleSessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("❌ Camera session runtime error: \(error.localizedDescription)")
        print("📷 Error code: \(error.code.rawValue)")
        
        // Try to restart the session if it's a recoverable error
        if error.code == .deviceIsNotAvailableInBackground {
            print("📷 Camera not available in background")
        } else {
            print("📷 Attempting to recover from error...")
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                // Wait a moment before restarting
                Thread.sleep(forTimeInterval: 0.5)
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
            }
        }
    }
    
    @objc private func handleSessionWasInterrupted(notification: Notification) {
        print("⚠️ Camera session was interrupted")
        if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int {
            print("📷 Interruption reason: \(reason)")
        }
    }
    
    @objc private func handleSessionInterruptionEnded(notification: Notification) {
        print("✅ Camera session interruption ended")
    }

    func start() {
        // Prevent multiple simultaneous start calls
        guard !isStarting else {
            print("⚠️ Camera start already in progress, ignoring duplicate call")
            return
        }
        
        // If already running, don't start again
        if captureSession.isRunning {
            print("⚠️ Camera session already running, ignoring start call")
            return
        }
        
        isStarting = true
        print("📷 CameraManager: Requesting camera access...")
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("✅ Camera authorized, configuring...")
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            configureIfNeededAndStart()
        case .notDetermined:
            print("❓ Camera permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print(granted ? "✅ Camera access granted" : "❌ Camera access denied")
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if !granted {
                        self?.isStarting = false
                    }
                }
                if granted {
                    self?.configureIfNeededAndStart()
                }
            }
        case .denied:
            print("❌ Camera access denied")
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.isStarting = false
            }
        case .restricted:
            print("⚠️ Camera access restricted")
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.isStarting = false
            }
        @unknown default:
            print("❓ Unknown camera authorization status")
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.isStarting = false
            }
        }
    }

    func stop() {
        print("📷 Stopping camera session...")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            // Stop the session first
            if self.captureSession.isRunning {
                print("📷 Stopping running session...")
                self.captureSession.stopRunning()
                print("✅ Session stopped")
            }
            
            // Begin configuration to safely remove inputs/outputs
            self.captureSession.beginConfiguration()
            
            // Remove all inputs and outputs to release memory
            print("📷 Removing \(self.captureSession.inputs.count) inputs and \(self.captureSession.outputs.count) outputs")
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }
            
            self.captureSession.commitConfiguration()
            print("✅ Camera resources released")
            
            DispatchQueue.main.async {
                self.isConfigured = false
                self.isStarting = false
            }
        }
    }

    private func configureIfNeededAndStart() {
        print("📷 Configuring camera session...")
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    self?.isStarting = false
                }
                return
            }
            if !self.isConfigured {
                let success = self.configureSession()
                if !success {
                    print("❌ Camera configuration failed")
                    DispatchQueue.main.async {
                        self.isStarting = false
                    }
                    return
                }
                // Wait for configuration to fully commit
                Thread.sleep(forTimeInterval: 0.2)
            }
            print("✅ Camera configured, starting session...")
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                // Verify it actually started
                Thread.sleep(forTimeInterval: 0.1)
                if self.captureSession.isRunning {
                    print("✅ Camera session started successfully")
                } else {
                    print("❌ Camera session failed to start (check runtime error notifications)")
                }
            } else {
                print("⚠️ Camera session already running")
            }
            DispatchQueue.main.async {
                self.isStarting = false
            }
        }
    }

    private func configureSession() -> Bool {
        print("📷 Beginning camera configuration...")
        print("📷 Current session preset: \(captureSession.sessionPreset.rawValue)")
        print("📷 Session is running: \(captureSession.isRunning)")
        print("📷 Existing inputs: \(captureSession.inputs.count)")
        print("📷 Existing outputs: \(captureSession.outputs.count)")
        
        captureSession.beginConfiguration()
        
        // CRITICAL: Don't let AVCaptureSession configure audio - we use separate AVAudioRecorder
        // This prevents conflicts where the camera claims exclusive audio access
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        
        captureSession.sessionPreset = .high  // Use high quality for iPhone 15 Pro
        print("📷 Session preset set to: \(captureSession.sessionPreset.rawValue)")
        print("📷 Auto-configure audio session: \(captureSession.automaticallyConfiguresApplicationAudioSession)")

        // Prefer front camera for interview practice
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        print("📷 Available front cameras: \(discoverySession.devices.count)")
        for device in discoverySession.devices {
            print("📷   - Device: \(device.localizedName), position: \(device.position.rawValue)")
        }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Failed to get front camera device")
            captureSession.commitConfiguration()
            return false
        }
        
        print("✅ Front camera device found: \(device.localizedName)")
        print("📷 Device is connected: \(device.isConnected)")
        print("📷 Device formats available: \(device.formats.count)")
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            print("✅ Camera input created successfully")
            
            guard captureSession.canAddInput(input) else {
                print("❌ Cannot add camera input to session")
                print("📷 Session is interrupted: \(captureSession.isInterrupted)")
                if let error = captureSession.inputs.first {
                    print("📷 Existing input: \(error)")
                }
                captureSession.commitConfiguration()
                return false
            }
            
            captureSession.addInput(input)
            print("✅ Camera input added to session")
            print("📷 Total inputs now: \(captureSession.inputs.count)")
            
        } catch {
            print("❌ Failed to create camera input: \(error.localizedDescription)")
            print("📷 Error details: \(error)")
            captureSession.commitConfiguration()
            return false
        }
        
        // Add movie output for video recording
        let movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            self.movieOutput = movieOutput
            print("✅ Movie output added to session")
        } else {
            print("⚠️ Cannot add movie output to session")
        }

        captureSession.commitConfiguration()
        print("📷 Session configuration committed")
        
        // Set isConfigured on main thread to avoid publishing warning
        DispatchQueue.main.async {
            self.isConfigured = true
            print("✅ Camera configuration complete")
        }
        
        return true
    }
    
    func startVideoRecording(for questionId: UUID) -> URL? {
        guard let movieOutput = movieOutput, !movieOutput.isRecording else {
            print("⚠️ Movie output not available or already recording")
            return nil
        }
        
        // Create video URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoFilename = documentsPath.appendingPathComponent("video_\(questionId.uuidString).mov")
        currentVideoURL = videoFilename
        
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: videoFilename)
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            movieOutput.startRecording(to: videoFilename, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
            }
            print("✅ Started video recording to: \(videoFilename.lastPathComponent)")
        }
        
        return videoFilename
    }
    
    func stopVideoRecording() -> URL? {
        guard let movieOutput = movieOutput, movieOutput.isRecording else {
            print("⚠️ No video recording in progress")
            return nil
        }
        
        sessionQueue.async { [weak self] in
            movieOutput.stopRecording()
            DispatchQueue.main.async {
                self?.isRecording = false
            }
            print("✅ Stopped video recording")
        }
        
        return currentVideoURL
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("❌ Video recording error: \(error.localizedDescription)")
        } else {
            print("✅ Video recording finished successfully: \(outputFileURL.lastPathComponent)")
        }
    }
    
    deinit {
        print("📷 CameraManager deinit - cleaning up")
        // Remove observers
        NotificationCenter.default.removeObserver(self)
        
        // Ensure session is stopped and cleaned up on dealloc
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        // Remove all inputs and outputs
        captureSession.beginConfiguration()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        captureSession.commitConfiguration()
        print("✅ CameraManager cleaned up")
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        if let connection = view.videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
    
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        // Release the session reference when view is torn down
        uiView.videoPreviewLayer.session = nil
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

#Preview {
    InterviewSessionView(session: InterviewSession(
        role: "Software Engineer",
        difficulty: .medium,
        categories: [.behavioral, .technical],
        duration: 15,
        questions: InterviewQuestionBank.shared.getQuestions(
            categories: [.behavioral],
            difficulty: .medium,
            count: 5
        )
    ))
}
