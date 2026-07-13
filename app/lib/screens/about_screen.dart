import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../release_info.dart';
import '../services/entitlement_service.dart';

/// What the app *is*: identity, version, the links that describe it, and the
/// RevenueCat support affordance. Pushed from the About row at the bottom of
/// [SettingsScreen], which keeps only the things you can change.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
    _LinkItem(
      'Web',
      'https://neywa.studio/apps/shiftfeed/',
      Icons.language,
    ),
    _LinkItem(
      'Source Code',
      'https://github.com/neywa/ona',
      Icons.code,
    ),
  ];

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final cardShape = RoundedRectangleBorder(
      side: BorderSide(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(14),
    );

    // Same section heading as Settings, so the two screens read as one.
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
                    leading: Icon(link.icon),
                    title: Text(link.label),
                    onTap: () => _open(link.url),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _RevenueCatIdCard(cardShape: cardShape),
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

/// Renders the app version label on the identity card. Reads
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
        // platform returns a combined string. The release codename comes
        // from the ritual-owned constant in release_info.dart.
        return Text(
          'v${raw.split('+').first} · $kReleaseName',
          style: style,
        );
      },
    );
  }
}

/// Exposes the device's RevenueCat App User ID with a one-tap copy. Used to
/// grant promotional entitlements from the RC dashboard for testers without a
/// paid subscription. Collapses entirely when the SDK can't return an ID (web).
class _RevenueCatIdCard extends StatefulWidget {
  final ShapeBorder cardShape;
  const _RevenueCatIdCard({required this.cardShape});

  @override
  State<_RevenueCatIdCard> createState() => _RevenueCatIdCardState();
}

class _RevenueCatIdCardState extends State<_RevenueCatIdCard> {
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
    return FutureBuilder<String?>(
      future: _idFuture,
      builder: (context, snapshot) {
        final id = snapshot.data;
        if (id == null) return const SizedBox.shrink();
        return Card(
          elevation: 0,
          shape: widget.cardShape,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Copy RevenueCat ID'),
            subtitle: Text(
              id,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
            ),
            trailing: const Icon(Icons.copy, size: 18),
            onTap: () => _copy(id),
          ),
        );
      },
    );
  }
}

class _DataItem {
  final IconData icon;
  final String label;
  const _DataItem(this.icon, this.label);
}

class _LinkItem {
  final String label;
  final String url;
  final IconData icon;
  const _LinkItem(this.label, this.url, this.icon);
}
