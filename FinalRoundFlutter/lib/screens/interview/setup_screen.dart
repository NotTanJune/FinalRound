import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/interview_models.dart';
import '../../models/job_post.dart';
import '../../services/groq_service.dart';
import 'session_screen.dart';

/// Experience level enum matching iOS ProfileSetupViewModel.ExperienceLevel
enum ExperienceLevel {
  beginner('Beginner', 'leaf'),
  mid('Mid Level', 'chart.bar'),
  senior('Senior', 'star'),
  executive('Executive', 'crown');

  final String displayName;
  final String iconName;
  const ExperienceLevel(this.displayName, this.iconName);

  IconData get icon {
    switch (this) {
      case ExperienceLevel.beginner:
        return Icons.eco;
      case ExperienceLevel.mid:
        return Icons.bar_chart;
      case ExperienceLevel.senior:
        return Icons.star;
      case ExperienceLevel.executive:
        return Icons.workspace_premium;
    }
  }
}

/// Interview setup screen matching iOS InterviewSetupView.swift
class InterviewSetupScreen extends StatefulWidget {
  final String? jobUrl;
  final JobPost? job;
  
  const InterviewSetupScreen({super.key, this.jobUrl, this.job});

  @override
  State<InterviewSetupScreen> createState() => _InterviewSetupScreenState();
}

class _InterviewSetupScreenState extends State<InterviewSetupScreen> {
  final _roleController = TextEditingController();
  Difficulty? _selectedDifficulty;
  final Set<QuestionCategory> _selectedCategories = {};
  ExperienceLevel? _selectedExperienceLevel;
  double _questionCount = 5;
  bool _enableAudioRecording = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _prePopulateFromJob();
  }

  /// Pre-populate fields from job posting if available
  void _prePopulateFromJob() {
    final job = widget.job;
    if (job == null) return;

    // Set role from job
    _roleController.text = job.role;

    // Infer difficulty from job title
    final roleLower = job.role.toLowerCase();
    if (roleLower.contains('senior') || roleLower.contains('lead') || roleLower.contains('principal')) {
      _selectedDifficulty = Difficulty.hard;
      _selectedExperienceLevel = ExperienceLevel.senior;
    } else if (roleLower.contains('junior') || roleLower.contains('entry') || roleLower.contains('intern')) {
      _selectedDifficulty = Difficulty.easy;
      _selectedExperienceLevel = ExperienceLevel.beginner;
    } else {
      _selectedDifficulty = Difficulty.medium;
      _selectedExperienceLevel = ExperienceLevel.mid;
    }

    // Infer categories from tags
    for (final tag in job.tags) {
      final tagLower = tag.toLowerCase();
      if (tagLower.contains('tech') || tagLower.contains('software') || 
          tagLower.contains('engineer') || tagLower.contains('python') ||
          tagLower.contains('java') || tagLower.contains('code')) {
        _selectedCategories.add(QuestionCategory.technical);
      }
      if (tagLower.contains('lead') || tagLower.contains('manager') || 
          tagLower.contains('team')) {
        _selectedCategories.add(QuestionCategory.behavioral);
      }
    }

    // Add default categories if none inferred
    if (_selectedCategories.isEmpty) {
      _selectedCategories.add(QuestionCategory.behavioral);
      _selectedCategories.add(QuestionCategory.situational);
    }
  }

  /// Check if all required fields are filled
  bool get _canStartInterview {
    return _roleController.text.trim().isNotEmpty &&
           _selectedCategories.isNotEmpty &&
           _selectedDifficulty != null &&
           _selectedExperienceLevel != null;
  }

  @override
  void dispose() {
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _startInterview() async {
    if (!_canStartInterview) return;

    setState(() => _isGenerating = true);

    try {
      final questions = await GroqService.instance.generateQuestions(
        role: _roleController.text.trim(),
        difficulty: _selectedDifficulty!,
        categories: _selectedCategories.toList(),
        count: _questionCount.toInt(),
      );

      final session = InterviewSession(
        role: _roleController.text.trim(),
        difficulty: _selectedDifficulty!,
        categories: _selectedCategories.toList(),
        questions: questions,
        enableAudioRecording: _enableAudioRecording,
        experienceLevel: _selectedExperienceLevel!.displayName,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SessionScreen(session: session),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating questions: $e');
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate questions: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground(context),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.close, color: AppTheme.textPrimary(context), size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Setup Interview',
          style: AppTheme.headline(context),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role input
                    _buildRoleSection(),
                    
                    const SizedBox(height: 20),
                    
                    // Categories
                    _buildCategoriesSection(),
                    
                    const SizedBox(height: 20),
                    
                    // Difficulty selector
                    _buildDifficultySection(),
                    
                    const SizedBox(height: 20),
                    
                    // Experience level
                    _buildExperienceLevelSection(),
                    
                    const SizedBox(height: 20),
                    
                    // Audio recording toggle
                    _buildAudioRecordingSection(),
                    
                    const SizedBox(height: 20),
                    
                    // Question count slider
                    _buildQuestionsSection(),
                    
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            
            // Start button
            _buildStartButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.shadowColor(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTheme.font(
        size: 17,
        weight: FontWeight.w600,
        color: AppTheme.textPrimary(context),
      ),
    );
  }

  Widget _buildRoleSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Interview Role'),
          const SizedBox(height: 12),
          TextField(
            controller: _roleController,
            style: AppTheme.body(context),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. Software Engineer, Product Manager',
              hintStyle: AppTheme.subheadline(context),
              filled: true,
              fillColor: AppTheme.inputBackground(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Question Categories'),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: QuestionCategory.values.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return _buildCategoryButton(category, isSelected);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryButton(QuestionCategory category, bool isSelected) {
    IconData icon;
    switch (category) {
      case QuestionCategory.behavioral:
        icon = Icons.people;
        break;
      case QuestionCategory.technical:
        icon = Icons.computer;
        break;
      case QuestionCategory.situational:
        icon = Icons.lightbulb;
        break;
      case QuestionCategory.general:
        icon = Icons.chat_bubble;
        break;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCategories.remove(category);
          } else {
            _selectedCategories.add(category);
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withAlpha(20) : AppTheme.inputBackground(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border(context),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? AppTheme.primary : AppTheme.textPrimary(context),
            ),
            const SizedBox(height: 8),
            Text(
              category.value,
              style: AppTheme.font(
                size: 14,
                weight: FontWeight.w600,
                color: isSelected ? AppTheme.primary : AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Difficulty Level'),
          const SizedBox(height: 16),
          Row(
            children: Difficulty.values.map((difficulty) {
              final isSelected = _selectedDifficulty == difficulty;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: difficulty != Difficulty.values.last ? 12 : 0,
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDifficulty = difficulty),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : AppTheme.inputBackground(context),
                        borderRadius: BorderRadius.circular(16),
                        border: isSelected 
                            ? null 
                            : Border.all(color: AppTheme.border(context)),
                      ),
                      child: Text(
                        difficulty.value,
                        textAlign: TextAlign.center,
                        style: AppTheme.font(
                          size: 15,
                          weight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceLevelSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Your Experience Level'),
          const SizedBox(height: 4),
          Text(
            'Grading adjusts based on your level',
            style: AppTheme.caption(context),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.8,
            children: ExperienceLevel.values.map((level) {
              final isSelected = _selectedExperienceLevel == level;
              return GestureDetector(
                onTap: () => setState(() => _selectedExperienceLevel = level),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : AppTheme.inputBackground(context),
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected 
                        ? null 
                        : Border.all(color: AppTheme.border(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        level.icon,
                        size: 16,
                        color: isSelected ? Colors.white : AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        level.displayName,
                        style: AppTheme.font(
                          size: 14,
                          weight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioRecordingSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Audio Recording'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _enableAudioRecording = !_enableAudioRecording),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _enableAudioRecording 
                    ? AppTheme.lightGreen.withAlpha(80) 
                    : AppTheme.inputBackground(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _enableAudioRecording 
                        ? Icons.check_box 
                        : Icons.check_box_outline_blank,
                    size: 28,
                    color: _enableAudioRecording 
                        ? AppTheme.primary 
                        : AppTheme.textSecondary(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enable audio recording',
                          style: AppTheme.font(
                            size: 16,
                            weight: FontWeight.w500,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Record your responses for AI-powered transcription and feedback',
                          style: AppTheme.caption(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle('Number of Questions'),
              Text(
                '${_questionCount.toInt()}',
                style: AppTheme.font(
                  size: 17,
                  weight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: AppTheme.border(context),
              thumbColor: AppTheme.primary,
              overlayColor: AppTheme.primary.withAlpha(30),
              trackHeight: 6,
            ),
            child: Slider(
              value: _questionCount,
              min: 3,
              max: 15,
              divisions: 12,
              onChanged: (value) => setState(() => _questionCount = value),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('3', style: AppTheme.caption(context)),
              Text('15', style: AppTheme.caption(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.background(context).withAlpha(0),
            AppTheme.background(context).withAlpha(200),
            AppTheme.background(context),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: AnimatedOpacity(
          opacity: _canStartInterview ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: ElevatedButton.icon(
            onPressed: (_canStartInterview && !_isGenerating) ? _startInterview : null,
            icon: _isGenerating
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_forward),
            label: Text(_isGenerating ? 'Generating Questions...' : 'Start Interview'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.primary.withAlpha(130),
              disabledForegroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: AppTheme.font(
                size: 16,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
