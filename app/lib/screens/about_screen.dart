import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/alert_rule_service.dart';
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
                  Text(
                    'v1.0.0',
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
    setState(() => _proCheck = EntitlementService.instance.isPro());
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
        20 + MediaQuery.of(context).viewInsets.bottom,
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
