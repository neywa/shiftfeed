/// Modal bottom sheet that pitches the Pro entitlement, lets the user pick
/// monthly vs annual, and drives [EntitlementService.purchasePackage].
///
/// Surface: bottom sheet with [showModalBottomSheet], rounded top corners,
/// safe-area aware. The visual style adapts to light/dark via
/// [Theme.of(context)] — no hard-coded ShiftFeed colours other than the
/// brand red used as the accent.
library;

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/entitlement_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import 'auth_sheet.dart';

/// Why the paywall was raised — drives the tagline shown above the bullets.
enum PaywallReason { briefing, notifications, sync }

class PaywallSheet extends StatefulWidget {
  final PaywallReason reason;

  const PaywallSheet({super.key, required this.reason});

  // ---- User-visible strings (kept static for easy future l10n) ----

  static const String _kTitle = 'ShiftFeed Pro';
  static const String _kSubtitle = '14-day free trial';

  static const String _kBulletNotifications =
      'Custom CVE & release alerts — your rules, your signal';
  static const String _kBulletBriefing =
      'AI daily briefing — delivered on your schedule';
  static const String _kBulletSync =
      'Bookmarks synced across all your devices';
  static const String _kBulletCustomRss = 'Bring Your Own RSS feed';
  static const String _kBulletHistory = 'Unlimited feed history';

  static const String _kPlanMonthlyLabel = 'Monthly';
  static const String _kPlanAnnualLabel = 'Annual';
  static const String _kPriceMonthly = '\$8.99 / month';
  static const String _kPriceAnnual = '\$64.99 / year';
  static const String _kSavingsBadge = 'Save 40%';

  static const String _kCtaStartTrial = 'Start Free Trial';
  static const String _kCtaRestore = 'Restore purchase';

  static const String _kSnackWelcome = 'Welcome to Pro 🎉';
  static const String _kSnackRestoreSuccess = 'Purchases restored.';
  static const String _kSnackRestoreNothing = 'No purchases to restore.';
  static const String _kSnackOfferingsMissing =
      'Subscriptions are not available right now. Try again later.';

  static const String _kReasonBriefing =
      'Your AI-curated CVE & release digest, every morning.';
  static const String _kReasonNotifications =
      'Get alerted the moment a critical CVE drops.';
  static const String _kReasonSync = 'Your bookmarks, everywhere you are.';

  /// Shows the paywall as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required PaywallReason reason,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaywallSheet(reason: reason),
    );
  }

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

enum _PlanChoice { monthly, annual }

class _PaywallSheetState extends State<PaywallSheet> {
  _PlanChoice _plan = _PlanChoice.annual;
  bool _busy = false;

  String get _reasonTagline {
    switch (widget.reason) {
      case PaywallReason.briefing:
        return PaywallSheet._kReasonBriefing;
      case PaywallReason.notifications:
        return PaywallSheet._kReasonNotifications;
      case PaywallReason.sync:
        return PaywallSheet._kReasonSync;
    }
  }

  Future<void> _onStartTrial() async {
    if (_busy) return;
    if (!UserService.instance.isSignedIn) {
      final didSignIn = await AuthSheet.show(context);
      if (!mounted) return;
      if (!didSignIn) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final offerings = await EntitlementService.instance.getOfferings();
      final current = offerings?.current;
      final pkg = _selectPackage(current);
      if (pkg == null) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text(PaywallSheet._kSnackOfferingsMissing)),
        );
        return;
      }
      await EntitlementService.instance.purchasePackage(pkg);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text(PaywallSheet._kSnackWelcome)),
      );
    } on UserCancelledPurchaseException {
      if (!mounted) return;
      navigator.pop();
    } on EntitlementException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRestore() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await EntitlementService.instance.restorePurchases();
      if (!mounted) return;
      final hasPro = info.entitlements.active.containsKey('pro');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            hasPro
                ? PaywallSheet._kSnackRestoreSuccess
                : PaywallSheet._kSnackRestoreNothing,
          ),
        ),
      );
      if (hasPro && mounted) Navigator.of(context).pop();
    } on EntitlementException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Package? _selectPackage(Offering? offering) {
    if (offering == null) return null;
    final wanted = _plan == _PlanChoice.annual
        ? PackageType.annual
        : PackageType.monthly;
    for (final p in offering.availablePackages) {
      if (p.packageType == wanted) return p;
    }
    return offering.availablePackages.isNotEmpty
        ? offering.availablePackages.first
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? kSurface : kLightSurface;
    final textPrimary = isDark ? kTextPrimary : kLightTextPrimary;
    final textSecondary = isDark ? kTextSecondary : kLightTextSecondary;
    final textMuted = isDark ? kTextMuted : kLightTextMuted;
    final border = isDark ? kBorder : kLightBorder;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: border),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/icon.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PaywallSheet._kTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      PaywallSheet._kSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kRed.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kRed.withValues(alpha: 0.4)),
            ),
            child: Text(
              _reasonTagline,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _bullet('\u{1F514}', PaywallSheet._kBulletNotifications, textPrimary),
          const SizedBox(height: 10),
          _bullet('\u{1F916}', PaywallSheet._kBulletBriefing, textPrimary),
          const SizedBox(height: 10),
          _bullet('\u{2601}\u{FE0F}', PaywallSheet._kBulletSync, textPrimary),
          const SizedBox(height: 10),
          _bullet('\u{1F4E1}', PaywallSheet._kBulletCustomRss, textPrimary),
          const SizedBox(height: 10),
          _bullet('\u{267E}\u{FE0F}', PaywallSheet._kBulletHistory, textPrimary),
          const SizedBox(height: 20),
          _planSelector(
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            border: border,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _onStartTrial,
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(PaywallSheet._kCtaStartTrial),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : _onRestore,
            child: Text(
              PaywallSheet._kCtaRestore,
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String emoji, String text, Color textColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _planSelector({
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required bool isDark,
  }) {
    return Row(
      children: [
        Expanded(
          child: _planTile(
            choice: _PlanChoice.monthly,
            label: PaywallSheet._kPlanMonthlyLabel,
            price: PaywallSheet._kPriceMonthly,
            badge: null,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            border: border,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _planTile(
            choice: _PlanChoice.annual,
            label: PaywallSheet._kPlanAnnualLabel,
            price: PaywallSheet._kPriceAnnual,
            badge: PaywallSheet._kSavingsBadge,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            border: border,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _planTile({
    required _PlanChoice choice,
    required String label,
    required String price,
    required String? badge,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required bool isDark,
  }) {
    final selected = _plan == choice;
    return Material(
      color: selected
          ? kRed.withValues(alpha: isDark ? 0.18 : 0.10)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? kRed : border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _plan = choice),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kRed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                price,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
