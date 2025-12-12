import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// Utility class for processing images (validation, sizing info)
/// Uses native image_picker which handles compression and encoding
class ImageProcessor {
  /// Maximum file size for avatars (2MB)
  static const int maxFileSizeBytes = 2 * 1024 * 1024;
  
  /// Target dimension for avatar images (square)
  static const int targetDimension = 512;

  /// Validates if image file size is within acceptable limits
  static bool validateFileSize(File imageFile) {
    final bytes = imageFile.lengthSync();
    return bytes <= maxFileSizeBytes;
  }

  /// Validates if image file size (in bytes) is within acceptable limits
  static bool validateFileSizeBytes(int sizeInBytes) {
    return sizeInBytes <= maxFileSizeBytes;
  }

  /// Gets file size in MB as string for display
  static String getFileSizeInMB(File imageFile) {
    final sizeInBytes = imageFile.lengthSync();
    final sizeInMB = sizeInBytes / (1024 * 1024);
    return '${sizeInMB.toStringAsFixed(2)} MB';
  }

  /// Gets file size in MB as string from bytes
  static String getFileSizeInMBFromBytes(int sizeInBytes) {
    final sizeInMB = sizeInBytes / (1024 * 1024);
    return '${sizeInMB.toStringAsFixed(2)} MB';
  }

  /// Converts File to Uint8List
  static Future<Uint8List> fileToBytes(File file) async {
    try {
      return await file.readAsBytes();
    } catch (e) {
      print('Error reading file: $e');
      rethrow;
    }
  }

  /// Checks if file is a valid image
  static bool isValidImageFormat(File file) {
    final path = file.path.toLowerCase();
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp');
  }

  /// Gets image dimensions from file
  static Future<({int width, int height})?> getImageDimensions(
    File imageFile,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      return (width: image.width, height: image.height);
    } catch (e) {
      print('Error getting image dimensions: $e');
      return null;
    }
  }

  /// Checks if image is approximately square (aspect ratio between 0.8 and 1.2)
  static Future<bool> isApproximatelySquare(File imageFile) async {
    final dims = await getImageDimensions(imageFile);
    if (dims == null) return false;
    
    final aspectRatio = dims.width / dims.height;
    return aspectRatio >= 0.8 && aspectRatio <= 1.2;
  }
}
