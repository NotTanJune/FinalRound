import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../config/theme.dart';
import '../../models/interview_models.dart';
import '../../services/audio_recording_manager.dart';
import '../../services/camera_manager.dart';
import '../../services/eye_contact_analyzer.dart';
import '../../services/groq_service.dart';
import 'summary_screen.dart';

/// Live interview session screen matching iOS InterviewSessionView.swift
/// Camera preview fills screen, question overlaid, voice-only answers
class SessionScreen extends StatefulWidget {
  final InterviewSession session;

  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with TickerProviderStateMixin {
  late InterviewSession _session;
  int _currentQuestionIndex = 0;
  bool _isSessionStarted = false;
  bool _isRecordingAudio = false;
  DateTime? _questionStartTime;
  
  // Timer
  late Stopwatch _sessionStopwatch;
  Timer? _timerRefresh;
  
  // Recording services
  final _audioManager = AudioRecordingManager.instance;
  final _cameraManager = CameraManager.instance;
  final _eyeContactAnalyzer = EyeContactAnalyzer.instance;
  
  String? _currentAudioPath;
  StreamSubscription? _eyeContactSubscription;
  double _currentEyeContactPercentage = 0;
  bool _isLookingAtCamera = false;
  
  // Animation controller for recording indicator
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _sessionStopwatch = Stopwatch();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameraInitialized = await _cameraManager.initialize(useFrontCamera: true);
    if (cameraInitialized && mounted) {
      setState(() {});
      
      // Initialize eye contact tracking
      await _eyeContactAnalyzer.initialize();
      
      // Listen for eye contact updates
      _eyeContactSubscription = _eyeContactAnalyzer.eyeContactStream.listen((update) {
        if (mounted) {
          setState(() {
            _currentEyeContactPercentage = update.currentPercentage;
            _isLookingAtCamera = update.isLookingAtCamera;
          });
        }
      });

      // Start processing frames
      _startEyeContactProcessing();
    }

    // Initialize audio
    await _audioManager.initialize();
  }

  void _startEyeContactProcessing() {
    final controller = _cameraManager.controller;
    if (controller == null) return;

    controller.startImageStream((image) {
      _eyeContactAnalyzer.processFrame(
        image,
        controller.description,
      );
    });
  }

  void _startSession() {
    setState(() {
      _isSessionStarted = true;
      _session.startTime = DateTime.now();
      _questionStartTime = DateTime.now();
    });
    
    // Start timer
    _sessionStopwatch.start();
    _timerRefresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    
    // Start eye contact session and audio recording for first question
    _eyeContactAnalyzer.startSession();
    _startRecordingForCurrentQuestion();
  }

  Future<void> _startRecordingForCurrentQuestion() async {
    final path = await _audioManager.startRecording(
      customFileName: 'q${_currentQuestionIndex + 1}_${DateTime.now().millisecondsSinceEpoch}.aac',
    );
    if (mounted) {
      setState(() {
        _isRecordingAudio = path != null;
        _currentAudioPath = path;
      });
    }
  }

  Future<void> _stopRecordingForCurrentQuestion() async {
    if (_isRecordingAudio) {
      await _audioManager.stopRecording();
      setState(() => _isRecordingAudio = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timerRefresh?.cancel();
    _eyeContactSubscription?.cancel();
    _stopRecordingAndCleanup();
    super.dispose();
  }

  Future<void> _stopRecordingAndCleanup() async {
    if (_isRecordingAudio) {
      await _audioManager.stopRecording();
    }
    _cameraManager.controller?.stopImageStream();
    await _cameraManager.dispose();
  }

  InterviewQuestion get _currentQuestion => 
      _session.questions[_currentQuestionIndex];

  bool get _isLastQuestion => 
      _currentQuestionIndex >= _session.questions.length - 1;

  String get _formattedTime {
    final elapsed = _sessionStopwatch.elapsed;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _submitAnswer() async {
    // Stop recording and get transcription
    await _stopRecordingForCurrentQuestion();
    
    final timeSpent = _questionStartTime != null
        ? DateTime.now().difference(_questionStartTime!).inSeconds.toDouble()
        : null;

    // Get eye contact metrics
    final eyeMetrics = _eyeContactAnalyzer.stopSession();
    
    // Transcribe the audio
    String transcription = '';
    if (_currentAudioPath != null) {
      try {
        transcription = await GroqService.instance.transcribeAudio(_currentAudioPath!);
      } catch (e) {
        debugPrint('Transcription error: $e');
        transcription = '[Transcription failed]';
      }
    }
    
    _session.questions[_currentQuestionIndex].answer = QuestionAnswer(
      transcription: transcription,
      audioUrl: _currentAudioPath,
      eyeContactMetrics: eyeMetrics,
      confidenceScore: eyeMetrics.percentage,
      timeSpent: timeSpent,
    );
    
    _session.answeredCount++;
    _nextQuestion();
  }

  void _skipQuestion() {
    // Stop recording without saving
    _stopRecordingForCurrentQuestion();
    
    // Stop eye contact session for this question
    _eyeContactAnalyzer.stopSession();
    _session.skippedCount++;
    _nextQuestion();
  }

  void _nextQuestion() {
    if (_isLastQuestion) {
      _finishSession();
    } else {
      setState(() {
        _currentQuestionIndex++;
        _questionStartTime = DateTime.now();
        _currentAudioPath = null;
        _currentEyeContactPercentage = 0;
      });
      
      // Start new eye contact session and recording for next question
      _eyeContactAnalyzer.startSession();
      _startRecordingForCurrentQuestion();
    }
  }

  void _finishSession() {
    _sessionStopwatch.stop();
    _session.endTime = DateTime.now();
    _session.duration = _sessionStopwatch.elapsed.inSeconds;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryScreen(session: _session),
      ),
    );
  }

  void _endSession() async {
    final shouldEnd = await _showExitDialog();
    if (shouldEnd == true && mounted) {
      // Stop any active recording
      await _stopRecordingForCurrentQuestion();
      
      // Stop eye contact tracking
      _eyeContactAnalyzer.stopSession();
      _sessionStopwatch.stop();
      
      // Mark remaining questions as skipped (iOS behavior)
      // Current question (if not answered) and all after are skipped
      final remainingCount = _session.questions.length - _currentQuestionIndex;
      
      // Only add to skipped if we're still on an unanswered question
      if (_session.questions[_currentQuestionIndex].answer == null) {
        _session.skippedCount += remainingCount;
      } else {
        // Current question was answered, only add remaining after current
        final afterCurrentCount = _session.questions.length - _currentQuestionIndex - 1;
        if (afterCurrentCount > 0) {
          _session.skippedCount += afterCurrentCount;
        }
      }
      
      // Set end time and duration
      _session.endTime = DateTime.now();
      _session.duration = _sessionStopwatch.elapsed.inSeconds;
      
      debugPrint('📊 Session ended early: Answered=${_session.answeredCount}, Skipped=${_session.skippedCount}, Total=${_session.questions.length}');
      
      // Navigate to summary screen (which will save to Supabase)
      await _stopRecordingAndCleanup();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SummaryScreen(session: _session),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _endSession();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Full screen camera preview
            _buildCameraPreview(),
            
            // Overlay content
            SafeArea(
              child: Column(
                children: [
                  // Header with timer
                  _buildHeader(),
                  
                  // Progress bar
                  if (_isSessionStarted) _buildProgressBar(),
                  
                  const Spacer(),
                  
                  // Question overlay at bottom
                  if (_isSessionStarted) _buildQuestionOverlay(),
                  
                  // Control buttons
                  if (_isSessionStarted) _buildControlButtons(),
                  
                  // Start button overlay
                  if (!_isSessionStarted) _buildStartOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showExitDialog() {
    final remaining = _session.questions.length - _currentQuestionIndex;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Interview?'),
        content: Text(
          remaining > 0
              ? 'You have $remaining question${remaining > 1 ? 's' : ''} remaining. They will be marked as skipped.'
              : 'Are you sure you want to end this interview?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Close button
          _buildCircleButton(
            icon: Icons.close,
            onTap: _endSession,
          ),
          
          const Spacer(),
          
          // Question counter (only when session started)
          if (_isSessionStarted)
            Text(
              'Q${_currentQuestionIndex + 1}/${_session.questions.length}',
              style: AppTheme.font(
                size: 16,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          
          const Spacer(),
          
          // Timer
          if (_isSessionStarted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    _formattedTime,
                    style: AppTheme.font(
                      size: 14,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(width: 40), // Placeholder for alignment
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = (_currentQuestionIndex + 1) / _session.questions.length;
    
    return Container(
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraManager.controller;
    
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildQuestionOverlay() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primary.withAlpha(100),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category and recording indicator row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _currentQuestion.category.value,
                  style: AppTheme.font(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              // Recording indicator
              if (_isRecordingAudio)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withAlpha(
                          (150 + _pulseController.value * 105).toInt(),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Recording',
                            style: AppTheme.font(
                              size: 12,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Question text
          Text(
            _currentQuestion.text,
            style: AppTheme.font(
              size: 18,
              weight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Eye contact indicator
          Row(
            children: [
              Icon(
                _isLookingAtCamera ? Icons.visibility : Icons.visibility_off,
                size: 16,
                color: _isLookingAtCamera ? AppTheme.success : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                'Eye Contact: ${_currentEyeContactPercentage.toStringAsFixed(0)}%',
                style: AppTheme.font(
                  size: 13,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Skip and Next buttons
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  label: 'Skip',
                  icon: Icons.skip_next,
                  onTap: _skipQuestion,
                  isPrimary: false,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _buildActionButton(
                  label: _isLastQuestion ? 'Finish' : 'Next',
                  icon: _isLastQuestion ? Icons.check : Icons.arrow_forward,
                  onTap: _submitAnswer,
                  isPrimary: true,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // End call button
          GestureDetector(
            onTap: _endSession,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.error.withAlpha(100),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.call_end,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primary : Colors.white.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: Colors.white30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isPrimary) Icon(icon, color: Colors.white, size: 20),
            if (!isPrimary) const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.font(
                size: 16,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (isPrimary) const SizedBox(width: 8),
            if (isPrimary) Icon(icon, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Role badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _session.role,
                style: AppTheme.font(
                  size: 18,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Text(
              '${_session.questions.length} Questions',
              style: AppTheme.font(
                size: 16,
                color: Colors.white70,
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Start button
            GestureDetector(
              onTap: _startSession,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withAlpha(200),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withAlpha(100),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 56,
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            Text(
              'Tap to Start',
              style: AppTheme.font(
                size: 16,
                weight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
