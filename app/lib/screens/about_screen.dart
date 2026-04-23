import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
