import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera manager for video recording during interviews
/// Matching iOS camera implementation
class CameraManager {
  static CameraManager? _instance;
  static CameraManager get instance => _instance ??= CameraManager._();

  CameraManager._();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  String? _currentVideoPath;
  DateTime? _recordingStartTime;

  // Stream for camera state
  final _cameraStateController = StreamController<CameraState>.broadcast();
  Stream<CameraState> get cameraStateStream => _cameraStateController.stream;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  String? get currentVideoPath => _currentVideoPath;

  Duration get recordingDuration {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Initialize the camera
  Future<bool> initialize({bool useFrontCamera = true}) async {
    try {
      // Request camera permission
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        debugPrint('Camera permission denied');
        return false;
      }

      // Request microphone permission for video recording
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint('Microphone permission denied');
        return false;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('No cameras available');
        return false;
      }

      // Select front or back camera
      CameraDescription selectedCamera;
      if (useFrontCamera) {
        selectedCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      } else {
        selectedCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );
      }

      // Create controller
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      _cameraStateController.add(CameraState.ready);

      debugPrint('Camera initialized: ${selectedCamera.name}');
      return true;
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      _cameraStateController.add(CameraState.error);
      return false;
    }
  }

  /// Start video recording
  Future<String?> startVideoRecording({String? customFileName}) async {
    if (!_isInitialized || _controller == null) {
      debugPrint('Camera not initialized');
      return null;
    }

    if (_isRecording) {
      debugPrint('Already recording video');
      return null;
    }

    try {
      await _controller!.prepareForVideoRecording();
      await _controller!.startVideoRecording();

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _cameraStateController.add(CameraState.recording);

      debugPrint('Started video recording');
      return 'recording_started';
    } catch (e) {
      debugPrint('Error starting video recording: $e');
      return null;
    }
  }

  /// Stop video recording and return the file path
  Future<String?> stopVideoRecording() async {
    if (!_isRecording || _controller == null) {
      debugPrint('Not currently recording video');
      return _currentVideoPath;
    }

    try {
      final XFile videoFile = await _controller!.stopVideoRecording();
      _isRecording = false;
      _cameraStateController.add(CameraState.ready);

      // Move to documents directory with proper name
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'interview_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final newPath = '${directory.path}/$fileName';
      
      final file = File(videoFile.path);
      await file.copy(newPath);
      await file.delete();
      
      _currentVideoPath = newPath;
      debugPrint('Stopped video recording: $_currentVideoPath');
      return _currentVideoPath;
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
      _isRecording = false;
      _cameraStateController.add(CameraState.ready);
      return null;
    }
  }

  /// Take a photo
  Future<String?> takePhoto() async {
    if (!_isInitialized || _controller == null) {
      debugPrint('Camera not initialized');
      return null;
    }

    try {
      final XFile photo = await _controller!.takePicture();
      
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = '${directory.path}/$fileName';
      
      final file = File(photo.path);
      await file.copy(newPath);
      await file.delete();
      
      debugPrint('Photo taken: $newPath');
      return newPath;
    } catch (e) {
      debugPrint('Error taking photo: $e');
      return null;
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (_cameras.length < 2) {
      debugPrint('Cannot switch camera - only one camera available');
      return;
    }

    final currentDirection = _controller?.description.lensDirection;
    final newDirection = currentDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final newCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == newDirection,
      orElse: () => _cameras.first,
    );

    await _controller?.dispose();
    _controller = CameraController(
      newCamera,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    await _controller!.initialize();
    _cameraStateController.add(CameraState.ready);
  }

  /// Get camera preview widget
  Widget? getCameraPreview() {
    if (!_isInitialized || _controller == null) return null;
    return CameraPreview(_controller!);
  }

  /// Delete a video file
  Future<bool> deleteVideo(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting video: $e');
      return false;
    }
  }

  /// Dispose camera resources
  Future<void> dispose() async {
    try {
      if (_isRecording) {
        await stopVideoRecording();
      }
      await _controller?.dispose();
      await _cameraStateController.close();
      _controller = null;
      _isInitialized = false;
    } catch (e) {
      debugPrint('Error disposing camera: $e');
    }
  }
}

/// Camera state enum
enum CameraState {
  uninitialized,
  ready,
  recording,
  error,
}
