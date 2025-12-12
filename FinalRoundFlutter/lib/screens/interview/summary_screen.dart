import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/interview_models.dart';
import '../../services/groq_service.dart';
import '../../services/supabase_service.dart';
import '../home/main_tab_screen.dart';

/// Session summary screen matching iOS SessionSummaryView.swift
/// Shows analysis progress, grade, stats, insights, and question breakdown
class SummaryScreen extends StatefulWidget {
  final InterviewSession session;
  final bool isFromHistory;

  const SummaryScreen({
    super.key, 
    required this.session,
    this.isFromHistory = false,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late InterviewSession _session;
  bool _isAnalyzing = false;
  int _completedCount = 0;
  bool _hasSaved = false;
  
  // Aggregated insights
  List<String> _strengths = [];
  List<String> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    
    if (!widget.isFromHistory) {
      _startAnalysis();
    }
  }

  Future<void> _startAnalysis() async {
    setState(() => _isAnalyzing = true);

    // Count answered questions
    final answeredQuestions = _session.questions.where(
      (q) => q.answer != null && q.answer!.transcription.isNotEmpty
    ).toList();

    for (int i = 0; i < _session.questions.length; i++) {
      final question = _session.questions[i];
      
      if (question.answer != null && 
          question.answer!.transcription.isNotEmpty &&
          question.answer!.transcription != '[No speech detected]' &&
          question.answer!.transcription != '[Transcription failed]' &&
          question.answer!.evaluation == null) {
        try {
          final evaluation = await GroqService.instance.evaluateAnswer(
            question: question.text,
            answer: question.answer!.transcription,
            role: _session.role,
            experienceLevel: _session.experienceLevel,
          );

          if (mounted) {
            setState(() {
              _session.questions[i].answer = QuestionAnswer(
                transcription: question.answer!.transcription,
                audioUrl: question.answer!.audioUrl,
                videoUrl: question.answer!.videoUrl,
                evaluation: evaluation,
                eyeContactMetrics: question.answer!.eyeContactMetrics,
                confidenceScore: question.answer!.confidenceScore,
                timestamp: question.answer!.timestamp,
                timeSpent: question.answer!.timeSpent,
              );
              _completedCount++;
            });
            
            // Aggregate insights
            _strengths.addAll(evaluation.strengths);
            _recommendations.addAll(evaluation.improvements);
          }
        } catch (e) {
          debugPrint('Error evaluating answer: $e');
          if (mounted) {
            setState(() => _completedCount++);
          }
        }
      } else if (question.answer == null) {
        // Skipped question
        if (mounted) {
          setState(() => _completedCount++);
        }
      } else {
        // Already evaluated or no speech
        if (mounted) {
          setState(() => _completedCount++);
        }
      }
    }

    // Deduplicate and limit insights
    _strengths = _strengths.toSet().take(3).toList();
    _recommendations = _recommendations.toSet().take(3).toList();

    // Save to Supabase
    if (!_hasSaved) {
      try {
        await SupabaseService.instance.saveSession(_session);
        _hasSaved = true;
      } catch (e) {
        debugPrint('Error saving session: $e');
      }
    }

    if (mounted) {
      setState(() => _isAnalyzing = false);
    }
  }

  Color get _gradeColor {
    if (_isAnalyzing) return AppTheme.textSecondary(context);
    final score = _session.averageScore.toInt();
    if (score >= 90) return AppTheme.primary;
    if (score >= 80) return AppTheme.accentBlue;
    if (score >= 70) return Colors.orange;
    return AppTheme.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Analysis progress banner
                    if (_isAnalyzing) _buildProgressBanner(),
                    
                    const SizedBox(height: 16),
                    
                    // Top summary card
                    _buildSummaryCard(),
                    
                    const SizedBox(height: 20),
                    
                    // Stats row
                    _buildStatsRow(),
                    
                    const SizedBox(height: 24),
                    
                    // Analytics overview cards
                    _buildAnalyticsCards(),
                    
                    const SizedBox(height: 24),
                    
                    // Key Insights (only after analysis)
                    if (!_isAnalyzing && (_strengths.isNotEmpty || _recommendations.isNotEmpty))
                      _buildKeyInsights(),
                    
                    const SizedBox(height: 24),
                    
                    // Questions Analysis
                    _buildQuestionsAnalysis(),
                    
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            
            // Bottom actions
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_back,
                color: AppTheme.textPrimary(context),
                size: 20,
              ),
            ),
          ),
          
          const Spacer(),
          
          Text(
            'Feedback',
            style: AppTheme.headline(context),
          ),
          
          const Spacer(),
          
          // Share button
          GestureDetector(
            onTap: _isAnalyzing ? null : _shareResults,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.ios_share,
                color: _isAnalyzing 
                    ? AppTheme.textSecondary(context) 
                    : AppTheme.textPrimary(context),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _shareResults() {
    // TODO: Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share feature coming soon!')),
    );
  }

  Widget _buildProgressBanner() {
    final progress = _session.questions.isNotEmpty 
        ? _completedCount / _session.questions.length 
        : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: AppTheme.primary.withAlpha(50),
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analyzing your responses...',
                  style: AppTheme.font(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_completedCount of ${_session.questions.length} complete',
                  style: AppTheme.font(
                    size: 12,
                    color: AppTheme.primary.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.shadowColor(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAnalyzing ? 'Analyzing...' : 'Great Job!',
                  style: AppTheme.title(context),
                ),
                const SizedBox(height: 4),
                Text(
                  _isAnalyzing 
                      ? 'Processing your responses'
                      : 'You\'ve completed the interview.',
                  style: AppTheme.subheadline(context),
                ),
              ],
            ),
          ),
          
          // Grade circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _gradeColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: _isAnalyzing
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _session.questions.isNotEmpty
                              ? _completedCount / _session.questions.length
                              : 0,
                          strokeWidth: 4,
                          backgroundColor: Colors.white.withAlpha(50),
                          color: Colors.white,
                        ),
                        Text(
                          '$_completedCount/${_session.questions.length}',
                          style: AppTheme.font(
                            size: 14,
                            weight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _session.overallGrade,
                          style: AppTheme.font(
                            size: 28,
                            weight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${_session.averageScore.toInt()}',
                          style: AppTheme.font(
                            size: 14,
                            weight: FontWeight.w500,
                            color: Colors.white.withAlpha(230),
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

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatItem('Role', _session.role)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatItem('Duration', _session.formattedDuration)),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatItem(
            'Questions', 
            '${_session.answeredCount}/${_session.questions.length}',
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: AppTheme.caption(context),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTheme.font(
              size: 14,
              weight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCards() {
    // Calculate averages
    final answeredQuestions = _session.questions.where(
      (q) => q.answer != null
    ).toList();
    
    final avgTimeSpent = answeredQuestions.isNotEmpty
        ? answeredQuestions.map((q) => q.answer!.timeSpent ?? 0).reduce((a, b) => a + b) / answeredQuestions.length
        : 0.0;
    
    final avgEyeContact = answeredQuestions.isNotEmpty
        ? answeredQuestions
            .where((q) => q.answer!.eyeContactMetrics != null)
            .map((q) => q.answer!.eyeContactMetrics!.percentage)
            .fold(0.0, (a, b) => a + b) / 
          answeredQuestions.where((q) => q.answer!.eyeContactMetrics != null).length
        : 0.0;
    
    final avgConfidence = answeredQuestions.isNotEmpty
        ? answeredQuestions
            .where((q) => q.answer!.confidenceScore != null)
            .map((q) => q.answer!.confidenceScore!)
            .fold(0.0, (a, b) => a + b) / 
          answeredQuestions.where((q) => q.answer!.confidenceScore != null).length
        : 0.0;

    return Row(
      children: [
        Expanded(
          child: _buildAnalyticCard(
            'Avg Time',
            '${avgTimeSpent.toStringAsFixed(0)}s',
            Icons.timer_outlined,
            AppTheme.accentBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildAnalyticCard(
            'Eye Contact',
            '${avgEyeContact.toStringAsFixed(0)}%',
            Icons.visibility_outlined,
            AppTheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildAnalyticCard(
            'Confidence',
            '${avgConfidence.toStringAsFixed(0)}%',
            Icons.trending_up,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.font(
              size: 18,
              weight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.caption(context),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyInsights() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Insights',
          style: AppTheme.headline(context),
        ),
        const SizedBox(height: 12),
        
        if (_strengths.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.lightGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Strengths',
                      style: AppTheme.font(
                        size: 16,
                        weight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._strengths.map((strength) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: AppTheme.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strength,
                          style: AppTheme.font(
                            size: 14,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        
        if (_recommendations.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Recommendations',
                      style: AppTheme.font(
                        size: 16,
                        weight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._recommendations.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.key + 1}.',
                        style: AppTheme.font(
                          size: 14,
                          weight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: AppTheme.font(
                            size: 14,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQuestionsAnalysis() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Questions Analysis',
          style: AppTheme.headline(context),
        ),
        const SizedBox(height: 12),
        
        ..._session.questions.asMap().entries.map((entry) {
          final index = entry.key;
          final question = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildQuestionCard(index, question),
          );
        }),
      ],
    );
  }

  Widget _buildQuestionCard(int index, InterviewQuestion question) {
    final answer = question.answer;
    final evaluation = answer?.evaluation;
    final isSkipped = answer == null;
    final isAnalyzing = answer != null && 
                        answer.transcription.isNotEmpty && 
                        answer.transcription != '[No speech detected]' &&
                        evaluation == null && 
                        _isAnalyzing;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.shadowColor(context),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Grade badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSkipped 
                      ? AppTheme.warning.withAlpha(40)
                      : isAnalyzing
                          ? AppTheme.inputBackground(context)
                          : (evaluation?.gradeColor ?? AppTheme.inputBackground(context)).withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: isAnalyzing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        )
                      : Text(
                          isSkipped ? '-' : (evaluation?.grade ?? '-'),
                          style: AppTheme.font(
                            size: 14,
                            weight: FontWeight.bold,
                            color: isSkipped 
                                ? AppTheme.warning 
                                : (evaluation?.gradeColor ?? AppTheme.textSecondary(context)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Question number
              Text(
                'Q${index + 1}',
                style: AppTheme.font(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              
              const Spacer(),
              
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  question.category.value,
                  style: AppTheme.font(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Question text
          Text(
            question.text,
            style: AppTheme.body(context),
          ),
          
          // Status/feedback
          if (isSkipped) ...[
            const SizedBox(height: 8),
            Text(
              'Skipped',
              style: AppTheme.font(
                size: 13,
                weight: FontWeight.w500,
                color: AppTheme.warning,
              ),
            ),
          ] else if (evaluation != null) ...[
            const SizedBox(height: 12),
            Text(
              evaluation.feedback,
              style: AppTheme.subheadline(context),
            ),
          ] else if (answer?.transcription == '[No speech detected]') ...[
            const SizedBox(height: 8),
            Text(
              'No speech detected',
              style: AppTheme.font(
                size: 13,
                weight: FontWeight.w500,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.background(context).withAlpha(0),
            AppTheme.background(context).withAlpha(230),
            AppTheme.background(context),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: widget.isFromHistory
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: PrimaryButtonStyle(),
                child: const Text('Dismiss'),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isAnalyzing ? null : _goToPreps,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: _isAnalyzing 
                            ? AppTheme.border(context) 
                            : AppTheme.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Go to Preps',
                      style: AppTheme.font(
                        size: 16,
                        weight: FontWeight.w600,
                        color: _isAnalyzing 
                            ? AppTheme.textSecondary(context)
                            : AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isAnalyzing ? null : _goHome,
                    style: PrimaryButtonStyle(),
                    child: const Text('Back to Home'),
                  ),
                ),
              ],
            ),
    );
  }

  void _goToPreps() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainTabScreen(initialTab: 1)),
      (route) => false,
    );
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainTabScreen()),
      (route) => false,
    );
  }
}
