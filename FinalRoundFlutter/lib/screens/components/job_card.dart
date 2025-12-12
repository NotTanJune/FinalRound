import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/job_post.dart';

/// Job post card matching iOS JobPostCard.swift
class JobCard extends StatelessWidget {
  final JobPost job;
  final VoidCallback? onTap;

  const JobCard({
    super.key,
    required this.job,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(16),
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
                // Company logo placeholder
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.lightGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.business,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.role,
                        style: AppTheme.headline(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        job.company,
                        style: AppTheme.subheadline(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Location and salary
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppTheme.textSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  job.location,
                  style: AppTheme.caption(context),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.attach_money,
                  size: 14,
                  color: AppTheme.textSecondary(context),
                ),
                const SizedBox(width: 2),
                Text(
                  job.salary,
                  style: AppTheme.caption(context),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Tags
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: job.tags.take(3).map((tag) => _buildTag(context, tag)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tag,
        style: AppTheme.font(
          size: 12,
          weight: FontWeight.w500,
          color: AppTheme.textSecondary(context),
        ),
      ),
    );
  }
}
