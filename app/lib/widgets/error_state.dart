import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Empty-state shown when a screen has NO data because the load failed
/// (network error / Supabase unreachable), distinct from the "genuinely
/// nothing here yet" empty states. Uses theme-aware colors and a clear
/// retry affordance. Visually leans on `cloud_off` to mirror the
/// `OfflineBanner` icon so the two reinforce each other.
class ErrorState extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback onRetry;

  const ErrorState({
    super.key,
    required this.title,
    required this.body,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textMuted = textMutedOf(context);
    final textSecondary = textSecondaryOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: textMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: textMuted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: BorderSide(color: kRed.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
