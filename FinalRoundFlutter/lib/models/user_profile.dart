/// User profile model
class UserProfile {
  final String id;
  final String email;
  String? fullName;
  String? targetRole;
  String? yearsOfExperience;
  String? location;
  String? currency;
  List<String> skills;
  String? avatarUrl;
  DateTime createdAt;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.targetRole,
    this.yearsOfExperience,
    this.location,
    this.currency,
    this.skills = const [],
    this.avatarUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Get first name only for greetings
  String get firstName {
    if (fullName != null && fullName!.isNotEmpty) {
      return fullName!.trim().split(' ').first;
    }
    return email.split('@').first;
  }

  String get displayName => fullName ?? email.split('@').first;

  String get initials {
    if (fullName != null && fullName!.isNotEmpty) {
      final parts = fullName!.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return fullName![0].toUpperCase();
    }
    return email[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'target_role': targetRole,
    'years_of_experience': yearsOfExperience,
    'location': location,
    'currency': currency,
    'skills': skills,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      targetRole: json['target_role'] as String?,
      yearsOfExperience: json['years_of_experience'] as String?,
      location: json['location'] as String?,
      currency: json['currency'] as String?,
      skills: (json['skills'] as List<dynamic>?)?.cast<String>() ?? [],
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  UserProfile copyWith({
    String? fullName,
    String? targetRole,
    String? yearsOfExperience,
    String? location,
    String? currency,
    List<String>? skills,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      targetRole: targetRole ?? this.targetRole,
      yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
      location: location ?? this.location,
      currency: currency ?? this.currency,
      skills: skills ?? this.skills,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
    );
  }
}
