import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Audio recording manager matching iOS AudioRecordingManager.swift
class AudioRecordingManager {
  static AudioRecordingManager? _instance;
  static AudioRecordingManager get instance => _instance ??= AudioRecordingManager._();

  AudioRecordingManager._();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  
  // Stream for recording state changes
  final _recordingStateController = StreamController<bool>.broadcast();
  Stream<bool> get recordingStateStream => _recordingStateController.stream;
  
  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  
  Duration get recordingDuration {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Initialize the recorder
  Future<bool> initialize() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('Microphone permission denied');
        return false;
      }

      // Open recorder
      await _recorder.openRecorder();
      _isRecorderInitialized = true;

      // Open player
      await _player.openPlayer();
      _isPlayerInitialized = true;

      return true;
    } catch (e) {
      debugPrint('Error initializing audio recorder: $e');
      return false;
    }
  }

  /// Start recording audio
  Future<String?> startRecording({String? customFileName}) async {
    if (!_isRecorderInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    if (_isRecording) {
      debugPrint('Already recording');
      return null;
    }

    try {
      // Generate file path
      final directory = await getApplicationDocumentsDirectory();
      final fileName = customFileName ?? 
          'recording_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordingPath = '${directory.path}/$fileName';

      // Start recording
      await _recorder.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingStateController.add(true);

      debugPrint('Started recording to: $_currentRecordingPath');
      return _currentRecordingPath;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return null;
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      debugPrint('Not currently recording');
      return _currentRecordingPath;
    }

    try {
      await _recorder.stopRecorder();
      _isRecording = false;
      _recordingStateController.add(false);
      
      final path = _currentRecordingPath;
      debugPrint('Stopped recording: $path');
      return path;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      _recordingStateController.add(false);
      return null;
    }
  }

  /// Play a recorded audio file
  Future<void> playRecording(String path) async {
    if (!_isPlayerInitialized) {
      await _player.openPlayer();
      _isPlayerInitialized = true;
    }

    try {
      await _player.startPlayer(
        fromURI: path,
        codec: Codec.aacADTS,
      );
    } catch (e) {
      debugPrint('Error playing recording: $e');
    }
  }

  /// Stop playback
  Future<void> stopPlayback() async {
    try {
      await _player.stopPlayer();
    } catch (e) {
      debugPrint('Error stopping playback: $e');
    }
  }

  /// Delete a recording file
  Future<bool> deleteRecording(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting recording: $e');
      return false;
    }
  }

  /// Get the duration of a recorded file
  Future<Duration?> getRecordingDuration(String path) async {
    // Note: flutter_sound doesn't have a direct way to get duration
    // You would need to decode the file or use another package
    return null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      if (_isRecording) {
        await stopRecording();
      }
      await _recorder.closeRecorder();
      await _player.closePlayer();
      await _recordingStateController.close();
      _isRecorderInitialized = false;
      _isPlayerInitialized = false;
    } catch (e) {
      debugPrint('Error disposing audio recorder: $e');
    }
  }
}
