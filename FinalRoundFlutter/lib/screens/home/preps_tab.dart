import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/interview_models.dart';
import '../../services/supabase_service.dart';
import '../interview/summary_screen.dart';

/// Preps tab showing interview history matching iOS ResultsView
class PrepsTab extends StatefulWidget {
  const PrepsTab({super.key});

  @override
  State<PrepsTab> createState() => _PrepsTabState();
}

class _PrepsTabState extends State<PrepsTab> {
  List<InterviewSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await SupabaseService.instance.fetchSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sessions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSession(InterviewSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Are you sure you want to delete the "${session.role}" interview session?'),
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
      try {
        await SupabaseService.instance.deleteSession(session.id);
        if (mounted) {
          setState(() {
            _sessions.removeWhere((s) => s.id == session.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session deleted')),
          );
        }
      } catch (e) {
        debugPrint('Error deleting session: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete session')),
          );
        }
      }
    }
  }

  void _viewSession(InterviewSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryScreen(
          session: session,
          isFromHistory: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header - matching iOS navigation bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interview Preps',
                      style: AppTheme.title(context),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Review and learn from your past sessions',
                      style: AppTheme.subheadline(context),
                    ),
                  ],
                ),
              ),
            ),
            
            // Sessions list
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              )
            else if (_sessions.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildSessionCard(_sessions[index]),
                      );
                    },
                    childCount: _sessions.length,
                  ),
                ),
              ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No interviews yet',
            style: AppTheme.title3(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your first interview\nto see it here',
            style: AppTheme.subheadline(context),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(InterviewSession session) {
    return GestureDetector(
      onTap: () => _viewSession(session),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Grade circle
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: session.gradeColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      session.overallGrade,
                      style: AppTheme.font(
                        size: 18,
                        weight: FontWeight.bold,
                        color: session.gradeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Role and date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.role,
                        style: AppTheme.headline(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.formattedDate,
                        style: AppTheme.caption(context),
                      ),
                    ],
                  ),
                ),
                // Delete button
                IconButton(
                  onPressed: () => _deleteSession(session),
                  icon: Icon(
                    Icons.delete_outline,
                    color: AppTheme.textSecondary(context),
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.check_circle_outline,
                  value: '${session.answeredCount}',
                  label: 'Answered',
                ),
                const SizedBox(width: 16),
                _buildStatItem(
                  icon: Icons.skip_next_outlined,
                  value: '${session.skippedCount}',
                  label: 'Skipped',
                ),
                const SizedBox(width: 16),
                _buildStatItem(
                  icon: Icons.timer_outlined,
                  value: session.formattedDuration,
                  label: 'Duration',
                ),
                const Spacer(),
                // Score badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: session.gradeColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${session.averageScore.toInt()}%',
                    style: AppTheme.font(
                      size: 14,
                      weight: FontWeight.w600,
                      color: session.gradeColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 4),
            Text(
              value,
              style: AppTheme.font(
                size: 14,
                weight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTheme.font(
            size: 11,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}
