import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Interview question model
class InterviewQuestion {
  final String id;
  final String text;
  final QuestionCategory category;
  final Difficulty difficulty;
  QuestionAnswer? answer;

  InterviewQuestion({
    String? id,
    required this.text,
    required this.category,
    required this.difficulty,
    this.answer,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'category': category.value,
    'difficulty': difficulty.value,
    'answer': answer?.toJson(),
  };

  factory InterviewQuestion.fromJson(Map<String, dynamic> json) {
    return InterviewQuestion(
      id: json['id'] as String?,
      text: json['text'] as String,
      category: QuestionCategory.fromString(json['category'] as String),
      difficulty: Difficulty.fromString(json['difficulty'] as String),
      answer: json['answer'] != null 
          ? QuestionAnswer.fromJson(json['answer'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Answer to an interview question
class QuestionAnswer {
  final String transcription;
  final String? audioUrl;
  final String? videoUrl;
  final AnswerEvaluation? evaluation;
  final DateTime timestamp;
  final EyeContactMetrics? eyeContactMetrics;
  final double? confidenceScore;
  final ToneAnalysis? toneAnalysis;
  final double? timeSpent;

  QuestionAnswer({
    required this.transcription,
    this.audioUrl,
    this.videoUrl,
    this.evaluation,
    DateTime? timestamp,
    this.eyeContactMetrics,
    this.confidenceScore,
    this.toneAnalysis,
    this.timeSpent,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'transcription': transcription,
    'audioUrl': audioUrl,
    'videoUrl': videoUrl,
    'evaluation': evaluation?.toJson(),
    'timestamp': timestamp.toIso8601String(),
    'eyeContactMetrics': eyeContactMetrics?.toJson(),
    'confidenceScore': confidenceScore,
    'toneAnalysis': toneAnalysis?.toJson(),
    'timeSpent': timeSpent,
  };

  factory QuestionAnswer.fromJson(Map<String, dynamic> json) {
    return QuestionAnswer(
      transcription: json['transcription'] as String,
      audioUrl: json['audioUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
      evaluation: json['evaluation'] != null
          ? AnswerEvaluation.fromJson(json['evaluation'] as Map<String, dynamic>)
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      eyeContactMetrics: json['eyeContactMetrics'] != null
          ? EyeContactMetrics.fromJson(json['eyeContactMetrics'] as Map<String, dynamic>)
          : null,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble(),
      toneAnalysis: json['toneAnalysis'] != null
          ? ToneAnalysis.fromJson(json['toneAnalysis'] as Map<String, dynamic>)
          : null,
      timeSpent: (json['timeSpent'] as num?)?.toDouble(),
    );
  }
}

/// Eye contact tracking metrics
class EyeContactMetrics {
  final double percentage; // 0-100
  final double totalDuration;
  final double lookingAtCameraDuration;
  final List<EyeContactTimestamp> timestamps;

  EyeContactMetrics({
    required this.percentage,
    required this.totalDuration,
    required this.lookingAtCameraDuration,
    this.timestamps = const [],
  });

  String get formattedPercentage => '${percentage.toStringAsFixed(1)}%';

  Map<String, dynamic> toJson() => {
    'percentage': percentage,
    'totalDuration': totalDuration,
    'lookingAtCameraDuration': lookingAtCameraDuration,
    'timestamps': timestamps.map((t) => t.toJson()).toList(),
  };

  factory EyeContactMetrics.fromJson(Map<String, dynamic> json) {
    return EyeContactMetrics(
      percentage: (json['percentage'] as num).toDouble(),
      totalDuration: (json['totalDuration'] as num).toDouble(),
      lookingAtCameraDuration: (json['lookingAtCameraDuration'] as num).toDouble(),
      timestamps: (json['timestamps'] as List<dynamic>?)
          ?.map((t) => EyeContactTimestamp.fromJson(t as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

class EyeContactTimestamp {
  final double time;
  final bool isLookingAtCamera;

  EyeContactTimestamp({required this.time, required this.isLookingAtCamera});

  Map<String, dynamic> toJson() => {
    'time': time,
    'isLookingAtCamera': isLookingAtCamera,
  };

  factory EyeContactTimestamp.fromJson(Map<String, dynamic> json) {
    return EyeContactTimestamp(
      time: (json['time'] as num).toDouble(),
      isLookingAtCamera: json['isLookingAtCamera'] as bool,
    );
  }
}

/// Tone and speech analysis
class ToneAnalysis {
  final double speechPace; // words per minute
  final int pauseCount;
  final double averagePauseDuration;
  final double volumeVariation; // 0-1 scale
  final SentimentScore sentiment;

  ToneAnalysis({
    required this.speechPace,
    required this.pauseCount,
    required this.averagePauseDuration,
    required this.volumeVariation,
    required this.sentiment,
  });

  String get paceDescription {
    if (speechPace < 100) return 'Slow';
    if (speechPace < 140) return 'Moderate';
    if (speechPace < 180) return 'Fast';
    return 'Very Fast';
  }

  String get formattedPace => '${speechPace.toStringAsFixed(0)} WPM';

  Map<String, dynamic> toJson() => {
    'speechPace': speechPace,
    'pauseCount': pauseCount,
    'averagePauseDuration': averagePauseDuration,
    'volumeVariation': volumeVariation,
    'sentiment': sentiment.toJson(),
  };

  factory ToneAnalysis.fromJson(Map<String, dynamic> json) {
    return ToneAnalysis(
      speechPace: (json['speechPace'] as num).toDouble(),
      pauseCount: json['pauseCount'] as int,
      averagePauseDuration: (json['averagePauseDuration'] as num).toDouble(),
      volumeVariation: (json['volumeVariation'] as num).toDouble(),
      sentiment: SentimentScore.fromJson(json['sentiment'] as Map<String, dynamic>),
    );
  }
}

class SentimentScore {
  final double score; // -1 to 1
  final double confidence; // 0-1

  SentimentScore({required this.score, required this.confidence});

  String get label {
    if (score >= 0.5) return 'Very Positive';
    if (score >= 0.1) return 'Positive';
    if (score >= -0.1) return 'Neutral';
    if (score >= -0.5) return 'Negative';
    return 'Very Negative';
  }

  Map<String, dynamic> toJson() => {
    'score': score,
    'confidence': confidence,
  };

  factory SentimentScore.fromJson(Map<String, dynamic> json) {
    return SentimentScore(
      score: (json['score'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}

/// Answer evaluation from AI
class AnswerEvaluation {
  final int score;
  final List<String> strengths;
  final List<String> improvements;
  final String feedback;

  AnswerEvaluation({
    required this.score,
    required this.strengths,
    required this.improvements,
    required this.feedback,
  });

  String get grade {
    if (score >= 95) return 'A+';
    if (score >= 90) return 'A';
    if (score >= 85) return 'A-';
    if (score >= 80) return 'B+';
    if (score >= 75) return 'B';
    if (score >= 70) return 'B-';
    if (score >= 65) return 'C+';
    if (score >= 60) return 'C';
    if (score >= 55) return 'C-';
    return 'D';
  }

  Color get gradeColor {
    if (score >= 90) return Colors.green;
    if (score >= 80) return Colors.blue;
    if (score >= 70) return Colors.orange;
    return Colors.red;
  }

  Map<String, dynamic> toJson() => {
    'score': score,
    'strengths': strengths,
    'improvements': improvements,
    'feedback': feedback,
  };

  factory AnswerEvaluation.fromJson(Map<String, dynamic> json) {
    return AnswerEvaluation(
      score: json['score'] as int,
      strengths: (json['strengths'] as List<dynamic>).cast<String>(),
      improvements: (json['improvements'] as List<dynamic>).cast<String>(),
      feedback: json['feedback'] as String,
    );
  }
}

/// Question category enum
enum QuestionCategory {
  behavioral('Behavioral'),
  technical('Technical'),
  situational('Situational'),
  general('General');

  final String value;
  const QuestionCategory(this.value);

  static QuestionCategory fromString(String value) {
    return QuestionCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => QuestionCategory.general,
    );
  }
}

/// Difficulty level enum
enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  final String value;
  const Difficulty(this.value);

  static Difficulty fromString(String value) {
    return Difficulty.values.firstWhere(
      (e) => e.value == value,
      orElse: () => Difficulty.medium,
    );
  }
}

/// Interview session model
class InterviewSession {
  final String id;
  final String role;
  final Difficulty difficulty;
  final List<QuestionCategory> categories;
  int duration; // in seconds
  List<InterviewQuestion> questions;
  int answeredCount;
  int skippedCount;
  DateTime? startTime;
  DateTime? endTime;
  String? userEmail;
  bool enableAudioRecording;
  String experienceLevel;

  InterviewSession({
    String? id,
    required this.role,
    required this.difficulty,
    required this.categories,
    this.duration = 0,
    required this.questions,
    this.answeredCount = 0,
    this.skippedCount = 0,
    this.startTime,
    this.endTime,
    this.userEmail,
    this.enableAudioRecording = true,
    this.experienceLevel = 'Mid Level',
  }) : id = id ?? const Uuid().v4();

  int get totalQuestions => questions.length;
  int get attemptedQuestions => answeredCount + skippedCount;
  int get remainingQuestions => totalQuestions - attemptedQuestions;

  Duration? get sessionDuration {
    if (startTime == null || endTime == null) return null;
    return endTime!.difference(startTime!);
  }

  double get completionRate {
    if (totalQuestions == 0) return 0;
    return answeredCount / totalQuestions;
  }

  double get averageScore {
    final evaluatedQuestions = questions
        .where((q) => q.answer?.evaluation != null)
        .map((q) => q.answer!.evaluation!)
        .toList();
    if (evaluatedQuestions.isEmpty) return 0;
    final totalScore = evaluatedQuestions.fold<int>(0, (sum, e) => sum + e.score);
    return totalScore / evaluatedQuestions.length;
  }

  String get overallGrade {
    final score = averageScore.round();
    if (score >= 95) return 'A+';
    if (score >= 90) return 'A';
    if (score >= 85) return 'A-';
    if (score >= 80) return 'B+';
    if (score >= 75) return 'B';
    if (score >= 70) return 'B-';
    if (score >= 65) return 'C+';
    if (score >= 60) return 'C';
    if (score >= 55) return 'C-';
    return 'D';
  }

  Color get gradeColor {
    final score = averageScore.round();
    if (score >= 90) return Colors.green;
    if (score >= 80) return Colors.blue;
    if (score >= 70) return Colors.orange;
    return Colors.red;
  }

  double get answerRate {
    if (attemptedQuestions == 0) return 0;
    return answeredCount / attemptedQuestions;
  }

  String get formattedDuration {
    final dur = sessionDuration;
    if (dur == null) return 'N/A';
    final minutes = dur.inMinutes;
    final seconds = dur.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  String get formattedDate {
    final date = startTime ?? endTime ?? DateTime.now();
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  double get averageEyeContact {
    final metrics = questions
        .where((q) => q.answer?.eyeContactMetrics != null)
        .map((q) => q.answer!.eyeContactMetrics!)
        .toList();
    if (metrics.isEmpty) return 0;
    return metrics.fold<double>(0, (sum, m) => sum + m.percentage) / metrics.length;
  }

  double get averageConfidenceScore {
    final scores = questions
        .where((q) => q.answer?.confidenceScore != null)
        .map((q) => q.answer!.confidenceScore!)
        .toList();
    if (scores.isEmpty) return 0;
    return scores.fold<double>(0, (sum, s) => sum + s) / scores.length;
  }

  double get averageSpeechPace {
    final analyses = questions
        .where((q) => q.answer?.toneAnalysis != null)
        .map((q) => q.answer!.toneAnalysis!)
        .toList();
    if (analyses.isEmpty) return 0;
    return analyses.fold<double>(0, (sum, a) => sum + a.speechPace) / analyses.length;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'difficulty': difficulty.value,
    'categories': categories.map((c) => c.value).toList(),
    'duration': duration,
    'questions': questions.map((q) => q.toJson()).toList(),
    'answeredCount': answeredCount,
    'skippedCount': skippedCount,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'userEmail': userEmail,
    'enableAudioRecording': enableAudioRecording,
    'experienceLevel': experienceLevel,
  };

  factory InterviewSession.fromJson(Map<String, dynamic> json) {
    return InterviewSession(
      id: json['id'] as String?,
      role: json['role'] as String,
      difficulty: Difficulty.fromString(json['difficulty'] as String),
      categories: (json['categories'] as List<dynamic>)
          .map((c) => QuestionCategory.fromString(c as String))
          .toList(),
      duration: json['duration'] as int? ?? 0,
      questions: (json['questions'] as List<dynamic>)
          .map((q) => InterviewQuestion.fromJson(q as Map<String, dynamic>))
          .toList(),
      answeredCount: json['answeredCount'] as int? ?? 0,
      skippedCount: json['skippedCount'] as int? ?? 0,
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      userEmail: json['userEmail'] as String?,
      enableAudioRecording: json['enableAudioRecording'] as bool? ?? true,
      experienceLevel: json['experienceLevel'] as String? ?? 'Mid Level',
    );
  }
}
