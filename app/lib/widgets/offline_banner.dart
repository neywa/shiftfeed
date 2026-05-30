import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connectivity_notifier.dart';
import '../theme/app_theme.dart';

/// Slim strip rendered above a screen's content while
/// [ConnectivityNotifier] reports offline. Collapses to zero height when
/// online so screen layouts don't shift on toggle. Uses theme-aware
/// colors so it stays legible in both light and dark mode.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityNotifier>().isOnline;
    if (online) return const SizedBox.shrink();

    final fg = textPrimaryOf(context);
    final bg = surface2Of(context);
    final border = borderOf(context);
    return Material(
      color: bg,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 14, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "You're offline — showing what we have",
                style: TextStyle(
                  fontSize: 12,
                  color: fg,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
