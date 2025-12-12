import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/interview_models.dart';

/// Eye contact analyzer using ML Kit face detection
/// Matching iOS EyeContactAnalyzer.swift
class EyeContactAnalyzer {
  static EyeContactAnalyzer? _instance;
  static EyeContactAnalyzer get instance => _instance ??= EyeContactAnalyzer._();

  EyeContactAnalyzer._();

  late final FaceDetector _faceDetector;
  bool _isInitialized = false;
  bool _isAnalyzing = false;
  
  // Tracking metrics
  DateTime? _sessionStartTime;
  int _totalFrames = 0;
  int _lookingAtCameraFrames = 0;
  final List<EyeContactTimestamp> _timestamps = [];
  
  // Thresholds for eye contact detection
  static const double _headRotationThreshold = 15.0; // degrees
  static const double _eyeOpenThreshold = 0.3;

  // Stream for real-time updates
  final _eyeContactController = StreamController<EyeContactUpdate>.broadcast();
  Stream<EyeContactUpdate> get eyeContactStream => _eyeContactController.stream;

  bool get isAnalyzing => _isAnalyzing;

  /// Initialize the face detector
  Future<void> initialize() async {
    if (_isInitialized) return;

    final options = FaceDetectorOptions(
      enableClassification: true, // For eye openness
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    );

    _faceDetector = FaceDetector(options: options);
    _isInitialized = true;
    debugPrint('Eye contact analyzer initialized');
  }

  /// Start eye contact analysis session
  void startSession() {
    _sessionStartTime = DateTime.now();
    _totalFrames = 0;
    _lookingAtCameraFrames = 0;
    _timestamps.clear();
    _isAnalyzing = true;
    debugPrint('Eye contact session started');
  }

  /// Process a camera frame for eye contact
  Future<void> processFrame(CameraImage image, CameraDescription camera) async {
    if (!_isInitialized || !_isAnalyzing) return;

    try {
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      _totalFrames++;

      final elapsedTime = _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inMilliseconds / 1000.0
          : 0.0;

      if (faces.isNotEmpty) {
        final face = faces.first;
        final isLookingAtCamera = _isLookingAtCamera(face);

        if (isLookingAtCamera) {
          _lookingAtCameraFrames++;
        }

        _timestamps.add(EyeContactTimestamp(
          time: elapsedTime,
          isLookingAtCamera: isLookingAtCamera,
        ));

        // Emit update
        final percentage = _totalFrames > 0
            ? (_lookingAtCameraFrames / _totalFrames) * 100
            : 0.0;

        _eyeContactController.add(EyeContactUpdate(
          isLookingAtCamera: isLookingAtCamera,
          currentPercentage: percentage,
          headRotationX: face.headEulerAngleX ?? 0,
          headRotationY: face.headEulerAngleY ?? 0,
          headRotationZ: face.headEulerAngleZ ?? 0,
        ));
      } else {
        // No face detected - not looking at camera
        _timestamps.add(EyeContactTimestamp(
          time: elapsedTime,
          isLookingAtCamera: false,
        ));
      }
    } catch (e) {
      debugPrint('Error processing frame for eye contact: $e');
    }
  }

  /// Check if the face is looking at the camera
  bool _isLookingAtCamera(Face face) {
    // Check head rotation (should be roughly facing camera)
    final rotationY = face.headEulerAngleY?.abs() ?? 0;
    final rotationX = face.headEulerAngleX?.abs() ?? 0;
    
    if (rotationY > _headRotationThreshold || rotationX > _headRotationThreshold) {
      return false; // Head turned too far
    }

    // Check if eyes are open (if classification is available)
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    
    if (leftEyeOpen < _eyeOpenThreshold && rightEyeOpen < _eyeOpenThreshold) {
      return false; // Eyes appear closed
    }

    return true;
  }

  /// Stop analysis and return metrics
  EyeContactMetrics stopSession() {
    _isAnalyzing = false;
    
    final totalDuration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds.toDouble()
        : 0.0;

    final percentage = _totalFrames > 0
        ? (_lookingAtCameraFrames / _totalFrames) * 100
        : 0.0;

    final lookingDuration = totalDuration * (percentage / 100);

    final metrics = EyeContactMetrics(
      percentage: percentage,
      totalDuration: totalDuration,
      lookingAtCameraDuration: lookingDuration,
      timestamps: List.from(_timestamps),
    );

    debugPrint('Eye contact session ended: ${percentage.toStringAsFixed(1)}% eye contact');
    return metrics;
  }

  /// Convert CameraImage to InputImage for ML Kit
  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final size = ui.Size(image.width.toDouble(), image.height.toDouble());

      final rotation = _getInputImageRotation(camera);
      if (rotation == null) return null;

      final inputImageData = InputImageMetadata(
        size: size,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: inputImageData,
      );
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }

  InputImageRotation? _getInputImageRotation(CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return null;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _isAnalyzing = false;
    await _faceDetector.close();
    await _eyeContactController.close();
    _isInitialized = false;
  }
}

/// Eye contact update for real-time feedback
class EyeContactUpdate {
  final bool isLookingAtCamera;
  final double currentPercentage;
  final double headRotationX;
  final double headRotationY;
  final double headRotationZ;

  EyeContactUpdate({
    required this.isLookingAtCamera,
    required this.currentPercentage,
    required this.headRotationX,
    required this.headRotationY,
    required this.headRotationZ,
  });
}
