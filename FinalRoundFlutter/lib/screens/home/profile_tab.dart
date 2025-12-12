import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/image_processor.dart';
import '../profile/profile_edit_screen.dart';
import '../../widgets/image_picker_sheet.dart';

/// Profile tab matching iOS ProfileView
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _isDarkMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            final profile = auth.userProfile;
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // Profile header
                  _buildProfileHeader(context, auth),
                  
                  const SizedBox(height: 24),
                  
                  // Edit Profile button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showEditProfileDialog(context, auth),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit Profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Profile info cards
                  _buildInfoCard(
                    context,
                    icon: Icons.work_outline,
                    title: 'Target Role',
                    value: profile?.targetRole ?? 'Not set',
                    onTap: () => _showEditProfileDialog(context, auth),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  _buildInfoCard(
                    context,
                    icon: Icons.trending_up,
                    title: 'Experience Level',
                    value: profile?.yearsOfExperience ?? 'Not set',
                    onTap: () => _showEditProfileDialog(context, auth),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  _buildInfoCard(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Location',
                    value: profile?.location ?? 'Not set',
                    onTap: () => _showEditProfileDialog(context, auth),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Skills
                  _buildSkillsCard(context, profile?.skills ?? []),
                  
                  const SizedBox(height: 32),
                  
                  // Appearance Settings
                  _buildAppearanceSection(context),
                  
                  const SizedBox(height: 24),
                  
                  // Account Settings section
                  _buildAccountSection(context, auth),
                  
                  const SizedBox(height: 100),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, AuthProvider auth) {
    final profile = auth.userProfile;
    
    return Column(
      children: [
        // Avatar with edit button
        GestureDetector(
          onTap: () => _changeProfilePhoto(context, auth),
          child: Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: AppTheme.lightGreen,
                backgroundImage: profile?.avatarUrl != null
                    ? NetworkImage(profile!.avatarUrl!)
                    : null,
                child: profile?.avatarUrl == null
                    ? Text(
                        profile?.initials ?? '?',
                        style: AppTheme.font(
                          size: 32,
                          weight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.cardBackground(context),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          profile?.displayName ?? 'User',
          style: AppTheme.title2(context),
        ),
        
        const SizedBox(height: 4),
        
        Text(
          profile?.targetRole ?? 'Set your target role',
          style: AppTheme.subheadline(context),
        ),
      ],
    );
  }

  void _changeProfilePhoto(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ImagePickerSheet(
        onImageSelected: (imageFile) async {
          await _handleImageSelection(context, auth, imageFile);
        },
        onCancel: () {
          debugPrint('Image picker cancelled');
        },
      ),
    );
  }

  Future<void> _handleImageSelection(
    BuildContext context,
    AuthProvider auth,
    File imageFile,
  ) async {
    try {
      // Validate file
      if (!ImageProcessor.isValidImageFormat(imageFile)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid image format. Please choose JPG, PNG, GIF, or WebP.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Validate file size
      if (!ImageProcessor.validateFileSize(imageFile)) {
        if (mounted) {
          final fileSize = ImageProcessor.getFileSizeInMB(imageFile);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Image too large ($fileSize). Maximum size is 2 MB.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();

      if (!mounted) return;

      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploading photo...'),
          duration: Duration(seconds: 30),
        ),
      );

      // Upload photo
      final success = await auth.uploadProfilePhoto(imageBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo updated successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Refresh profile to get the updated avatar URL
          await auth.refreshProfile();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(auth.errorMessage ?? 'Failed to upload photo'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error handling image selection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditProfileDialog(BuildContext context, AuthProvider auth) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileEditScreen(),
      ),
    );
    
    // If profile was saved and jobs need refresh, trigger it
    if (result != null && result['needsJobRefresh'] == true) {
      debugPrint('🔄 Profile saved with job-relevant changes, triggering job refresh');
      auth.triggerJobRefresh();
    }
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.shadowColor(context),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.caption(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppTheme.body(context),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsCard(BuildContext context, List<String> skills) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.shadowColor(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.star_outline, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                'Skills',
                style: AppTheme.headline(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (skills.isEmpty)
            Text(
              'No skills added yet',
              style: AppTheme.subheadline(context),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: skills.map((skill) => _buildSkillChip(context, skill)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSkillChip(BuildContext context, String skill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lightGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        skill,
        style: AppTheme.font(
          size: 13,
          weight: FontWeight.w500,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appearance',
          style: AppTheme.headline(context),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                Icons.dark_mode_outlined,
                color: AppTheme.textSecondary(context),
                size: 22,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Dark Mode',
                  style: AppTheme.body(context),
                ),
              ),
              Switch(
                value: _isDarkMode,
                onChanged: (value) {
                  setState(() => _isDarkMode = value);
                  // TODO: Implement theme switching
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Theme switching coming soon!')),
                  );
                },
                activeColor: AppTheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(BuildContext context, AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account',
          style: AppTheme.headline(context),
        ),
        const SizedBox(height: 12),
        
        _buildSettingItem(
          context,
          icon: Icons.lock_outline,
          title: 'Change Password',
          onTap: () => _changePassword(context),
        ),
        
        _buildSettingItem(
          context,
          icon: Icons.logout,
          title: 'Sign Out',
          onTap: () => _confirmSignOut(context, auth),
        ),
        
        _buildSettingItem(
          context,
          icon: Icons.delete_outline,
          title: 'Delete Account',
          isDestructive: true,
          onTap: () => _confirmDeleteAccount(context, auth),
        ),
      ],
    );
  }

  void _changePassword(BuildContext context) async {
    final email = SupabaseService.instance.currentUserEmail;
    if (email != null) {
      try {
        await SupabaseService.instance.resetPassword(email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset email sent!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  void _confirmSignOut(BuildContext context, AuthProvider auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await auth.signOut();
      // AuthWrapper will automatically navigate to LoginScreen with sign in mode
      if (mounted && !context.mounted) return;
    }
  }

  void _confirmDeleteAccount(BuildContext context, AuthProvider auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      try {
        // Delete account through Supabase service
        // TODO: Implement deleteAccount in SupabaseService
        // For now, just call deleteAccount to set the flag
        await auth.deleteAccount();

        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          // AuthWrapper will automatically navigate to LoginScreen with create account mode
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete account: $e'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? AppTheme.error : AppTheme.textSecondary(context),
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: AppTheme.body(context).copyWith(
                  color: isDestructive ? AppTheme.error : null,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }
}
