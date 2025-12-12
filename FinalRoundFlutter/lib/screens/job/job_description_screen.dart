import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/job_post.dart';
import '../../services/groq_service.dart';
import '../../services/job_cache.dart';
import '../interview/setup_screen.dart';

/// Job description screen matching iOS JobDescriptionView.swift
/// Shows job details and company info with tabs
class JobDescriptionScreen extends StatefulWidget {
  final JobPost job;

  const JobDescriptionScreen({super.key, required this.job});

  @override
  State<JobDescriptionScreen> createState() => _JobDescriptionScreenState();
}

class _JobDescriptionScreenState extends State<JobDescriptionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _companyInfo;
  bool _isLoadingCompanyInfo = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _companyInfo == null && !_isLoadingCompanyInfo) {
      _loadCompanyInfo();
    }
  }

  Future<void> _loadCompanyInfo() async {
    // Check cache first
    final cached = JobCache.instance.getCachedCompanyInfo(widget.job.company);
    if (cached != null) {
      setState(() => _companyInfo = cached);
      return;
    }

    setState(() => _isLoadingCompanyInfo = true);

    try {
      final info = await GroqService.instance.getCompanyInfo(
        companyName: widget.job.company,
        industry: widget.job.tags.isNotEmpty ? widget.job.tags.first : 'technology',
      );

      // Cache the result
      await JobCache.instance.cacheCompanyInfo(info, widget.job.company);

      if (mounted) {
        setState(() {
          _companyInfo = info;
          _isLoadingCompanyInfo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _companyInfo = '${widget.job.company} is a leading company in the ${widget.job.tags.isNotEmpty ? widget.job.tags.first : "tech"} industry.';
          _isLoadingCompanyInfo = false;
        });
      }
    }
  }

  void _generateInterview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InterviewSetupScreen(job: widget.job),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            _buildAppBar(),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildTags(),
                      const SizedBox(height: 24),
                      _buildTabBar(),
                      const SizedBox(height: 20),
                      _buildTabContent(),
                      const SizedBox(height: 100), // Space for bottom bar
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back,
                color: AppTheme.textPrimary(context),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo
        Container(
          width: 64,
          height: 64,
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
          child: Icon(
            Icons.work_outline,
            size: 32,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(width: 16),
        // Job info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.job.role,
                style: AppTheme.font(
                  size: 22,
                  weight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  Text(
                    widget.job.salary,
                    style: AppTheme.font(
                      size: 14,
                      weight: FontWeight.w500,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  Text(
                    '•',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  Text(
                    widget.job.company,
                    style: AppTheme.font(
                      size: 14,
                      color: AppTheme.textSecondary(context),
                    ),
                    softWrap: true,
                  ),
                  Text(
                    '•',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  Text(
                    widget.job.location,
                    style: AppTheme.font(
                      size: 14,
                      color: AppTheme.textSecondary(context),
                    ),
                    softWrap: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTags() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.job.tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _tagColor(tag),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            tag,
            style: AppTheme.font(
              size: 12,
              weight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _tagColor(String tag) {
    final lowerTag = tag.toLowerCase();
    if (lowerTag.contains('software') || lowerTag.contains('python') || lowerTag.contains('java')) {
      return AppTheme.lightGreen;
    } else if (lowerTag.contains('design') || lowerTag.contains('ui') || lowerTag.contains('ux')) {
      return Colors.orange.withValues(alpha: 0.3);
    } else if (lowerTag.contains('data') || lowerTag.contains('ml') || lowerTag.contains('ai')) {
      return Colors.blue.withValues(alpha: 0.3);
    }
    return AppTheme.lightGreen;
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.border(context),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppTheme.textPrimary(context),
        unselectedLabelColor: AppTheme.textSecondary(context),
        labelStyle: AppTheme.font(size: 15, weight: FontWeight.w600),
        unselectedLabelStyle: AppTheme.font(size: 15, weight: FontWeight.w500),
        indicatorColor: AppTheme.textPrimary(context),
        indicatorWeight: 2,
        tabs: const [
          Tab(text: 'Job Detail'),
          Tab(text: 'About Company'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        if (_tabController.index == 0) {
          return _buildJobDetailTab();
        } else {
          return _buildAboutCompanyTab();
        }
      },
    );
  }

  Widget _buildJobDetailTab() {
    final description = widget.job.description ??
        'This is an exciting opportunity to join a dynamic team and work on challenging projects. The ideal candidate will have strong technical skills and a passion for innovation.';

    final responsibilities = widget.job.responsibilities ??
        [
          'Collaborate with cross-functional teams to define and implement solutions',
          'Write clean, maintainable, and efficient code',
          'Participate in code reviews and knowledge sharing',
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Description',
          style: AppTheme.font(
            size: 18,
            weight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: AppTheme.font(
            size: 15,
            color: AppTheme.textSecondary(context),
          ).copyWith(height: 1.6),
          softWrap: true,
          maxLines: null,
        ),
        const SizedBox(height: 24),
        Text(
          'Responsibilities',
          style: AppTheme.font(
            size: 18,
            weight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        ...responsibilities.asMap().entries.map((entry) {
          return _buildResponsibilityRow(entry.key + 1, entry.value);
        }),
      ],
    );
  }

  Widget _buildResponsibilityRow(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Center(
              child: Text(
                '$number',
                style: AppTheme.font(
                  size: 12,
                  weight: FontWeight.bold,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTheme.font(
                size: 14,
                color: AppTheme.textSecondary(context),
              ).copyWith(height: 1.6),
              softWrap: true,
              maxLines: null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCompanyTab() {
    if (_isLoadingCompanyInfo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Loading company information...',
                style: AppTheme.font(
                  size: 14,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About ${widget.job.company}',
          style: AppTheme.font(
            size: 18,
            weight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _companyInfo ?? 'Unable to load company information at this time.',
          style: AppTheme.font(
            size: 15,
            color: AppTheme.textSecondary(context),
          ).copyWith(height: 1.6),
          softWrap: true,
          maxLines: null,
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _generateInterview,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_fix_high, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Generate Interview',
              style: AppTheme.font(
                size: 16,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
