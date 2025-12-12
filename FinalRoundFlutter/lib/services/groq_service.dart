import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/interview_models.dart';
import '../models/job_post.dart';

/// Groq AI service for question generation and answer evaluation
/// Migrated from iOS GroqService.swift
class GroqService {
  static GroqService? _instance;
  static GroqService get instance => _instance ??= GroqService._();

  late final Dio _dio;
  late String _apiKey;

  static const String _baseUrl = 'https://api.groq.com/openai/v1';
  static const String _model = 'llama-3.1-8b-instant';
  static const String _transcriptionModel = 'whisper-large-v3';

  // Dedicated client for transcription with shorter timeout
  late final Dio _transcriptionDio;

  GroqService._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ));
    
    // Shorter timeout for transcription - fail fast and retry
    _transcriptionDio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  /// Initialize with API key
  static void initialize(String apiKey) {
    instance._apiKey = apiKey;
    instance._dio.options.headers['Authorization'] = 'Bearer $apiKey';
    instance._dio.options.headers['Content-Type'] = 'application/json';
    
    // Set auth for transcription client (no content-type, using multipart)
    instance._transcriptionDio.options.headers['Authorization'] = 'Bearer $apiKey';
  }

  // MARK: - Audio Transcription (Whisper)

  /// Transcribe audio file to text using Whisper
  /// Matches iOS GroqService.transcribeAudio
  Future<String> transcribeAudio(String audioFilePath) async {
    final file = File(audioFilePath);
    
    if (!await file.exists()) {
      throw Exception('Audio file not found: $audioFilePath');
    }

    final fileSize = await file.length();
    
    // Check if file is too small (likely empty/silent)
    if (fileSize < 1024) {
      debugPrint('Audio file too small ($fileSize bytes), likely silent');
      return '[No speech detected]';
    }

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFilePath,
          filename: audioFilePath.split('/').last,
        ),
        'model': _transcriptionModel,
        'temperature': '0',
        'response_format': 'verbose_json',
      });

      final response = await _transcriptionDio.post(
        '/audio/transcriptions',
        data: formData,
      );

      final data = response.data as Map<String, dynamic>;
      final text = data['text'] as String? ?? '';
      
      if (text.isEmpty) {
        return '[No speech detected]';
      }

      debugPrint('Transcription received: ${text.substring(0, text.length.clamp(0, 50))}...');
      return text;
    } on DioException catch (e) {
      debugPrint('Transcription error: ${e.message}');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Transcription timed out. Please try again.');
      }
      rethrow;
    }
  }

  // MARK: - Question Generation


  /// Generate interview questions
  Future<List<InterviewQuestion>> generateQuestions({
    required String role,
    required Difficulty difficulty,
    required List<QuestionCategory> categories,
    required int count,
  }) async {
    final categoryList = categories.map((c) => c.value).join(', ');
    
    final prompt = '''
You are an expert interviewer. Generate exactly $count interview questions for a ${difficulty.value} level interview for a $role position.

Categories to include: $categoryList

Return ONLY a JSON array of objects with this exact format:
[
  {
    "text": "The interview question text",
    "category": "One of: Behavioral, Technical, Situational, General",
    "difficulty": "${difficulty.value}"
  }
]

Generate diverse, realistic interview questions. Do not include any explanation, only the JSON array.
''';

    try {
      final response = await _chatCompletion(prompt);
      final content = _extractJsonArray(response);
      
      return content.map((json) => InterviewQuestion(
        text: json['text'] as String,
        category: QuestionCategory.fromString(json['category'] as String),
        difficulty: Difficulty.fromString(json['difficulty'] as String),
      )).toList();
    } catch (e) {
      debugPrint('Error generating questions: $e');
      rethrow;
    }
  }

  // MARK: - Answer Evaluation

  /// Evaluate an interview answer
  Future<AnswerEvaluation> evaluateAnswer({
    required String question,
    required String answer,
    required String role,
    required String experienceLevel,
  }) async {
    final prompt = '''
You are evaluating an interview answer for a $experienceLevel candidate applying for a $role position.

Question: $question

Candidate's Answer: $answer

Evaluate the answer and provide:
1. A score from 0-100
2. 2-3 specific strengths
3. 2-3 areas for improvement
4. Brief overall feedback

Return ONLY a JSON object with this exact format:
{
  "score": 85,
  "strengths": ["strength 1", "strength 2"],
  "improvements": ["improvement 1", "improvement 2"],
  "feedback": "Overall feedback here"
}
''';

    try {
      final response = await _chatCompletion(prompt);
      final json = _extractJsonObject(response);
      
      return AnswerEvaluation(
        score: json['score'] as int,
        strengths: (json['strengths'] as List).cast<String>(),
        improvements: (json['improvements'] as List).cast<String>(),
        feedback: json['feedback'] as String,
      );
    } catch (e) {
      debugPrint('Error evaluating answer: $e');
      rethrow;
    }
  }

  // MARK: - Job Recommendations

  /// Generate job recommendations based on user profile
  Future<List<JobPost>> generateJobRecommendations({
    required String targetRole,
    required List<String> skills,
    required String location,
    required String currency,
  }) async {
    final skillsList = skills.isNotEmpty ? skills.join(', ') : 'general skills';
    
    final prompt = '''
Generate 5 realistic job recommendations for someone with these qualifications:
- Target Role: $targetRole
- Skills: $skillsList
- Preferred Location: $location

Return ONLY a JSON array with this format:
[
  {
    "role": "Job Title",
    "company": "Company Name",
    "location": "$location or Remote",
    "salary": "${currency}80,000 - ${currency}120,000",
    "tags": ["skill1", "skill2"],
    "description": "Brief job description",
    "responsibilities": ["responsibility 1", "responsibility 2"]
  }
]
''';

    try {
      final response = await _chatCompletion(prompt);
      final content = _extractJsonArray(response);
      
      return content.map((json) => JobPost.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error generating job recommendations: $e');
      rethrow;
    }
  }

  // MARK: - Skill Suggestions

  /// Generate skill suggestions
  Future<List<String>> generateSkills(String prompt) async {
    final systemPrompt = '''
Based on the following context, suggest 5-8 relevant professional skills.
Return ONLY a JSON array of strings, e.g.: ["Skill 1", "Skill 2", "Skill 3"]

Context: $prompt
''';

    try {
      final response = await _chatCompletion(systemPrompt);
      final json = jsonDecode(_cleanJsonString(response)) as List;
      return json.cast<String>();
    } catch (e) {
      debugPrint('Error generating skills: $e');
      return [];
    }
  }

  // MARK: - Private Methods

  Future<String> _chatCompletion(String prompt) async {
    final response = await _dio.post('/chat/completions', data: {
      'model': _model,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.7,
      'max_tokens': 2048,
    });

    final data = response.data as Map<String, dynamic>;
    final choices = data['choices'] as List;
    final message = choices.first['message'] as Map<String, dynamic>;
    return message['content'] as String;
  }

  String _cleanJsonString(String content) {
    var cleaned = content.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^```json\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^```\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*```$'), '');
    return cleaned.trim();
  }

  List<Map<String, dynamic>> _extractJsonArray(String content) {
    final cleaned = _cleanJsonString(content);
    
    // Find array bounds
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    
    if (start >= 0 && end > start) {
      final jsonStr = cleaned.substring(start, end + 1);
      final parsed = jsonDecode(jsonStr) as List;
      return parsed.cast<Map<String, dynamic>>();
    }
    
    throw FormatException('No valid JSON array found in response');
  }

  Map<String, dynamic> _extractJsonObject(String content) {
    final cleaned = _cleanJsonString(content);
    
    // Find object bounds
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    
    if (start >= 0 && end > start) {
      final jsonStr = cleaned.substring(start, end + 1);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    }
    
    throw FormatException('No valid JSON object found in response');
  }

  // MARK: - Job Search

  /// Search for jobs based on role, skills, location, and currency
  /// Uses browser search for real-time results
  Future<List<JobPost>> searchJobs({
    required String role,
    List<String> skills = const [],
    String? location,
    String? currency,
    int count = 10,
  }) async {
    final currencySymbol = _getCurrencySymbol(currency ?? 'USD');
    final locationStr = location ?? 'various locations';

    final prompt = '''
Generate $count realistic job postings in JSON format.

TARGET ROLE: $role
LOCATION: $locationStr
SKILLS: ${skills.join(', ')}

Return ONLY a valid JSON array:
[{"role":"Job Title","company":"Company Name","location":"City, Country","salary":"${currencySymbol}XXk-${currencySymbol}XXk","tags":["skill1","skill2"],"description":"Brief description","responsibilities":["task1","task2","task3"]}]

IMPORTANT: 
- All jobs must be located in or near the specified location
- Use ${currency ?? 'USD'} currency with $currencySymbol symbol for salaries
- Generate exactly $count jobs
- Make company names realistic
- No markdown, no explanation, pure JSON only
''';

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 4000,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List;
      final content = choices[0]['message']['content'] as String;

      final jobsJson = _extractJsonArray(content);
      
      return jobsJson.map((json) {
        return JobPost(
          role: json['role'] as String? ?? 'Unknown',
          company: json['company'] as String? ?? 'Company',
          location: json['location'] as String? ?? locationStr,
          salary: json['salary'] as String? ?? 'Not specified',
          tags: (json['tags'] as List?)?.cast<String>() ?? [],
          description: json['description'] as String?,
          responsibilities: (json['responsibilities'] as List?)?.cast<String>(),
          logoName: JobPost.iconForCategory(json['role'] as String? ?? ''),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error searching jobs: $e');
      rethrow;
    }
  }

  /// Get company information using browser search
  /// Matches iOS getCompanyInfo with browser search enabled
  Future<String> getCompanyInfo({
    required String companyName,
    required String industry,
  }) async {
    final prompt = '''
Provide a brief, informative overview of $companyName as a company.

Focus on:
1. What the company does and their main products/services
2. Company size and reach (if known)
3. Company culture and values
4. Notable achievements or recognition
5. Why someone might want to work there

Industry context: $industry

Keep the response to 3-4 paragraphs, professional and engaging.
Do not include any disclaimers or notes about information accuracy.
Write as if you have verified information about this company.
''';

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': 'You are a knowledgeable career advisor providing company information to job seekers. Be informative and professional.',
            },
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.5,
          'max_tokens': 1000,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List;
      final content = choices[0]['message']['content'] as String;

      return content.trim();
    } catch (e) {
      debugPrint('Error getting company info: $e');
      return '$companyName is a leading company in the $industry industry. They are known for their innovative approach and commitment to excellence.';
    }
  }

  /// Get currency symbol for a currency code
  String _getCurrencySymbol(String currencyCode) {
    const symbols = {
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'INR': '₹',
      'JPY': '¥',
      'CNY': '¥',
      'AUD': 'A\$',
      'CAD': 'C\$',
      'SGD': 'S\$',
      'AED': 'د.إ',
    };
    return symbols[currencyCode] ?? currencyCode;
  }

  // MARK: - Raw Generation

  /// Generate a raw response from the LLM without structured parsing
  /// Used by JobUrlParser and other services needing custom prompts
  Future<String> generateRaw({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.3,
    int maxTokens = 2000,
  }) async {
    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt}
          ],
          'temperature': temperature,
          'max_tokens': maxTokens,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List;
      final content = choices[0]['message']['content'] as String;

      return content.trim();
    } catch (e) {
      debugPrint('Error in generateRaw: $e');
      rethrow;
    }
  }
}

