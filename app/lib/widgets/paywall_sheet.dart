/// Modal bottom sheet that pitches the Pro entitlement, lets the user pick
/// monthly vs annual, and drives [EntitlementService.purchasePackage].
///
/// Surface: bottom sheet with [showModalBottomSheet], rounded top corners,
/// safe-area aware. The visual style adapts to light/dark via
/// [Theme.of(context)] — no hard-coded ShiftFeed colours other than the
/// brand red used as the accent.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static const String _kCtaStartTrial = 'Start Free Trial';
  static const String _kCtaSubscribe = 'Subscribe';
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

  // ---- Renewal disclosure (store subscription policy) ----

  static const String _kPrivacyLabel = 'Privacy Policy';
  static const String _kPrivacyUrl =
      'https://neywa.github.io/app-privacy-policies/shiftfeed/';

  /// Shows the paywall as a modal bottom sheet. No-op on web — the SDK
  /// short-circuits Pro to false there and the magic-link auth flow is
  /// not currently functional on web, so the paywall has nothing to
  /// offer.
  static Future<void> show(
    BuildContext context, {
    required PaywallReason reason,
  }) {
    if (kIsWeb) return Future<void>.value();
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

/// Per-package free-trial descriptor derived from the live store product.
/// [label] is display-ready, e.g. "14-day", "2-week".
class _TrialInfo {
  final String label;
  final bool isFree;
  const _TrialInfo(this.label, this.isFree);
}

/// Display-ready pricing for one plan, assembled from the RevenueCat
/// [StoreProduct]. [fromSdk] is false while offerings are still loading — in
/// that placeholder state a trial is never reported.
class _PlanPricing {
  final String priceString;
  final String periodLabel;
  final _TrialInfo? trial;
  final bool fromSdk;
  const _PlanPricing({
    required this.priceString,
    required this.periodLabel,
    required this.trial,
    required this.fromSdk,
  });
}

/// Singular noun for a billing-period unit.
String _unitSingular(PeriodUnit unit) {
  switch (unit) {
    case PeriodUnit.day:
      return 'day';
    case PeriodUnit.week:
      return 'week';
    case PeriodUnit.month:
      return 'month';
    case PeriodUnit.year:
      return 'year';
    case PeriodUnit.unknown:
      return 'period';
  }
}

/// Formats a trial duration as `n-unit` (e.g. "14-day", "2-week").
String _trialLabel(PeriodUnit unit, int value) =>
    '$value-${_unitSingular(unit)}';

/// Noun form of a recurring billing period for display after "/": singular
/// for a single unit ("month"), pluralised otherwise ("3 months").
String _periodNoun(PeriodUnit unit, int value) {
  final singular = _unitSingular(unit);
  return value == 1 ? singular : '$value ${singular}s';
}

/// Parses an ISO-8601 subscription period ("P14D", "P2W", "P1M", "P1Y")
/// into a (unit, value) pair, or null if unrecognised. Used for the
/// String-only SDK fields (StoreProduct.subscriptionPeriod,
/// IntroductoryPrice.period).
(PeriodUnit, int)? _parseIsoPeriod(String iso) {
  final match = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
  if (match == null) return null;
  final value = int.tryParse(match.group(1)!);
  if (value == null) return null;
  switch (match.group(2)) {
    case 'D':
      return (PeriodUnit.day, value);
    case 'W':
      return (PeriodUnit.week, value);
    case 'M':
      return (PeriodUnit.month, value);
    case 'Y':
      return (PeriodUnit.year, value);
  }
  return null;
}

class _PaywallSheetState extends State<PaywallSheet> {
  _PlanChoice _plan = _PlanChoice.annual;
  bool _busy = false;
  Offering? _offering;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await EntitlementService.instance.getOfferings();
    if (!mounted) return;
    setState(() => _offering = offerings?.current);
  }

  Package? _packageFor(_PlanChoice choice) {
    final offering = _offering;
    if (offering == null) return null;
    final wanted = choice == _PlanChoice.annual
        ? PackageType.annual
        : PackageType.monthly;
    for (final p in offering.availablePackages) {
      if (p.packageType == wanted) return p;
    }
    return null;
  }

  /// Assembles display-ready pricing for [choice] from the live store
  /// product. While offerings are still loading (or RevenueCat failed) the
  /// result is a placeholder — [_PlanPricing.fromSdk] is false and no trial
  /// is ever reported.
  _PlanPricing _pricingFor(_PlanChoice choice) {
    final pkg = _packageFor(choice);
    if (pkg == null) {
      return _PlanPricing(
        priceString: choice == _PlanChoice.annual
            ? PaywallSheet._kPriceAnnual
            : PaywallSheet._kPriceMonthly,
        periodLabel: '',
        trial: null,
        fromSdk: false,
      );
    }
    final sp = pkg.storeProduct;
    return _PlanPricing(
      priceString: sp.priceString,
      periodLabel: _recurringPeriodLabel(sp, choice),
      trial: _detectTrial(sp),
      fromSdk: true,
    );
  }

  /// Store-localised "price / period" for [choice]. Falls back to the
  /// hardcoded USD placeholder (which already carries its own "/ unit"
  /// suffix) while offerings load.
  String _priceFor(_PlanChoice choice) {
    final p = _pricingFor(choice);
    if (!p.fromSdk) return p.priceString;
    return '${p.priceString} / ${p.periodLabel}';
  }

  /// First subscription option for [sp] (Android), or null on iOS / when the
  /// product exposes none. Prefers the SDK's [StoreProduct.defaultOption].
  SubscriptionOption? _primaryOption(StoreProduct sp) {
    final options = sp.subscriptionOptions;
    return sp.defaultOption ??
        (options != null && options.isNotEmpty ? options.first : null);
  }

  /// Returns the free-trial descriptor for [sp], or null when the product has
  /// no trial. Reads Android base-plan pricing phases first, then falls back
  /// to the iOS [StoreProduct.introductoryPrice].
  _TrialInfo? _detectTrial(StoreProduct sp) {
    final option = _primaryOption(sp);
    if (option != null) {
      PricingPhase? freePhase = option.freePhase;
      if (freePhase == null) {
        for (final phase in option.pricingPhases) {
          if (phase.offerPaymentMode == OfferPaymentMode.freeTrial ||
              phase.price.amountMicros == 0) {
            freePhase = phase;
            break;
          }
        }
      }
      final period = freePhase?.billingPeriod;
      if (period != null) {
        return _TrialInfo(_trialLabel(period.unit, period.value), true);
      }
    }
    final intro = sp.introductoryPrice;
    if (intro != null && intro.price == 0) {
      return _TrialInfo(
        _trialLabel(intro.periodUnit, intro.periodNumberOfUnits),
        true,
      );
    }
    return null;
  }

  /// Human-readable recurring billing period ("month", "year", "3 months")
  /// derived from the SDK — only falls back to the plan suffix when every SDK
  /// source is missing.
  String _recurringPeriodLabel(StoreProduct sp, _PlanChoice choice) {
    final option = _primaryOption(sp);
    if (option != null) {
      Period? period = option.fullPricePhase?.billingPeriod;
      if (period == null) {
        for (final phase in option.pricingPhases) {
          if (phase.price.amountMicros > 0 && phase.billingPeriod != null) {
            period = phase.billingPeriod;
          }
        }
      }
      if (period != null) return _periodNoun(period.unit, period.value);
    }
    final iso = sp.subscriptionPeriod;
    if (iso != null) {
      final parsed = _parseIsoPeriod(iso);
      if (parsed != null) return _periodNoun(parsed.$1, parsed.$2);
    }
    return choice == _PlanChoice.annual ? 'year' : 'month';
  }

  Future<void> _openPrivacy() async {
    await launchUrl(
      Uri.parse(PaywallSheet._kPrivacyUrl),
      mode: LaunchMode.externalApplication,
    );
  }

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
      final current = _offering ??
          (await EntitlementService.instance.getOfferings())?.current;
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
    // Pro requires a signed-in session (see EntitlementService.isPro), so a
    // restore on an anonymous session would report success yet leave every
    // gated feature locked. Force sign-in first — mirrors _onStartTrial — so
    // the restored entitlement is aliased to the Supabase user via linkUser.
    if (!UserService.instance.isSignedIn) {
      final didSignIn = await AuthSheet.show(context);
      if (!mounted) return;
      if (!didSignIn) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await EntitlementService.instance.restorePurchases();
      if (!mounted) return;
      final hasPro =
          info.entitlements.active.containsKey(kProEntitlementId);
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

    // Drives the trial subtitle, CTA label and renewal disclosure entirely
    // from the selected plan's live store data. Recomputed every build, so
    // switching Monthly/Annual tiles updates all three.
    final selected = _pricingFor(_plan);

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
                    if (selected.trial != null)
                      Text(
                        '${selected.trial!.label} free trial',
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
          if (selected.fromSdk) ...[
            _disclosure(selected, textSecondary, textMuted),
            const SizedBox(height: 14),
          ],
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
                  : Text(selected.trial != null
                      ? PaywallSheet._kCtaStartTrial
                      : PaywallSheet._kCtaSubscribe),
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

  /// Store name for the renewal disclosure, named per platform so the copy is
  /// store-policy compliant. Returns a form that slots after "in ...".
  String get _storeName {
    if (kIsWeb) return 'your account settings'; // sheet never renders on web
    if (Platform.isIOS) return 'the App Store';
    if (Platform.isAndroid) return 'Google Play';
    return 'your account settings'; // neutral fallback — never name a wrong store
  }

  /// Auto-renewal small print, with the store name resolved per platform.
  String get _smallPrint =>
      'Subscription auto-renews unless cancelled at least 24 hours before '
      'the end of the current period. Manage or cancel in $_storeName.';

  /// Store-compliant renewal disclosure for the selected plan, built from live
  /// store data. Only rendered once offerings have loaded
  /// ([_PlanPricing.fromSdk]).
  Widget _disclosure(
    _PlanPricing pricing,
    Color textSecondary,
    Color textMuted,
  ) {
    final trial = pricing.trial;
    final renewal = trial != null
        ? '${trial.label} free trial, then '
            '${pricing.priceString}/${pricing.periodLabel}. Auto-renews. '
            'Cancel anytime in $_storeName before the trial ends.'
        : '${pricing.priceString}/${pricing.periodLabel}. Auto-renews. '
            'Cancel anytime in $_storeName.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          renewal,
          style: TextStyle(color: textSecondary, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(
          _smallPrint,
          style: TextStyle(color: textMuted, fontSize: 10, height: 1.4),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _openPrivacy,
          child: Text(
            PaywallSheet._kPrivacyLabel,
            style: const TextStyle(
              color: kRed,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
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
            price: _priceFor(_PlanChoice.monthly),
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
            price: _priceFor(_PlanChoice.annual),
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
              Text(
                label,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
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
