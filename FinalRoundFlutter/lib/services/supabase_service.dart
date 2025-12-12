import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../models/interview_models.dart';

/// Supabase service for authentication and database operations
/// Migrated from iOS SupabaseService.swift
class SupabaseService extends ChangeNotifier {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;
  
  // Current user state
  User? get currentUser => client.auth.currentUser;
  String? get currentUserEmail => currentUser?.email;
  bool get isAuthenticated => currentUser != null;
  
  UserProfile? _userProfile;
  UserProfile? get userProfile => _userProfile;

  // Initialize Supabase
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    _instance = SupabaseService._();
    
    // Listen for auth changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      _instance?._handleAuthChange(data.event, data.session);
    });
  }

  void _handleAuthChange(AuthChangeEvent event, Session? session) {
    if (event == AuthChangeEvent.signedIn && session != null) {
      fetchProfile();
    } else if (event == AuthChangeEvent.signedOut) {
      _userProfile = null;
      notifyListeners();
    }
  }

  // MARK: - Authentication

  /// Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.user != null) {
      await fetchProfile();
    }
    return response;
  }

  /// Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: fullName != null ? {'full_name': fullName} : null,
    );
    if (response.user != null) {
      // Create profile
      await _createProfile(
        userId: response.user!.id,
        email: email,
        fullName: fullName,
      );
    }
    return response;
  }

  /// Sign out
  Future<void> signOut() async {
    await client.auth.signOut();
    _userProfile = null;
    notifyListeners();
  }

  /// Send password reset email
  Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  // MARK: - Profile Management

  Future<void> _createProfile({
    required String userId,
    required String email,
    String? fullName,
  }) async {
    await client.from('profiles').insert({
      'id': userId,
      'email': email,
      'full_name': fullName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Fetch current user's profile
  Future<UserProfile?> fetchProfile() async {
    if (currentUser == null) return null;

    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', currentUser!.id)
          .single();

      _userProfile = UserProfile.fromJson(response);
      notifyListeners();
      return _userProfile;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateProfile(UserProfile profile) async {
    await client
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id);
    
    _userProfile = profile;
    notifyListeners();
  }

  /// Update user profile with individual fields
  Future<void> updateProfileFields({
    required String fullName,
    required String targetRole,
    required String yearsOfExperience,
    required List<String> skills,
    required String location,
    required String currency,
  }) async {
    if (currentUser == null) throw Exception('User not authenticated');

    final updates = {
      'full_name': fullName,
      'target_role': targetRole,
      'years_of_experience': yearsOfExperience,
      'skills': skills,
      'location': location,
      'currency': currency,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await client
        .from('profiles')
        .update(updates)
        .eq('id', currentUser!.id);
    
    // Refresh profile
    await fetchProfile();
  }

  /// Upload profile photo
  Future<String?> uploadProfilePhoto(String filePath, String fileName) async {
    try {
      final bytes = await _readFileBytes(filePath);
      final path = 'avatars/${currentUser!.id}/$fileName';
      
      await client.storage.from('avatars').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );

      final url = client.storage.from('avatars').getPublicUrl(path);
      return url;
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }

  Future<Uint8List> _readFileBytes(String path) async {
    // This would use path_provider in a real implementation
    throw UnimplementedError('Use image_picker to get file bytes');
  }

  // MARK: - Interview Sessions

  /// Save an interview session
  Future<void> saveSession(InterviewSession session) async {
    if (currentUserEmail == null) {
      throw Exception('Not authenticated');
    }

    final record = {
      'id': session.id,
      'user_email': currentUserEmail,
      'role': session.role,
      'difficulty': session.difficulty.value,
      'categories': session.categories.map((c) => c.value).toList(),
      'questions': jsonEncode(session.questions.map((q) => q.toJson()).toList()),
      'answered_count': session.answeredCount,
      'skipped_count': session.skippedCount,
      'duration': session.duration,
      'start_time': session.startTime?.toIso8601String(),
      'end_time': session.endTime?.toIso8601String(),
    };

    await client.from('interview_sessions').insert(record);
  }

  /// Fetch all interview sessions for current user
  Future<List<InterviewSession>> fetchSessions() async {
    if (currentUserEmail == null) {
      debugPrint('Warning: fetchSessions called but user not authenticated');
      return [];
    }

    final response = await client
        .from('interview_sessions')
        .select()
        .eq('user_email', currentUserEmail!)
        .order('created_at', ascending: false);

    final List<InterviewSession> sessions = [];
    
    for (final record in (response as List)) {
      try {
        final questionsJson = jsonDecode(record['questions'] as String) as List;
        final questions = questionsJson
            .map((q) => InterviewQuestion.fromJson(q as Map<String, dynamic>))
            .toList();

        // Handle ID that can be int or String
        final dynamic rawId = record['id'];
        final String sessionId = rawId is int ? rawId.toString() : (rawId as String? ?? '');

        sessions.add(InterviewSession(
          id: sessionId,
          role: record['role'] as String,
          difficulty: Difficulty.fromString(record['difficulty'] as String),
          categories: (record['categories'] as List)
              .map((c) => QuestionCategory.fromString(c as String))
              .toList(),
          duration: record['duration'] as int? ?? 0,
          questions: questions,
          answeredCount: record['answered_count'] as int? ?? 0,
          skippedCount: record['skipped_count'] as int? ?? 0,
          startTime: record['start_time'] != null
              ? DateTime.tryParse(record['start_time'] as String)
              : null,
          endTime: record['end_time'] != null
              ? DateTime.tryParse(record['end_time'] as String)
              : null,
          userEmail: record['user_email'] as String?,
        ));
      } catch (e) {
        debugPrint('Error parsing session record: $e');
        // Skip malformed records
        continue;
      }
    }
    
    return sessions;
  }

  /// Delete an interview session
  Future<void> deleteSession(String sessionId) async {
    await client
        .from('interview_sessions')
        .delete()
        .eq('id', sessionId);
  }

  /// Upload user avatar to Supabase storage
  /// Returns the public URL of the uploaded avatar
  Future<String> uploadAvatar(Uint8List imageBytes) async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Validate image size (max 2MB)
      if (imageBytes.length > 2 * 1024 * 1024) {
        throw Exception('Image too large. Maximum size is 2MB.');
      }

      // Create file path: avatars/{userId}.jpg
      final filePath = 'avatars/$userId.jpg';

      debugPrint('Uploading avatar (${ imageBytes.length ~/ 1024}KB) to $filePath');

      // Upload to storage bucket
      final uploadPath = await client.storage.from('avatars').uploadBinary(
            filePath,
            imageBytes,
            fileOptions: const FileOptions(upsert: true),
          );

      debugPrint('Avatar uploaded to: $uploadPath');

      // Get public URL
      final publicUrl = client.storage.from('avatars').getPublicUrl(filePath);

      // Update user profile with avatar URL
      await client.from('profiles').update({
        'avatar_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Update local profile
      if (_userProfile != null) {
        _userProfile = _userProfile!.copyWith(avatarUrl: publicUrl);
        notifyListeners();
      }

      debugPrint('Avatar URL saved to profile: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading avatar: $e');
      rethrow;
    }
  }

  /// Delete user's avatar from storage
  Future<void> deleteAvatar() async {
    try {
      final userId = currentUser?.id;
      if (userId == null) return;

      final filePath = 'avatars/$userId.jpg';

      // Delete from storage
      await client.storage.from('avatars').remove([filePath]);

      // Update profile to remove avatar URL
      await client.from('profiles').update({
        'avatar_url': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Update local profile
      if (_userProfile != null) {
        _userProfile = _userProfile!.copyWith(avatarUrl: null);
        notifyListeners();
      }

      debugPrint('Avatar deleted successfully');
    } catch (e) {
      debugPrint('Error deleting avatar: $e');
      rethrow;
    }
  }
}
