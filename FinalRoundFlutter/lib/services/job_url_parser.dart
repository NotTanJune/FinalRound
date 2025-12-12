import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/job_post.dart';
import 'groq_service.dart';

/// Service for parsing job URLs from LinkedIn, Indeed, etc.
/// Matches iOS LinkedInJobParser.swift
class JobUrlParser {
  static final JobUrlParser instance = JobUrlParser._();
  JobUrlParser._();

  // MARK: - URL Validation

  /// Check if URL is a valid job posting URL
  bool isValidJobUrl(String urlString) {
    final url = Uri.tryParse(urlString);
    if (url == null) return false;

    final host = url.host.toLowerCase();
    final path = url.path.toLowerCase();

    // LinkedIn
    if (host.contains('linkedin.com') || host.contains('lnkd.in')) {
      return path.contains('/jobs/view/') || 
             path.contains('/jobs/') || 
             path.contains('/job/');
    }

    // Indeed
    if (host.contains('indeed.com')) {
      return path.contains('/viewjob') || 
             path.contains('/job/') ||
             path.contains('/jobs/');
    }

    // Glassdoor
    if (host.contains('glassdoor.com')) {
      return path.contains('/job-listing/');
    }

    return false;
  }

  // MARK: - Job Parsing

  /// Parse a job URL and extract job details
  Future<JobPost> parseJobUrl(String urlString) async {
    if (!isValidJobUrl(urlString)) {
      throw JobParserException(JobParserError.invalidUrl);
    }

    final url = Uri.tryParse(urlString);
    if (url == null) {
      throw JobParserException(JobParserError.invalidUrl);
    }

    try {
      // Fetch the page HTML
      final html = await _fetchPageHtml(url);
      
      // Extract job details using Groq LLM
      final job = await _extractJobDetails(html, urlString);
      
      return job;
    } catch (e) {
      debugPrint('Error parsing job URL: $e');
      if (e is JobParserException) rethrow;
      throw JobParserException(JobParserError.parsingError, e.toString());
    }
  }

  // MARK: - HTML Fetching

  Future<String> _fetchPageHtml(Uri url) async {
    try {
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw JobParserException(JobParserError.networkError, 'HTTP ${response.statusCode}');
      }

      final html = response.body;
      
      // Check for auth wall
      if (html.contains('authwall') || html.contains('sign-in-modal')) {
        debugPrint('⚠️ Auth wall detected, attempting to extract metadata...');
      }

      return html;
    } catch (e) {
      if (e is JobParserException) rethrow;
      throw JobParserException(JobParserError.networkError, e.toString());
    }
  }

  // MARK: - Groq LLM Extraction

  Future<JobPost> _extractJobDetails(String html, String sourceUrl) async {
    // Extract Open Graph metadata as fallback
    final ogData = _extractOpenGraphData(html);
    
    // Truncate HTML to avoid token limits
    final truncatedHtml = html.length > 15000 ? html.substring(0, 15000) : html;
    
    // Use Groq to extract structured data
    return await _callGroqForExtraction(truncatedHtml, ogData);
  }

  Map<String, String> _extractOpenGraphData(String html) {
    final ogData = <String, String>{};
    
    // Extract og:title
    final titleMatch = RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]*)"').firstMatch(html);
    if (titleMatch != null) {
      ogData['title'] = titleMatch.group(1) ?? '';
    }
    
    // Extract og:description
    final descMatch = RegExp(r'<meta[^>]*property="og:description"[^>]*content="([^"]*)"').firstMatch(html);
    if (descMatch != null) {
      ogData['description'] = descMatch.group(1) ?? '';
    }
    
    return ogData;
  }

  Future<JobPost> _callGroqForExtraction(String html, Map<String, String> ogData) async {
    final ogContext = ogData.isEmpty ? '' : '''

Open Graph metadata found:
- Title: ${ogData['title'] ?? 'N/A'}
- Description: ${ogData['description'] ?? 'N/A'}
''';

    final prompt = '''
Extract job posting details from this page HTML and return ONLY valid JSON.
$ogContext

HTML content (truncated):
$html

Return ONLY this JSON format (no markdown, no explanation):
{
    "role": "Job Title",
    "company": "Company Name",
    "location": "City, State/Country or Remote",
    "salary": "Salary range if mentioned, otherwise empty string",
    "tags": ["skill1", "skill2", "skill3"],
    "description": "Brief job description summary (2-3 sentences)",
    "responsibilities": ["responsibility1", "responsibility2", "responsibility3"]
}

Guidelines:
- Extract the exact job title for "role"
- Extract the company name
- For location, extract city/state or note if remote
- For salary, extract if mentioned, otherwise use empty string
- For tags, extract 3-5 key skills/technologies mentioned
- For description, provide a concise 2-3 sentence summary
- For responsibilities, extract 3-5 key responsibilities
- If information is not found, use reasonable defaults based on job title

RETURN ONLY THE JSON, NO OTHER TEXT.
''';

    try {
      // Use the internal _dio from GroqService - we'll call the chat API directly
      final response = await GroqService.instance.generateRaw(
        systemPrompt: 'You are a precise data extraction assistant. Extract job details from HTML and return only valid JSON. Never include markdown formatting or explanations.',
        userPrompt: prompt,
        temperature: 0.1,
        maxTokens: 1000,
      );

      return _parseExtractedJson(response);
    } catch (e) {
      debugPrint('Groq extraction failed: $e');
      
      // Return a basic job from OG data if available
      return JobPost(
        role: ogData['title'] ?? 'Unknown Position',
        company: 'Unknown Company',
        location: 'Location not specified',
        salary: '',
        tags: [],
        description: ogData['description'],
        logoName: 'link',
      );
    }
  }

  JobPost _parseExtractedJson(String content) {
    // Clean up response
    var cleaned = content
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    
    // Find JSON object bounds
    final startIndex = cleaned.indexOf('{');
    final endIndex = cleaned.lastIndexOf('}');
    
    if (startIndex >= 0 && endIndex > startIndex) {
      cleaned = cleaned.substring(startIndex, endIndex + 1);
    }
    
    final json = jsonDecode(cleaned) as Map<String, dynamic>;
    
    return JobPost(
      role: json['role'] as String? ?? 'Unknown Position',
      company: json['company'] as String? ?? 'Unknown Company',
      location: json['location'] as String? ?? 'Location not specified',
      salary: json['salary'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String?,
      responsibilities: (json['responsibilities'] as List<dynamic>?)?.cast<String>(),
      logoName: 'link',
    );
  }
}

// MARK: - Error Types

class JobParserException implements Exception {
  final JobParserError error;
  final String? details;

  JobParserException(this.error, [this.details]);

  @override
  String toString() => details != null ? '${error.message}: $details' : error.message;
}

enum JobParserError {
  invalidUrl,
  networkError,
  parsingError,
  missingApiKey;

  String get message {
    switch (this) {
      case JobParserError.invalidUrl:
        return 'Please enter a valid job posting URL (LinkedIn, Indeed, etc.)';
      case JobParserError.networkError:
        return 'Network error. Please check your connection.';
      case JobParserError.parsingError:
        return 'Could not parse job details from this URL.';
      case JobParserError.missingApiKey:
        return 'API key not configured.';
    }
  }
}
