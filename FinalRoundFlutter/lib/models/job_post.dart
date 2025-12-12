import 'package:uuid/uuid.dart';

/// Job post model matching iOS JobPost.swift
class JobPost {
  final String id;
  final String role;
  final String company;
  final String location;
  final String salary;
  final List<String> tags;
  final String? description;
  final List<String>? responsibilities;
  final String? category;
  final String logoName;

  JobPost({
    String? id,
    required this.role,
    required this.company,
    required this.location,
    required this.salary,
    required this.tags,
    this.description,
    this.responsibilities,
    this.category,
    required this.logoName,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'company': company,
    'location': location,
    'salary': salary,
    'tags': tags,
    'description': description,
    'responsibilities': responsibilities,
    'category': category,
    'logoName': logoName,
  };

  factory JobPost.fromJson(Map<String, dynamic> json) {
    return JobPost(
      id: json['id'] as String?,
      role: json['role'] as String? ?? json['title'] as String? ?? 'Unknown',
      company: json['company'] as String? ?? 'Company',
      location: json['location'] as String? ?? 'Remote',
      salary: json['salary'] as String? ?? 'Not specified',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? 
            (json['skills'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String?,
      responsibilities: (json['responsibilities'] as List<dynamic>?)?.cast<String>(),
      category: json['category'] as String?,
      logoName: json['logoName'] as String? ?? 'briefcase.fill',
    );
  }

  static List<JobPost> get examples => [
    JobPost(
      role: 'Senior Procurement Analyst',
      company: 'Zephyr',
      location: 'California',
      salary: '\$78,000',
      tags: ['Accounting', 'Software'],
      logoName: 'briefcase.fill',
    ),
    JobPost(
      role: 'Senior UI Artist',
      company: 'Netflix',
      location: 'California',
      salary: '\$120,000',
      tags: ['Art & Design', 'Digital Entertainment'],
      logoName: 'paintpalette.fill',
    ),
    JobPost(
      role: 'Product Designer',
      company: 'Linear',
      location: 'Remote',
      salary: '\$140,000',
      tags: ['Design', 'Product'],
      logoName: 'pencil.circle.fill',
    ),
  ];

  /// Get icon name for job based on category/tags
  static String iconForCategory(String category) {
    final lowerCategory = category.toLowerCase();
    if (lowerCategory.contains('software') || lowerCategory.contains('engineer') || lowerCategory.contains('developer')) {
      return 'code';
    } else if (lowerCategory.contains('design') || lowerCategory.contains('ui') || lowerCategory.contains('ux')) {
      return 'palette';
    } else if (lowerCategory.contains('data') || lowerCategory.contains('analytics') || lowerCategory.contains('scientist')) {
      return 'analytics';
    } else if (lowerCategory.contains('product') || lowerCategory.contains('manager')) {
      return 'work';
    } else if (lowerCategory.contains('marketing')) {
      return 'campaign';
    } else if (lowerCategory.contains('sales')) {
      return 'trending_up';
    } else if (lowerCategory.contains('finance') || lowerCategory.contains('accounting')) {
      return 'account_balance';
    } else {
      return 'work';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is JobPost && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Result from job search with categories
class JobSearchResult {
  final List<String> categories;
  final List<JobPost> jobs;

  JobSearchResult({
    required this.categories,
    required this.jobs,
  });

  factory JobSearchResult.fromJson(Map<String, dynamic> json) {
    return JobSearchResult(
      categories: (json['categories'] as List<dynamic>?)?.cast<String>() ?? [],
      jobs: (json['jobs'] as List<dynamic>?)
          ?.map((j) => JobPost.fromJson(j as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categories': categories,
      'jobs': jobs.map((j) => j.toJson()).toList(),
    };
  }
}

