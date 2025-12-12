import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../models/job_post.dart';
import '../../services/groq_service.dart';
import '../../services/job_cache.dart';
import '../../services/job_url_parser.dart';
import '../interview/setup_screen.dart';
import '../job/job_description_screen.dart';
import '../components/job_card.dart';

/// Home tab matching iOS HomeTab in MainTabView.swift
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<JobPost> _recommendedJobs = [];
  bool _isLoadingJobs = false;
  final TextEditingController _jobUrlController = TextEditingController();
  bool _isParsingUrl = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendedJobs();
    
    // Listen for job refresh triggers from profile changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().addListener(_onAuthChanged);
    });
  }

  @override
  void dispose() {
    _jobUrlController.dispose();
    // Remove listener safely
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }
  
  void _onAuthChanged() {
    final auth = context.read<AuthProvider>();
    if (auth.needsJobRefresh) {
      debugPrint('🔄 HomeTab detected job refresh trigger, reloading jobs...');
      auth.clearJobRefreshFlag();
      _forceRefreshJobs();
    }
  }
  
  /// Force refresh jobs bypassing cache
  Future<void> _forceRefreshJobs() async {
    final auth = context.read<AuthProvider>();
    final profile = auth.userProfile;
    
    setState(() => _isLoadingJobs = true);
    
    try {
      final jobs = await GroqService.instance.searchJobs(
        role: profile?.targetRole ?? 'Software Engineer',
        skills: profile?.skills ?? ['Programming', 'Problem Solving'],
        location: profile?.location,
        currency: profile?.currency,
        count: 5,
      );
      
      // Cache the new results
      final userId = profile?.email ?? 'anonymous';
      await JobCache.instance.cacheJobs(jobs, userId);
      
      if (mounted) {
        setState(() {
          _recommendedJobs = jobs;
          _isLoadingJobs = false;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing jobs: $e');
      if (mounted) {
        setState(() {
          _recommendedJobs = JobPost.examples;
          _isLoadingJobs = false;
        });
      }
    }
  }

  Future<void> _loadRecommendedJobs() async {
    final auth = context.read<AuthProvider>();
    final profile = auth.userProfile;
    final userId = profile?.email ?? 'anonymous';

    // Check cache first
    final cachedJobs = JobCache.instance.getCachedJobs(userId);
    if (cachedJobs != null && cachedJobs.isNotEmpty) {
      setState(() {
        _recommendedJobs = cachedJobs;
        _isLoadingJobs = false;
      });
      return;
    }

    setState(() => _isLoadingJobs = true);
    
    try {
      final jobs = await GroqService.instance.searchJobs(
        role: profile?.targetRole ?? 'Software Engineer',
        skills: profile?.skills ?? ['Programming', 'Problem Solving'],
        location: profile?.location,
        currency: profile?.currency,
        count: 5,
      );
      
      // Cache the results
      await JobCache.instance.cacheJobs(jobs, userId);
      
      if (mounted) {
        setState(() {
          _recommendedJobs = jobs;
          _isLoadingJobs = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading jobs: $e');
      if (mounted) {
        setState(() {
          _recommendedJobs = JobPost.examples;
          _isLoadingJobs = false;
        });
      }
    }
  }

  Future<void> _parseJobUrl() async {
    final url = _jobUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a job URL')),
      );
      return;
    }

    // Validate URL format
    if (!JobUrlParser.instance.isValidJobUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid LinkedIn or Indeed job URL')),
      );
      return;
    }

    setState(() => _isParsingUrl = true);
    
    try {
      final job = await JobUrlParser.instance.parseJobUrl(url);
      
      if (mounted) {
        // Clear the input
        _jobUrlController.clear();
        
        // Navigate to job description screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobDescriptionScreen(job: job),
          ),
        );
      }
    } on JobParserException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.error.message)),
        );
      }
    } catch (e) {
      debugPrint('Error parsing job URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to parse job URL')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isParsingUrl = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStartPreparationCard(),
                    const SizedBox(height: 20),
                    _buildJobUrlGenerator(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Recommended Jobs'),
                  ],
                ),
              ),
            ),
            
            // Jobs list
            if (_isLoadingJobs)
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final job = _recommendedJobs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JobDescriptionScreen(job: job),
                              ),
                            );
                          },
                          child: JobCard(job: job),
                        ),
                      );
                    },
                    childCount: _recommendedJobs.length,
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

  Widget _buildHeader() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final firstName = auth.userProfile?.firstName ?? 'there';
        
        return Row(
          children: [
            // Profile avatar on LEFT (iOS style)
            GestureDetector(
              onTap: () {
                // Navigate to profile - handled by tab
              },
              child: CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.lightGreen,
                backgroundImage: auth.userProfile?.avatarUrl != null
                    ? NetworkImage(auth.userProfile!.avatarUrl!)
                    : null,
                child: auth.userProfile?.avatarUrl == null
                    ? Text(
                        auth.userProfile?.initials ?? '?',
                        style: AppTheme.font(
                          size: 16,
                          weight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Greeting text next to avatar
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hi $firstName 👋',
                    style: AppTheme.title2(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Let's ace your next interview",
                    style: AppTheme.subheadline(context),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStartPreparationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, Color(0xFF1FAF69)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start Preparation',
            style: AppTheme.font(
              size: 22,
              weight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Practice with AI-generated questions tailored to your target role',
            style: AppTheme.font(
              size: 14,
              color: Colors.white.withAlpha(230),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InterviewSetupScreen()),
                );
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text('Generate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: AppTheme.font(
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobUrlGenerator() {
    return Container(
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.link,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Generate from Job URL',
                style: AppTheme.font(
                  size: 16,
                  weight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Paste a job listing URL to generate tailored interview questions',
            style: AppTheme.caption(context),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jobUrlController,
                  style: AppTheme.body(context),
                  decoration: InputDecoration(
                    hintText: 'Paste job URL here...',
                    hintStyle: AppTheme.subheadline(context),
                    filled: true,
                    fillColor: AppTheme.inputBackground(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _isParsingUrl ? null : _parseJobUrl,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isParsingUrl
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTheme.headline(context),
        ),
        GestureDetector(
          onTap: () {
            // TODO: Navigate to all jobs screen
          },
          child: Text(
            'See All',
            style: AppTheme.font(
              size: 14,
              weight: FontWeight.w500,
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
