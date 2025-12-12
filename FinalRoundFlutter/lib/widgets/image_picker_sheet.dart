import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';

/// Modal bottom sheet for selecting images from camera or photo library
/// Returns the selected File on completion
class ImagePickerSheet extends StatefulWidget {
  final Function(File) onImageSelected;
  final VoidCallback? onCancel;
  
  const ImagePickerSheet({
    super.key,
    required this.onImageSelected,
    this.onCancel,
  });

  @override
  State<ImagePickerSheet> createState() => _ImagePickerSheetState();
}

class _ImagePickerSheetState extends State<ImagePickerSheet> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickFromCamera() async {
    setState(() => _isLoading = true);
    
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );
      
      if (image != null && mounted) {
        widget.onImageSelected(File(image.path));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error picking from camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open camera: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() => _isLoading = true);
    
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      
      if (image != null && mounted) {
        widget.onImageSelected(File(image.path));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error picking from gallery: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open gallery: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary(context).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                'Add Photo',
                style: AppTheme.title2(context),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Take Photo Button
                  _buildPickerButton(
                    context,
                    icon: Icons.camera_alt,
                    label: 'Take Photo',
                    onPressed: _isLoading ? null : _pickFromCamera,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Choose from Gallery Button
                  _buildPickerButton(
                    context,
                    icon: Icons.photo_library,
                    label: 'Choose from Library',
                    onPressed: _isLoading ? null : _pickFromGallery,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Cancel Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          widget.onCancel?.call();
                          Navigator.of(context).pop();
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary(context),
                    side: BorderSide(
                      color: AppTheme.border(context),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTheme.headline(context),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTheme.headline(context),
              ),
            ),
            if (_isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                color: AppTheme.textSecondary(context),
              ),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.lightGreen.withOpacity(0.15),
          foregroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: AppTheme.primary.withOpacity(0.3),
            ),
          ),
          elevation: 0,
          disabledBackgroundColor:
              AppTheme.lightGreen.withOpacity(0.1),
        ),
      ),
    );
  }
}
