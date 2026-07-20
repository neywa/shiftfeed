import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/alert_rule_service.dart';
import '../services/custom_rss_service.dart';
import '../services/digest_pref_service.dart';
import '../services/entitlement_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../theme/text_metrics.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/brand_title.dart';
import '../widgets/main_app_bar.dart';
import '../widgets/paywall_sheet.dart';
import 'about_screen.dart';
import 'cve_notifications_screen.dart';
import 'submit_screen.dart';

// One spacing rule for the screen, in *visible* space: 16 above a section
// title, 8 from a title down to its card, and 8 between two cards that belong
// together (Account -> Submit a Link, Links -> About).
//
// Cards are real boxes, so a gap between two of them is what it says. A title
// is not: its line box carries a blank strip above the glyphs and another
// below the baseline, so the gaps around it have to subtract those strips or
// they read ~5dp too tall on top and ~8dp too tall underneath — which is
// exactly what a device screenshot showed. See theme/text_metrics.dart.
const double _kSectionGap = 16;
const double _kCardGap = 8;

// The section title. An explicit `height` is what makes the strips
// computable — see [inkTop].
const double _kTitleSize = 14;
const double _kTitleHeight = 1.0;

// The PRO badge stands ~15.7dp tall (a 9dp label in the font's natural line
// box, plus 2dp of padding either side), which overhangs the title's 14dp
// tightened box. So on a Pro section the badge — a real box, no strip — is the
// row's topmost and bottommost ink, and the gaps around it stand as written.

class SettingsScreen extends StatelessWidget {
  /// True when this screen is a bottom-nav tab: it then wears the shared
  /// [MainAppBar] (wordmark + the four actions). False on the desktop
  /// push-route, which keeps its own descriptive title and back arrow.
  final bool isTab;

  const SettingsScreen({super.key, this.isTab = false});

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

  // App-identity links (Privacy Policy, Web, Source Code) live on the About
  // screen; these are the reading links.
  static const _links = <_LinkItem>[
    _LinkItem('OpenShift Documentation', 'https://docs.openshift.com'),
    _LinkItem('Red Hat Blog', 'https://www.redhat.com/en/blog'),
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

    // The strips to subtract from the gaps around a title. On a Pro section the
    // badge overhangs the text's line box top and bottom, and it is a real box
    // — so there is nothing to subtract there and the gaps stand as written.
    final titleInkTop = inkTop(_kTitleSize, _kTitleHeight);
    final titleInkBottom = inkBottom(_kTitleSize, _kTitleHeight);

    // Each title owns the gap above it, so the strip can come off it. That is
    // also why the list has no top padding of its own.
    Widget sectionTitle(String text, {bool pro = false}) => Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        _kSectionGap - (pro ? 0 : titleInkTop),
        0,
        _kCardGap - (pro ? 0 : titleInkBottom),
      ),
      child: Row(
        children: [
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: _kTitleSize,
              fontWeight: FontWeight.bold,
              // A tight box: without an explicit height the strips are the
              // font's own leading — ~5dp above and ~8dp below at this size,
              // which would make the 8dp gap under a title impossible to hit.
              height: _kTitleHeight,
              leadingDistribution: TextLeadingDistribution.even,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (pro) ...[
            const SizedBox(width: 8),
            const ProBadge(),
          ],
        ],
      ),
    );

    // margin: zero — Card's default is 4dp on every side, which silently added
    // 8dp between two stacked cards and 4dp under every title. With it gone a
    // gap between two cards is exactly the number written, and cards line up
    // with the titles on the list's own 16dp inset.
    Widget card(Widget child) => Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    return Scaffold(
      // Nothing here responds to search or the card view mode, so both stay
      // greyed out.
      appBar: isTab
          ? const MainAppBar()
          : AppBar(title: const Text('Settings')),
      body: ListView(
        // No top padding: the first section title carries the 16dp itself, so
        // the strip above its glyphs can be subtracted from it.
        padding: const EdgeInsets.fromLTRB(16, 0, 16, _kSectionGap),
        children: [
          if (!kIsWeb) ...[
            sectionTitle('Account'),
            card(const _AccountSection()),
            const SizedBox(height: _kCardGap),
          ] else
            // On web the list opens on a card, which has no strip to trim.
            const SizedBox(height: _kSectionGap),
          card(
            ListTile(
              leading: const Icon(Icons.add_link_outlined),
              title: const Text('Submit a Link'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubmitScreen()),
              ),
            ),
          ),
          if (!kIsWeb) ...[
            sectionTitle('Notifications', pro: true),
            card(const _NotificationsSection()),
            sectionTitle('Alert Rules', pro: true),
            card(const _AlertRulesSection()),
            sectionTitle('Daily Briefing', pro: true),
            card(const _DigestScheduleSection()),
            sectionTitle('Custom Feeds', pro: true),
            card(const _CustomFeedsSection()),
          ],
          sectionTitle('Sources'),
          card(
            Column(
              children: [
                for (final item in _sources)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                  ),
              ],
            ),
          ),
          sectionTitle('Links'),
          card(
            Column(
              children: [
                for (final link in _links)
                  ListTile(
                    leading: const Icon(Icons.open_in_browser),
                    title: Text(link.label),
                    onTap: () => _open(link.url),
                  ),
              ],
            ),
          ),
          const SizedBox(height: _kCardGap),
          card(
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
          ),
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

class _LinkItem {
  final String label;
  final String url;
  const _LinkItem(this.label, this.url);
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

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  // CVE alerts used to be a switch here on the single `security` topic,
  // which carried every CVE at every severity. It now lives on its own
  // screen with one switch per severity — see CveNotificationsScreen and
  // the "CVE notifications" tile below this section.
  static const _topics = <_TopicRow>[
    _TopicRow('all', 'Daily AI briefing', Icons.auto_awesome),
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
        // Not a switch: CVE alerts are four independent per-severity
        // subscriptions, which don't collapse into one on/off.
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('CVE notifications'),
          subtitle: const Text('Choose which severities alert you'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CveNotificationsScreen(),
            ),
          ),
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

/// Mixin for paywall-gated sections that cache an [EntitlementService.isPro]
/// future in `_proCheck`. Re-reads that future whenever entitlement may have
/// changed (sign-in / sign-out, purchase, restore) via the
/// [EntitlementService] notifier — Pro now requires an authenticated session,
/// so the gated UI must lock on sign-out and unlock on sign-in without
/// restarting the app. Listening to the notifier (rather than the raw auth
/// stream) means the refresh fires after `Purchases.logIn` has settled, so a
/// returning Pro user's entitlement resolves correctly on sign-in.
mixin _EntitlementRefresh<T extends StatefulWidget> on State<T> {
  /// Re-read and store the entitlement future, inside a setState.
  void _refreshProCheck();

  void _listenForEntitlementChanges() {
    EntitlementService.instance.addListener(_onEntitlementChanged);
  }

  void _stopListeningForEntitlementChanges() {
    EntitlementService.instance.removeListener(_onEntitlementChanged);
  }

  void _onEntitlementChanged() {
    if (mounted) _refreshProCheck();
  }
}

class _AlertRulesSection extends StatefulWidget {
  const _AlertRulesSection();

  @override
  State<_AlertRulesSection> createState() => _AlertRulesSectionState();
}

class _AlertRulesSectionState extends State<_AlertRulesSection>
    with _EntitlementRefresh {
  Future<bool>? _proCheck;

  @override
  void initState() {
    super.initState();
    _proCheck = EntitlementService.instance.isPro();
    _listenForEntitlementChanges();
  }

  @override
  void dispose() {
    _stopListeningForEntitlementChanges();
    super.dispose();
  }

  @override
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
                  fontWeight: FontWeight.w700,
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

class _DigestScheduleSectionState extends State<_DigestScheduleSection>
    with _EntitlementRefresh {
  Future<bool>? _proCheck;
  Future<DigestPrefs>? _prefsFuture;

  @override
  void initState() {
    super.initState();
    _proCheck = EntitlementService.instance.isPro();
    _prefsFuture = DigestPrefService.instance.getPrefs();
    _listenForEntitlementChanges();
  }

  @override
  void dispose() {
    _stopListeningForEntitlementChanges();
    super.dispose();
  }

  @override
  void _refreshProCheck() {
    setState(() {
      _proCheck = EntitlementService.instance.isPro();
    });
  }

  void _refreshPrefs() {
    setState(() {
      _prefsFuture = DigestPrefService.instance.getPrefs();
    });
  }

  Future<void> _showPaywall() async {
    await PaywallSheet.show(context, reason: PaywallReason.briefing);
    if (!mounted) return;
    _refreshProCheck();
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
    // The scraper runs hourly and only matches on `delivery_hour`, so
    // anything finer than an hour gets silently rounded down. Use a
    // plain hour-only list picker instead of `showTimePicker`, which
    // would let users tap minutes the backend ignores.
    final initial = _deliveryHour;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        // Scroll the current selection into view (each ListTile ≈ 48 px).
        final controller = ScrollController(
          initialScrollOffset: ((initial - 2).clamp(0, 23)) * 48.0,
        );
        return AlertDialog(
          title: const Text('Delivery hour'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.builder(
              controller: controller,
              itemCount: 24,
              itemBuilder: (_, h) {
                final selected = h == initial;
                return ListTile(
                  dense: true,
                  title: Text(_formatHour(h)),
                  trailing: selected
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.pop(ctx, h),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _deliveryHour = picked);
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
                fontWeight: FontWeight.w700,
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

class _CustomFeedsSectionState extends State<_CustomFeedsSection>
    with _EntitlementRefresh {
  Future<bool>? _proCheck;

  @override
  void initState() {
    super.initState();
    _proCheck = EntitlementService.instance.isPro();
    _listenForEntitlementChanges();
  }

  @override
  void dispose() {
    _stopListeningForEntitlementChanges();
    super.dispose();
  }

  @override
  void _refreshProCheck() {
    setState(() {
      _proCheck = EntitlementService.instance.isPro();
    });
  }

  Future<void> _showPaywall() async {
    await PaywallSheet.show(context, reason: PaywallReason.briefing);
    if (!mounted) return;
    _refreshProCheck();
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
                  fontWeight: FontWeight.w700,
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
