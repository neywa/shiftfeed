import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/alert_rule_service.dart';
import '../services/custom_rss_service.dart';
import '../services/digest_pref_service.dart';
import '../services/entitlement_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/paywall_sheet.dart';
import 'submit_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _sources = <_SourceItem>[
    _SourceItem('Red Hat Blog', Icons.rss_feed),
    _SourceItem('Red Hat Developer', Icons.rss_feed),
    _SourceItem('Kubernetes Blog', Icons.rss_feed),
    _SourceItem('CNCF Blog', Icons.rss_feed),
    _SourceItem('Istio Blog', Icons.rss_feed),
    _SourceItem('Hacker News (openshift, kubernetes)', Icons.rss_feed),
    _SourceItem('HackerNoon (kubernetes, devops)', Icons.rss_feed),
    _SourceItem(
      'GitHub Releases — operator-sdk, ROSA, Argo CD, Tekton, Istio, Quay',
      Icons.rocket_launch,
    ),
    _SourceItem(
      'Red Hat Security Data API — OpenShift, Kubernetes, Podman, Quay, Istio, Service Mesh',
      Icons.shield,
    ),
    _SourceItem(
      'OpenShift stable channels (cincinnati-graph-data)',
      Icons.layers,
    ),
  ];

  static const _dataItems = <_DataItem>[
    _DataItem(Icons.schedule, 'Updated every hour automatically'),
    _DataItem(Icons.storage, 'Powered by Supabase'),
    _DataItem(Icons.code, 'Built with Flutter'),
  ];

  static const _links = <_LinkItem>[
    _LinkItem(
      'Privacy Policy',
      'https://neywa.github.io/app-privacy-policies/shiftfeed/',
      Icons.privacy_tip_outlined,
    ),
    _LinkItem('OpenShift Documentation', 'https://docs.openshift.com'),
    _LinkItem('Red Hat Blog', 'https://www.redhat.com/en/blog'),
    _LinkItem('Source Code', 'https://github.com/neywa/ona'),
  ];

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final border = BorderSide(color: theme.dividerColor);
    final cardShape = RoundedRectangleBorder(
      side: border,
      borderRadius: BorderRadius.circular(14),
    );

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: onSurface.withValues(alpha: 0.7),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: cardShape,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ShiftFeed',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _AppVersionText(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'OpenShift Community Intelligence',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          sectionTitle('Account'),
          Card(
            elevation: 0,
            shape: cardShape,
            clipBehavior: Clip.antiAlias,
            child: const _AccountSection(),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: cardShape,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.add_link_outlined),
              title: const Text('Submit a Link'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubmitScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!kIsWeb) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  Text(
                    'Notifications',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _ProBadge(),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: cardShape,
              clipBehavior: Clip.antiAlias,
              child: const _NotificationsSection(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  Text(
                    'Alert Rules',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _ProBadge(),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: cardShape,
              clipBehavior: Clip.antiAlias,
              child: const _AlertRulesSection(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  Text(
                    'Daily Briefing',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _ProBadge(),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: cardShape,
              clipBehavior: Clip.antiAlias,
              child: const _DigestScheduleSection(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  Text(
                    'Custom Feeds',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _ProBadge(),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: cardShape,
              clipBehavior: Clip.antiAlias,
              child: const _CustomFeedsSection(),
            ),
            const SizedBox(height: 16),
          ],
          sectionTitle('Sources'),
          Card(
            elevation: 0,
            shape: cardShape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final item in _sources)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          sectionTitle('Data'),
          Card(
            elevation: 0,
            shape: cardShape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final item in _dataItems)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          sectionTitle('Links'),
          Card(
            elevation: 0,
            shape: cardShape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final link in _links)
                  ListTile(
                    leading: Icon(link.icon ?? Icons.open_in_browser),
                    title: Text(link.label),
                    onTap: () => _open(link.url),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _RevenueCatIdSection(),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Made with ♥ by Neywa',
              style: theme.textTheme.bodySmall?.copyWith(
                color: onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Renders the app version label on the About card. Reads
/// `package_info_plus` at runtime so the value tracks `pubspec.yaml`
/// instead of being hand-edited per release.
class _AppVersionText extends StatelessWidget {
  final TextStyle? style;
  const _AppVersionText({this.style});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        // Plugin not registered (e.g. hot reload after adding the
        // dependency, before a full rebuild), or any other failure —
        // collapse the line rather than showing a stuck placeholder.
        if (snapshot.hasError) {
          debugPrint('[About] PackageInfo.fromPlatform failed: '
              '${snapshot.error}');
          return const SizedBox.shrink();
        }
        final raw = snapshot.data?.version;
        if (raw == null) {
          // Still loading. Reserve a line of vertical space so the
          // layout doesn't jump when the version arrives.
          return Text(' ', style: style);
        }
        // package_info_plus already separates `version` (semver) from
        // `buildNumber`, but defensively split on '+' in case a future
        // platform returns a combined string.
        return Text('v${raw.split('+').first}', style: style);
      },
    );
  }
}

/// Bottom-of-Settings affordance that exposes the device's RevenueCat
/// App User ID with a one-tap copy. Used to grant promotional
/// entitlements from the RC dashboard for testers without a paid
/// subscription. Hidden when the SDK can't return an ID (web).
class _RevenueCatIdSection extends StatefulWidget {
  const _RevenueCatIdSection();

  @override
  State<_RevenueCatIdSection> createState() => _RevenueCatIdSectionState();
}

class _RevenueCatIdSectionState extends State<_RevenueCatIdSection> {
  late final Future<String?> _idFuture =
      EntitlementService.instance.currentAppUserId();

  Future<void> _copy(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('RevenueCat ID copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return FutureBuilder<String?>(
      future: _idFuture,
      builder: (context, snapshot) {
        final id = snapshot.data;
        if (id == null) return const SizedBox.shrink();
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy RevenueCat ID'),
                onPressed: () => _copy(id),
              ),
              const SizedBox(height: 8),
              SelectableText(
                id,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onSurface.withValues(alpha: 0.5),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SourceItem {
  final String label;
  final IconData icon;
  const _SourceItem(this.label, this.icon);
}

class _DataItem {
  final IconData icon;
  final String label;
  const _DataItem(this.icon, this.label);
}

class _LinkItem {
  final String label;
  final String url;
  final IconData? icon;
  const _LinkItem(this.label, this.url, [this.icon]);
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your Pro features will stop working on this device until you '
          'sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await UserService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: UserService.instance.authStateChanges,
      builder: (context, _) {
        final user = UserService.instance.currentUser;
        final signedIn = user != null;
        if (signedIn) {
          return ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Signed in'),
            subtitle: Text(user.email ?? ''),
            trailing: TextButton(
              onPressed: () => _confirmSignOut(context),
              child: const Text('Sign out'),
            ),
          );
        }
        return ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: const Text('No account'),
          subtitle: const Text(
            'Sign in to sync bookmarks and manage your subscription',
          ),
          trailing: TextButton(
            onPressed: () => AuthSheet.show(context),
            child: const Text('Sign in'),
          ),
        );
      },
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEE0000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  static const _topics = <_TopicRow>[
    _TopicRow('all', 'Daily AI briefing', Icons.auto_awesome),
    _TopicRow('security', 'CVE alerts', Icons.shield_outlined),
    _TopicRow('releases', 'Release alerts', Icons.rocket_launch_outlined),
  ];

  final Map<String, bool> _enabled = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final t in _topics) {
      _enabled[t.topic] = await NotificationService.getTopicEnabled(t.topic);
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  Future<void> _onToggle(String topic, bool desired) async {
    final isPro = await EntitlementService.instance.isPro();
    if (!mounted) return;
    if (!isPro) {
      // Revert and show paywall — pref is unchanged.
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
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final t in _topics)
          SwitchListTile(
            secondary: Icon(t.icon),
            title: Text(t.label),
            value: _enabled[t.topic] ?? true,
            onChanged: (v) => _onToggle(t.topic, v),
          ),
      ],
    );
  }
}

class _TopicRow {
  final String topic;
  final String label;
  final IconData icon;
  const _TopicRow(this.topic, this.label, this.icon);
}

class _AlertRulesSection extends StatefulWidget {
  const _AlertRulesSection();

  @override
  State<_AlertRulesSection> createState() => _AlertRulesSectionState();
}

class _AlertRulesSectionState extends State<_AlertRulesSection> {
  Future<bool>? _proCheck;

  @override
  void initState() {
    super.initState();
    _proCheck = EntitlementService.instance.isPro();
  }

  void _refreshProCheck() {
    setState(() {
      _proCheck = EntitlementService.instance.isPro();
    });
  }

  Future<void> _showPaywall() async {
    await PaywallSheet.show(context, reason: PaywallReason.notifications);
    if (!mounted) return;
    _refreshProCheck();
  }

  Future<void> _editRule({AlertRule? existing}) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AlertRuleEditSheet(
        existing: existing,
        messenger: messenger,
      ),
    );
  }

  Future<void> _confirmDelete(AlertRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete rule '${rule.name}'?"),
        content: const Text(
          'This rule will stop matching new articles immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && rule.id != null) {
      await AlertRuleService.instance.deleteRule(rule.id!);
    }
  }

  String _ruleSubtitle(AlertRule rule) {
    final parts = <String>[];
    if (rule.categories.isEmpty) {
      parts.add('All categories');
    } else {
      parts.add(
        rule.categories
            .map((c) => c[0].toUpperCase() + c.substring(1))
            .join(' / '),
      );
    }
    if (rule.cvssMinimum != null) {
      parts.add('CVSS ≥ ${rule.cvssMinimum!.toStringAsFixed(1)}');
    }
    if (rule.keywords.isNotEmpty) {
      parts.add('keywords: ${rule.keywords.join(", ")}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _proCheck,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final isPro = snap.data == true;
        if (!isPro) {
          return InkWell(
            onTap: _showPaywall,
            child: const ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text('Custom alert rules'),
              subtitle: Text(
                'Get notified only about what matters to you. '
                'Upgrade to Pro to unlock.',
              ),
              trailing: Icon(Icons.chevron_right),
            ),
          );
        }
        return StreamBuilder<List<AlertRule>>(
          stream: AlertRuleService.instance.watchRules(),
          initialData: const [],
          builder: (context, ruleSnap) {
            final rules = ruleSnap.data ?? const <AlertRule>[];
            return Column(
              children: [
                if (rules.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No rules yet — add one to start receiving '
                        'targeted alerts.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                else
                  for (final rule in rules)
                    ListTile(
                      leading: Switch(
                        value: rule.enabled,
                        onChanged: rule.id == null
                            ? null
                            : (v) => AlertRuleService.instance
                                .toggleRule(rule.id!, v),
                      ),
                      title: Text(rule.name),
                      subtitle: Text(_ruleSubtitle(rule)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(rule),
                      ),
                      onTap: () => _editRule(existing: rule),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add rule'),
                      onPressed: () => _editRule(),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AlertRuleEditSheet extends StatefulWidget {
  final AlertRule? existing;
  final ScaffoldMessengerState messenger;

  const _AlertRuleEditSheet({
    required this.existing,
    required this.messenger,
  });

  @override
  State<_AlertRuleEditSheet> createState() => _AlertRuleEditSheetState();
}

class _AlertRuleEditSheetState extends State<_AlertRuleEditSheet> {
  static const _kCategoryLabels = {
    'security': 'Security',
    'releases': 'Releases',
    'ocp': 'OCP',
  };

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _keywordsCtrl;
  late Set<String> _categories;
  bool _useCvss = false;
  double _cvss = 7.0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _keywordsCtrl = TextEditingController(text: (r?.keywords ?? const []).join(', '));
    _categories = {...?r?.categories};
    _useCvss = r?.cvssMinimum != null;
    _cvss = r?.cvssMinimum ?? 7.0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keywordsCtrl.dispose();
    super.dispose();
  }

  bool get _showCvss =>
      _categories.isEmpty || _categories.contains('security');

  List<String> _parseKeywords(String raw) => raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final rule = AlertRule(
        id: widget.existing?.id,
        name: _nameCtrl.text.trim(),
        enabled: widget.existing?.enabled ?? true,
        categories: _categories.toList()..sort(),
        cvssMinimum: _useCvss ? _cvss : null,
        keywords: _parseKeywords(_keywordsCtrl.text),
      );
      if (rule.id == null) {
        await AlertRuleService.instance.createRule(rule);
      } else {
        await AlertRuleService.instance.updateRule(rule);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        SnackBar(content: Text('Could not save rule: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
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
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.existing == null ? 'New rule' : 'Edit rule',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Rule name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Rule name is required.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Categories'),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _categories.isEmpty,
                    onSelected: (sel) {
                      setState(() {
                        _categories.clear();
                      });
                    },
                  ),
                  for (final entry in _kCategoryLabels.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _categories.contains(entry.key),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _categories.add(entry.key);
                          } else {
                            _categories.remove(entry.key);
                          }
                        });
                      },
                    ),
                ],
              ),
              if (_showCvss) ...[
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Only notify above CVSS threshold'),
                  value: _useCvss,
                  onChanged: (v) => setState(() => _useCvss = v ?? false),
                ),
                Slider(
                  value: _cvss,
                  min: 0.0,
                  max: 10.0,
                  divisions: 20,
                  label: _cvss.toStringAsFixed(1),
                  onChanged: _useCvss
                      ? (v) => setState(() => _cvss = v)
                      : null,
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _keywordsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Keywords (optional)',
                  hintText: 'kubernetes, etcd, cni',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: kRed),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigestScheduleSection extends StatefulWidget {
  const _DigestScheduleSection();

  @override
  State<_DigestScheduleSection> createState() => _DigestScheduleSectionState();
}

class _DigestScheduleSectionState extends State<_DigestScheduleSection> {
  Future<bool>? _proCheck;
  Future<DigestPrefs>? _prefsFuture;

  @override
  void initState() {
    super.initState();
    _proCheck = EntitlementService.instance.isPro();
    _prefsFuture = DigestPrefService.instance.getPrefs();
  }

  void _refreshPrefs() {
    setState(() {
      _prefsFuture = DigestPrefService.instance.getPrefs();
    });
  }

  Future<void> _showPaywall() async {
    await PaywallSheet.show(context, reason: PaywallReason.briefing);
    if (!mounted) return;
    setState(() {
      _proCheck = EntitlementService.instance.isPro();
    });
  }

  Future<void> _openSheet(DigestPrefs prefs) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DigestScheduleSheet(
        existing: prefs,
        messenger: messenger,
      ),
    );
    if (!mounted) return;
    _refreshPrefs();
  }

  String _formatHour(int h) {
    final period = h < 12 ? 'AM' : 'PM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:00 $period';
  }

  String _categoriesLabel(List<String> cats) {
    if (cats.isEmpty) return 'All categories';
    return cats.map((c) => c[0].toUpperCase() + c.substring(1)).join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _proCheck,
      builder: (context, proSnap) {
        if (!proSnap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final isPro = proSnap.data == true;
        if (!isPro) {
          return InkWell(
            onTap: _showPaywall,
            child: const ListTile(
              leading: Icon(Icons.schedule_outlined),
              title: Text('Schedule daily briefing'),
              subtitle: Text(
                'Get the AI briefing in your inbox at the time you choose. '
                'Upgrade to Pro to unlock.',
              ),
              trailing: Icon(Icons.chevron_right),
            ),
          );
        }
        return FutureBuilder<DigestPrefs>(
          future: _prefsFuture,
          builder: (context, prefsSnap) {
            if (!prefsSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final prefs = prefsSnap.data!;
            final title = prefs.enabled
                ? 'Delivered daily at ${_formatHour(prefs.deliveryHour)}'
                : 'On-demand only — tap to set a schedule';
            final subtitle = prefs.enabled
                ? '${prefs.timezone} · ${_categoriesLabel(prefs.categories)}'
                : null;
            return ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openSheet(prefs),
            );
          },
        );
      },
    );
  }
}

class _DigestScheduleSheet extends StatefulWidget {
  final DigestPrefs existing;
  final ScaffoldMessengerState messenger;

  const _DigestScheduleSheet({
    required this.existing,
    required this.messenger,
  });

  @override
  State<_DigestScheduleSheet> createState() => _DigestScheduleSheetState();
}

class _DigestScheduleSheetState extends State<_DigestScheduleSheet> {
  static const _kCategoryLabels = {
    'security': 'Security',
    'releases': 'Releases',
    'ocp': 'OCP',
  };

  late bool _enabled;
  late int _deliveryHour;
  late String _timezone;
  late Set<String> _categories;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.existing.enabled;
    _deliveryHour = widget.existing.deliveryHour;
    _timezone = widget.existing.timezone;
    _categories = {...widget.existing.categories};
    // First-time setup: pre-fill device IANA timezone if user has no row yet
    if (widget.existing.id == null && _timezone == 'UTC') {
      DigestPrefService.deviceTimezone().then((tz) {
        if (!mounted) return;
        setState(() => _timezone = tz);
      });
    }
  }

  String _formatHour(int h) {
    final period = h < 12 ? 'AM' : 'PM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:00 $period';
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _deliveryHour, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _deliveryHour = picked.hour);
    }
  }

  Future<void> _editTimezone() async {
    final controller = TextEditingController(text: _timezone);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Timezone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Europe/Prague',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'e.g. Europe/Prague, America/New_York, Asia/Tokyo',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _timezone = result);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs = widget.existing.copyWith(
        enabled: _enabled,
        deliveryHour: _deliveryHour,
        timezone: _timezone,
        categories: _categories.toList()..sort(),
      );
      await DigestPrefService.instance.savePrefs(prefs);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        SnackBar(content: Text('Could not save schedule: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = !_enabled;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
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
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Daily briefing schedule',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Schedule daily delivery'),
              subtitle: const Text(
                'When off, you can still open the briefing on-demand.',
              ),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 4),
            Opacity(
              opacity: disabled ? 0.5 : 1.0,
              child: IgnorePointer(
                ignoring: disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time),
                      title: const Text('Delivery time'),
                      subtitle: Text(_formatHour(_deliveryHour)),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _pickTime,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.public),
                      title: const Text('Timezone'),
                      subtitle: Text(_timezone),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _editTimezone,
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Categories'),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('All'),
                          selected: _categories.isEmpty,
                          onSelected: (_) {
                            setState(() => _categories.clear());
                          },
                        ),
                        for (final entry in _kCategoryLabels.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected: _categories.contains(entry.key),
                            onSelected: (sel) {
                              setState(() {
                                if (sel) {
                                  _categories.add(entry.key);
                                } else {
                                  _categories.remove(entry.key);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: kRed),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomFeedsSection extends StatefulWidget {
  const _CustomFeedsSection();

  @override
  State<_CustomFeedsSection> createState() => _CustomFeedsSectionState();
}

class _CustomFeedsSectionState extends State<_CustomFeedsSection> {
  Future<bool>? _proCheck;

  @override
  void initState() {
    super.initState();
    _proCheck = EntitlementService.instance.isPro();
  }

  Future<void> _showPaywall() async {
    await PaywallSheet.show(context, reason: PaywallReason.briefing);
    if (!mounted) return;
    setState(() {
      _proCheck = EntitlementService.instance.isPro();
    });
  }

  Future<void> _confirmDelete(CustomRssSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove '${source.label}'?"),
        content: const Text(
          'This feed will stop being fetched and existing articles from '
          'it will fade out as new ones replace them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && source.id != null) {
      try {
        await CustomRssService.instance.deleteSource(source.id!);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove feed: $e')),
        );
      }
    }
  }

  Future<void> _openAddSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddRssSourceSheet(messenger: messenger),
    );
  }

  String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _proCheck,
      builder: (context, proSnap) {
        if (!proSnap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final isPro = proSnap.data == true;
        if (!isPro) {
          return InkWell(
            onTap: _showPaywall,
            child: const ListTile(
              leading: Icon(Icons.rss_feed_outlined),
              title: Text('Custom RSS feeds'),
              subtitle: Text(
                'Add your own RSS feeds and see them alongside the '
                'curated feed. Upgrade to Pro to unlock.',
              ),
              trailing: Icon(Icons.chevron_right),
            ),
          );
        }
        return StreamBuilder<List<CustomRssSource>>(
          stream: CustomRssService.instance.watchSources(),
          initialData: const [],
          builder: (context, snap) {
            final sources = snap.data ?? const <CustomRssSource>[];
            final atLimit = sources.length >= CustomRssSource.maxSources;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${sources.length}/${CustomRssSource.maxSources} feeds',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                if (sources.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No feeds yet — add one to start pulling articles '
                        'from any RSS source.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                else
                  for (final source in sources)
                    ListTile(
                      leading: Switch(
                        value: source.enabled,
                        onChanged: source.id == null
                            ? null
                            : (v) => CustomRssService.instance
                                .toggleSource(source.id!, v),
                      ),
                      title: Text(source.label),
                      subtitle: Text(
                        _truncate(source.url, 40),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (source.lastError != null)
                            Tooltip(
                              message: source.lastError!,
                              child: const Icon(
                                Icons.error_outline,
                                color: kRed,
                                size: 18,
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => _confirmDelete(source),
                          ),
                        ],
                      ),
                      onLongPress: () => _confirmDelete(source),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: atLimit
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                            child: Text(
                              '${CustomRssSource.maxSources}/'
                              '${CustomRssSource.maxSources} feeds added '
                              '(limit reached)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          )
                        : TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add feed'),
                            onPressed: _openAddSheet,
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AddRssSourceSheet extends StatefulWidget {
  final ScaffoldMessengerState messenger;

  const _AddRssSourceSheet({required this.messenger});

  @override
  State<_AddRssSourceSheet> createState() => _AddRssSourceSheetState();
}

class _AddRssSourceSheetState extends State<_AddRssSourceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String? _urlFieldError;
  bool _saving = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _urlFieldError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await CustomRssService.instance.addSource(
        url: _urlCtrl.text,
        label: _labelCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on RssSourceLimitException {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        const SnackBar(content: Text("You've reached the 10-feed limit")),
      );
    } on RssUrlInvalidException catch (e) {
      if (!mounted) return;
      setState(() => _urlFieldError = e.message);
    } catch (e) {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        SnackBar(content: Text('Could not add feed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
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
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Add custom feed',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _labelCtrl,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. Kubernetes Blog',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Label is required.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Feed URL',
                  hintText: 'https://example.com/feed.xml',
                  errorText: _urlFieldError,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'URL is required.';
                  if (!t.startsWith('http://') &&
                      !t.startsWith('https://')) {
                    return 'URL must start with http:// or https://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Paste any RSS or Atom feed URL. The feed will be checked '
                'hourly.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: kRed),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
