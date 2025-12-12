import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/job_post.dart';

/// Service for caching jobs and company info locally
/// Matches iOS JobCache.swift implementation
class JobCache {
  static final JobCache instance = JobCache._();
  JobCache._();

  // In-memory cache
  final Map<String, _CachedJobData> _jobCache = {};
  final Map<String, _CachedCompanyInfo> _companyInfoCache = {};

  // Cache expiration times
  static const Duration jobCacheExpiration = Duration(hours: 24);
  static const Duration companyInfoExpiration = Duration(days: 7);

  // File paths
  String? _cacheDirectory;

  Future<String> get _cacheDir async {
    if (_cacheDirectory != null) return _cacheDirectory!;
    final dir = await getApplicationDocumentsDirectory();
    _cacheDirectory = dir.path;
    return _cacheDirectory!;
  }

  // MARK: - Job Caching

  /// Cache jobs for a user
  Future<void> cacheJobs(List<JobPost> jobs, String userId) async {
    _jobCache[userId] = _CachedJobData(
      jobs: jobs,
      timestamp: DateTime.now(),
    );
    await _saveJobCacheToDisk();
    debugPrint('✅ Cached ${jobs.length} jobs for user: $userId');
  }

  /// Get cached jobs for a user (returns null if expired or not found)
  List<JobPost>? getCachedJobs(String userId) {
    final cached = _jobCache[userId];
    if (cached == null) return null;

    // Check if cache has expired
    final elapsed = DateTime.now().difference(cached.timestamp);
    if (elapsed > jobCacheExpiration) {
      _jobCache.remove(userId);
      _saveJobCacheToDisk();
      debugPrint('ℹ️ Job cache expired for user: $userId');
      return null;
    }

    debugPrint('✅ Using cached jobs for user: $userId');
    return cached.jobs;
  }

  /// Cache jobs with categories
  Future<void> cacheJobsWithCategories(JobSearchResult result, String userId) async {
    _jobCache[userId] = _CachedJobData(
      jobs: result.jobs,
      timestamp: DateTime.now(),
      categories: result.categories,
    );
    await _saveJobCacheToDisk();
    debugPrint('✅ Cached ${result.jobs.length} jobs with ${result.categories.length} categories');
  }

  /// Get cached jobs with categories
  JobSearchResult? getCachedJobsWithCategories(String userId) {
    final cached = _jobCache[userId];
    if (cached == null || cached.categories == null) return null;

    final elapsed = DateTime.now().difference(cached.timestamp);
    if (elapsed > jobCacheExpiration) {
      _jobCache.remove(userId);
      _saveJobCacheToDisk();
      return null;
    }

    return JobSearchResult(
      categories: cached.categories!,
      jobs: cached.jobs,
    );
  }

  /// Clear all job cache
  void clearCache() {
    _jobCache.clear();
    _saveJobCacheToDisk();
    debugPrint('✅ Cleared all job cache');
  }

  /// Clear cache for a specific user
  void clearCacheForUser(String userId) {
    _jobCache.remove(userId);
    _saveJobCacheToDisk();
    debugPrint('✅ Cleared job cache for user: $userId');
  }

  // MARK: - Company Info Caching

  /// Cache company info
  Future<void> cacheCompanyInfo(String info, String companyName) async {
    final key = companyName.toLowerCase().trim();
    _companyInfoCache[key] = _CachedCompanyInfo(
      info: info,
      timestamp: DateTime.now(),
    );
    await _saveCompanyInfoCacheToDisk();
    debugPrint('✅ Cached company info for: $companyName');
  }

  /// Get cached company info
  String? getCachedCompanyInfo(String companyName) {
    final key = companyName.toLowerCase().trim();
    final cached = _companyInfoCache[key];
    if (cached == null) return null;

    final elapsed = DateTime.now().difference(cached.timestamp);
    if (elapsed > companyInfoExpiration) {
      _companyInfoCache.remove(key);
      _saveCompanyInfoCacheToDisk();
      debugPrint('ℹ️ Company info cache expired for: $companyName');
      return null;
    }

    debugPrint('✅ Using cached company info for: $companyName');
    return cached.info;
  }

  /// Clear company info cache
  void clearCompanyInfoCache() {
    _companyInfoCache.clear();
    _saveCompanyInfoCacheToDisk();
    debugPrint('✅ Cleared all company info cache');
  }

  // MARK: - Disk Persistence

  Future<void> _saveJobCacheToDisk() async {
    try {
      final dir = await _cacheDir;
      final file = File('$dir/job_cache.json');
      
      final data = <String, dynamic>{};
      _jobCache.forEach((key, value) {
        data[key] = {
          'jobs': value.jobs.map((j) => j.toJson()).toList(),
          'timestamp': value.timestamp.toIso8601String(),
          'categories': value.categories,
        };
      });
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save job cache: $e');
    }
  }

  Future<void> loadCacheFromDisk() async {
    try {
      final dir = await _cacheDir;
      final jobFile = File('$dir/job_cache.json');
      final companyFile = File('$dir/company_info_cache.json');

      // Load job cache
      if (await jobFile.exists()) {
        final content = await jobFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        data.forEach((key, value) {
          final jobData = value as Map<String, dynamic>;
          final jobs = (jobData['jobs'] as List)
              .map((j) => JobPost.fromJson(j as Map<String, dynamic>))
              .toList();
          final timestamp = DateTime.parse(jobData['timestamp'] as String);
          final categories = (jobData['categories'] as List?)?.cast<String>();
          
          _jobCache[key] = _CachedJobData(
            jobs: jobs,
            timestamp: timestamp,
            categories: categories,
          );
        });
        debugPrint('✅ Loaded job cache from disk (${_jobCache.length} users)');
      }

      // Load company info cache
      if (await companyFile.exists()) {
        final content = await companyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        data.forEach((key, value) {
          final infoData = value as Map<String, dynamic>;
          _companyInfoCache[key] = _CachedCompanyInfo(
            info: infoData['info'] as String,
            timestamp: DateTime.parse(infoData['timestamp'] as String),
          );
        });
        debugPrint('✅ Loaded company info cache from disk (${_companyInfoCache.length} companies)');
      }
    } catch (e) {
      debugPrint('❌ Failed to load cache from disk: $e');
    }
  }

  Future<void> _saveCompanyInfoCacheToDisk() async {
    try {
      final dir = await _cacheDir;
      final file = File('$dir/company_info_cache.json');
      
      final data = <String, dynamic>{};
      _companyInfoCache.forEach((key, value) {
        data[key] = {
          'info': value.info,
          'timestamp': value.timestamp.toIso8601String(),
        };
      });
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save company info cache: $e');
    }
  }
}

/// Internal class for cached job data
class _CachedJobData {
  final List<JobPost> jobs;
  final DateTime timestamp;
  final List<String>? categories;

  _CachedJobData({
    required this.jobs,
    required this.timestamp,
    this.categories,
  });
}

/// Internal class for cached company info
class _CachedCompanyInfo {
  final String info;
  final DateTime timestamp;

  _CachedCompanyInfo({
    required this.info,
    required this.timestamp,
  });
}
