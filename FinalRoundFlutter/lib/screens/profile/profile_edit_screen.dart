import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/location_service.dart';
import '../../services/job_cache.dart';
import '../../services/supabase_service.dart';

/// Profile edit screen matching iOS ProfileEditView.swift
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _targetRoleController = TextEditingController();
  final _locationController = TextEditingController();
  final _customSkillController = TextEditingController();
  final _locationFocusNode = FocusNode();

  String? _selectedExperienceLevel;
  Set<String> _selectedSkills = {};
  String _currency = 'USD';
  bool _isLocationLocked = true;
  bool _isSaving = false;

  // Original values for change detection
  late UserProfile? _originalProfile;
  String _originalLocation = '';
  String _originalCurrency = '';
  String _originalRole = '';
  String _originalExperienceLevel = '';
  Set<String> _originalSkills = {};

  static const List<String> experienceLevels = [
    'Beginner',
    'Mid Level',
    'Senior',
    'Executive',
  ];

  static const List<String> suggestedSkills = [
    'Python', 'JavaScript', 'Java', 'Flutter', 'React',
    'Data Analysis', 'Machine Learning', 'SQL', 'AWS',
    'Product Management', 'Leadership', 'Communication',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _locationFocusNode.addListener(_onLocationFocusChange);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _targetRoleController.dispose();
    _locationController.dispose();
    _customSkillController.dispose();
    _locationFocusNode.removeListener(_onLocationFocusChange);
    _locationFocusNode.dispose();
    super.dispose();
  }

  void _loadProfile() {
    final auth = context.read<AuthProvider>();
    final profile = auth.userProfile;
    _originalProfile = profile;

    if (profile != null) {
      _fullNameController.text = profile.fullName ?? '';
      _targetRoleController.text = profile.targetRole ?? '';
      _locationController.text = profile.location ?? '';
      _selectedExperienceLevel = profile.yearsOfExperience;
      _selectedSkills = Set<String>.from(profile.skills ?? []);
      _currency = profile.currency ?? 'USD';

      // Store originals
      _originalLocation = profile.location ?? '';
      _originalCurrency = profile.currency ?? 'USD';
      _originalRole = profile.targetRole ?? '';
      _originalExperienceLevel = profile.yearsOfExperience ?? '';
      _originalSkills = Set<String>.from(profile.skills ?? []);
    }
  }

  void _onLocationFocusChange() {
    if (!_locationFocusNode.hasFocus) {
      // Clear suggestions when focus lost
      LocationService.instance.clearSuggestions();
    }
  }

  bool get _hasJobRelevantChanges {
    return _locationController.text != _originalLocation ||
        _currency != _originalCurrency ||
        _targetRoleController.text != _originalRole ||
        _selectedExperienceLevel != _originalExperienceLevel ||
        !_selectedSkills.containsAll(_originalSkills) ||
        !_originalSkills.containsAll(_selectedSkills);
  }

  bool get _canSave {
    return _fullNameController.text.trim().isNotEmpty &&
        _targetRoleController.text.trim().isNotEmpty &&
        _selectedExperienceLevel != null &&
        _selectedSkills.length >= 3;
  }

  Future<void> _searchLocation(String query) async {
    if (query.length < 2) {
      LocationService.instance.clearSuggestions();
      return;
    }
    await LocationService.instance.searchLocations(query);
    if (mounted) setState(() {});
  }

  void _selectLocation(LocationInfo location) {
    setState(() {
      _locationController.text = location.displayName;
      _currency = location.currency;
      _isLocationLocked = true;
    });
    LocationService.instance.clearSuggestions();
    _locationFocusNode.unfocus();
  }

  void _unlockLocation() {
    setState(() => _isLocationLocked = false);
    _locationFocusNode.requestFocus();
  }

  void _addSkill(String skill) {
    if (skill.isNotEmpty && !_selectedSkills.contains(skill)) {
      setState(() {
        _selectedSkills.add(skill);
        _customSkillController.clear();
      });
    }
  }

  void _removeSkill(String skill) {
    setState(() => _selectedSkills.remove(skill));
  }

  Future<void> _saveProfile() async {
    if (!_canSave) return;

    setState(() => _isSaving = true);
    
    // Store before updating
    final shouldRefreshJobs = _hasJobRelevantChanges;

    try {
      final auth = context.read<AuthProvider>();
      
      // Update profile in Supabase
      await SupabaseService.instance.updateProfileFields(
        fullName: _fullNameController.text.trim(),
        targetRole: _targetRoleController.text.trim(),
        yearsOfExperience: _selectedExperienceLevel!,
        skills: _selectedSkills.toList(),
        location: _locationController.text.trim(),
        currency: _currency,
      );

      // If job-relevant changes, invalidate cache
      if (shouldRefreshJobs) {
        debugPrint('🔄 Job-relevant profile changes detected, invalidating job cache');
        JobCache.instance.clearCacheForUser(auth.userProfile?.email ?? '');
      }

      // Refresh user profile in auth provider
      await auth.refreshProfile();

      if (mounted) {
        // Return whether jobs need to be refreshed
        Navigator.pop(context, {'saved': true, 'needsJobRefresh': shouldRefreshJobs});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.background(context),
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTheme.font(
              size: 16,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ),
        title: Text(
          'Edit Profile',
          style: AppTheme.font(
            size: 17,
            weight: FontWeight.w600,
            color: AppTheme.textPrimary(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _canSave && !_isSaving ? _saveProfile : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: AppTheme.font(
                      size: 16,
                      weight: FontWeight.w600,
                      color: _canSave ? AppTheme.primary : AppTheme.textSecondary(context),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildSection('Full Name', Icons.person, _buildNameField()),
            const SizedBox(height: 24),
            _buildSection('Target Role', Icons.work, _buildRoleField()),
            const SizedBox(height: 24),
            _buildSection('Experience Level', Icons.bar_chart, _buildExperienceLevel()),
            const SizedBox(height: 24),
            _buildSection('Skills', Icons.star, _buildSkillsSection()),
            const SizedBox(height: 24),
            _buildSection('Location', Icons.location_on, _buildLocationSection()),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 8),
            Text(
              title,
              style: AppTheme.font(
                size: 14,
                weight: FontWeight.w600,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _fullNameController,
      style: AppTheme.font(size: 16, color: AppTheme.textPrimary(context)),
      decoration: _inputDecoration('Your full name'),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildRoleField() {
    return TextField(
      controller: _targetRoleController,
      style: AppTheme.font(size: 16, color: AppTheme.textPrimary(context)),
      decoration: _inputDecoration('e.g., Product Manager'),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildExperienceLevel() {
    return Column(
      children: experienceLevels.map((level) {
        final isSelected = _selectedExperienceLevel == level;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() => _selectedExperienceLevel = level),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    level,
                    style: AppTheme.font(
                      size: 15,
                      weight: FontWeight.w500,
                      color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? Colors.white : AppTheme.textSecondary(context).withValues(alpha: 0.3),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSkillsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected skills
        if (_selectedSkills.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedSkills.map((skill) {
              return GestureDetector(
                onTap: () => _removeSkill(skill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        skill,
                        style: AppTheme.font(size: 14, weight: FontWeight.w500, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.close, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 12),

        // Add skill input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customSkillController,
                style: AppTheme.font(size: 15, color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: 'Add a skill',
                  hintStyle: AppTheme.font(size: 15, color: AppTheme.textSecondary(context)),
                  filled: true,
                  fillColor: AppTheme.cardBackground(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: _addSkill,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _addSkill(_customSkillController.text.trim()),
              child: Icon(
                Icons.add_circle,
                size: 28,
                color: _customSkillController.text.trim().isNotEmpty
                    ? AppTheme.primary
                    : AppTheme.textSecondary(context).withValues(alpha: 0.3),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Suggested skills
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestedSkills
              .where((s) => !_selectedSkills.contains(s))
              .take(6)
              .map((skill) {
            return GestureDetector(
              onTap: () => _addSkill(skill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                child: Text(
                  skill,
                  style: AppTheme.font(size: 13, color: AppTheme.textSecondary(context)),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        Text(
          'Select at least 3 skills',
          style: AppTheme.font(
            size: 12,
            color: _selectedSkills.length >= 3 ? AppTheme.primary : AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection() {
    return ListenableBuilder(
      listenable: LocationService.instance,
      builder: (context, _) {
        final suggestions = LocationService.instance.suggestions;
        final isSearching = LocationService.instance.isSearching;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLocationLocked) ...[
              // Locked state - show location with edit button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _locationController.text.isEmpty ? 'Not set' : _locationController.text,
                            style: AppTheme.font(
                              size: 16,
                              weight: FontWeight.w500,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${LocationService.getSymbol(_currency)} $_currency',
                            style: AppTheme.font(
                              size: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _unlockLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.lightGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 14, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Edit',
                              style: AppTheme.font(
                                size: 14,
                                weight: FontWeight.w500,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Unlocked state - text field
              TextField(
                controller: _locationController,
                focusNode: _locationFocusNode,
                style: AppTheme.font(size: 16, color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: 'Start typing a city...',
                  hintStyle: AppTheme.font(size: 16, color: AppTheme.textSecondary(context)),
                  filled: true,
                  fillColor: AppTheme.cardBackground(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: suggestions.isNotEmpty
                        ? BorderSide(color: AppTheme.primary)
                        : BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                  suffixIcon: isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _searchLocation,
              ),

              // Suggestions dropdown
              if (suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground(context),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: suggestions.map((suggestion) {
                      return ListTile(
                        leading: Icon(Icons.location_on, color: AppTheme.primary),
                        title: Text(
                          suggestion.city,
                          style: AppTheme.font(
                            size: 15,
                            weight: FontWeight.w500,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        subtitle: Text(
                          suggestion.country,
                          style: AppTheme.font(size: 12, color: AppTheme.textSecondary(context)),
                        ),
                        trailing: Text(
                          '${LocationService.getSymbol(suggestion.currency)} ${suggestion.currency}',
                          style: AppTheme.font(size: 12, color: AppTheme.textSecondary(context)),
                        ),
                        onTap: () => _selectLocation(suggestion),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.font(size: 16, color: AppTheme.textSecondary(context)),
      filled: true,
      fillColor: AppTheme.cardBackground(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(16),
    );
  }
}
