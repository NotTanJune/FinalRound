import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../models/user_profile.dart';

/// Authentication state provider
class AuthProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService.instance;

  bool _isLoading = false;
  String? _errorMessage;
  bool _needsJobRefresh = false;
  bool _justSignedOut = false;
  bool _justDeletedAccount = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _supabase.isAuthenticated;
  UserProfile? get userProfile => _supabase.userProfile;
  String? get userEmail => _supabase.currentUserEmail;
  bool get justSignedOut => _justSignedOut;
  bool get justDeletedAccount => _justDeletedAccount;
  
  /// Flag to indicate jobs need to be refreshed after profile change
  bool get needsJobRefresh => _needsJobRefresh;
  
  void triggerJobRefresh() {
    _needsJobRefresh = true;
    notifyListeners();
  }
  
  void clearJobRefreshFlag() {
    _needsJobRefresh = false;
  }

  AuthProvider() {
    // Listen for profile changes
    _supabase.addListener(_onSupabaseChange);
    
    // If already authenticated, fetch profile
    if (isAuthenticated && userProfile == null) {
      refreshProfile();
    }
  }

  void _onSupabaseChange() {
    notifyListeners();
  }

  /// Sign in with email and password
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabase.signIn(email: email, password: password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign up with email and password
  Future<bool> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabase.signUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    _justSignedOut = true;
    _justDeletedAccount = false;
    await _supabase.signOut();
    notifyListeners();
  }

  /// Delete account
  Future<void> deleteAccount() async {
    _justDeletedAccount = true;
    _justSignedOut = false;
    // Clear any persisted "hasEverSignedIn" flag
    // TODO: If you have shared preferences, clear hasEverSignedIn here
    await _supabase.signOut();
    notifyListeners();
  }

  /// Clear sign out flag after showing login screen
  void clearSignOutFlag() {
    _justSignedOut = false;
    notifyListeners();
  }

  /// Clear delete account flag after showing create account screen
  void clearDeleteAccountFlag() {
    _justDeletedAccount = false;
    notifyListeners();
  }

  /// Refresh user profile
  Future<void> refreshProfile() async {
    await _supabase.fetchProfile();
    notifyListeners();
  }

  /// Update user profile
  Future<bool> updateProfile(UserProfile profile) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _supabase.updateProfile(profile);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Upload profile photo/avatar
  Future<bool> uploadProfilePhoto(Uint8List imageBytes) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _supabase.uploadAvatar(imageBytes);
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to upload photo: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Delete profile photo/avatar
  Future<bool> deleteProfilePhoto() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _supabase.deleteAvatar();
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to delete photo: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Request password reset via magic link
  Future<bool> requestPasswordReset(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabase.resetPassword(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _supabase.removeListener(_onSupabaseChange);
    super.dispose();
  }
}
