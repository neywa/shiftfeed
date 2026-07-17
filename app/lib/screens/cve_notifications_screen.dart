/// Per-severity CVE notification switches.
///
/// Replaces the single inline "CVE alerts" switch that subscribed to one
/// `security` topic carrying every CVE regardless of severity. Each switch
/// here maps to one per-severity topic (`cve_critical` … `cve_low`) that the
/// scraper routes to — see `scraper/sources/cve_severity.py`.
///
/// The rows are driven off [CveSeverity] rather than a local list, so the
/// labels, order and colours are the same ones the CVE screen filters by. A
/// user who filters that screen to HIGH and enables the HIGH switch here
/// gets the same set of CVEs; that equivalence is the whole point, and it is
/// pinned on the scraper side by `test_cve_severity.py`.
library;

import 'package:flutter/material.dart';

import '../models/cve_severity.dart';
import '../services/entitlement_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/paywall_sheet.dart';

class CveNotificationsScreen extends StatefulWidget {
  const CveNotificationsScreen({super.key});

  @override
  State<CveNotificationsScreen> createState() => _CveNotificationsScreenState();
}

class _CveNotificationsScreenState extends State<CveNotificationsScreen> {
  final Map<String, bool> _enabled = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final topic in kCveTopics) {
      _enabled[topic] = await NotificationService.getTopicEnabled(topic);
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  /// Same mechanism as the Notifications section's `_onToggle`: re-check the
  /// entitlement on every flip rather than trusting a cached value, revert
  /// the switch and show the paywall when it fails. A non-Pro user can read
  /// this screen but no flip sticks.
  Future<void> _onToggle(String topic, bool desired) async {
    final isPro = await EntitlementService.instance.isPro();
    if (!mounted) return;
    if (!isPro) {
      setState(() => _enabled[topic] = !desired);
      PaywallSheet.show(context, reason: PaywallReason.notifications);
      return;
    }
    setState(() => _enabled[topic] = desired);
    await NotificationService.setTopicEnabled(
      topic,
      enabled: desired,
      isPro: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CVE notifications')),
      body: !_loaded
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Get pushed only the severities you care about. Every '
                    'level is off until you turn it on.',
                    style: TextStyle(
                      fontSize: 13,
                      color: textMutedOf(context),
                    ),
                  ),
                ),
                for (final severity in CveSeverity.values)
                  SwitchListTile(
                    secondary: _SeverityDot(color: severity.color),
                    title: Text(severity.label),
                    subtitle: Text(_subtitleFor(severity)),
                    value: _enabled[cveTopicFor(severity)] ?? false,
                    onChanged: (v) => _onToggle(cveTopicFor(severity), v),
                  ),
              ],
            ),
    );
  }

  /// Names the raw vocabularies that land in each bucket, because the
  /// notification itself says the source's own word — a Red Hat CVE arrives
  /// titled IMPORTANT, not HIGH, and this is where that stops being a
  /// surprise.
  String _subtitleFor(CveSeverity severity) => switch (severity) {
        CveSeverity.critical => 'Critical advisories',
        CveSeverity.high => 'Red Hat “Important” and NVD “High”',
        CveSeverity.medium => 'Red Hat “Moderate” and NVD “Medium”',
        CveSeverity.low => 'Low-severity advisories',
      };
}

class _SeverityDot extends StatelessWidget {
  final Color color;
  const _SeverityDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
