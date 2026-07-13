import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../models/ocp_version.dart';
import '../repositories/article_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/error_state.dart';
import '../widgets/offline_banner.dart';

const Color _kStatusGreen = Color(0xFF00AA44);
const Color _kStatusAmber = Color(0xFFFFAA00);
const Color _kStatusGrey = Color(0xFF555555);

class VersionsScreen extends StatefulWidget {
  /// Whether this screen is the visible tab. Inside the mobile
  /// `IndexedStack` the State is kept alive, so `initState` runs only once
  /// at launch; the parent flips this when the Versions tab is selected so a
  /// previously-empty/failed load can self-heal on revisit. Defaults to true
  /// for the desktop push-route case where the screen is built fresh.
  final bool isActive;

  const VersionsScreen({super.key, this.isActive = true});

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  final ArticleRepository _repository = ArticleRepository();

  List<OcpVersion> _versions = [];
  List<Color> _accentColors = [];
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  @override
  void didUpdateWidget(VersionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Self-heal: the IndexedStack keeps this State alive, so initState only
    // ran once at launch. When the tab becomes visible again, re-attempt a
    // load that previously came up empty or failed. Skip the refetch when
    // data is already valid or a load is in flight (avoids hammering on
    // every tab tap).
    if (!oldWidget.isActive &&
        widget.isActive &&
        !_isLoading &&
        (_versions.isEmpty || _loadFailed)) {
      _loadVersions();
    }
  }

  Future<void> _loadVersions() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final all = await _repository.fetchOcpVersions();
      // All post-fetch transformation lives inside the try so any throw here
      // (an unexpected row shape, a bad minor) routes to the recoverable
      // ErrorState rather than falling through to a silent grey blank.
      final active = all
          .where((v) => v.minorInt >= kOcpActiveMinorMinimum)
          .toList()
        ..sort((a, b) => b.minorInt.compareTo(a.minorInt));

      final colors = <Color>[
        for (int i = 0; i < active.length; i++) _accentForIndex(i),
      ];

      if (!mounted) return;
      setState(() {
        _versions = active;
        _accentColors = colors;
        _isLoading = false;
      });
    } on RepoException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    } catch (e) {
      // Any non-repo failure (post-fetch transformation error) — surface as
      // the recoverable error state, never a silent blank or stuck spinner.
      debugPrint('VersionsScreen: load transform error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Color _accentForIndex(int index) {
    if (index <= 1) return _kStatusGreen;
    if (index <= 3) return _kStatusAmber;
    return _kStatusGrey;
  }

  String _statusLabel(int index) {
    if (index <= 1) return 'LATEST';
    if (index <= 3) return 'SUPPORTED';
    return 'MAINTENANCE';
  }

  @override
  Widget build(BuildContext context) {
    final bg = bgOf(context);
    final textPrimary = textPrimaryOf(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'OCP VERSIONS',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        backgroundColor: bg,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kRed),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kRed),
      );
    }

    if (_loadFailed && _versions.isEmpty) {
      return ErrorState(
        title: "Couldn't load versions",
        body: 'Check your connection and try again.',
        onRetry: _loadVersions,
      );
    }

    if (_versions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 48, color: textMutedOf(context)),
            const SizedBox(height: 16),
            Text(
              'No version data available',
              style: TextStyle(color: textSecondaryOf(context)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadVersions,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: BorderSide(color: kRed.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 8dp rhythm, matching the feed: divider -> header -> cards -> cards.
          // The gaps live here rather than in the cards' own margins so a
          // single value governs the whole column.
          const SizedBox(height: 8),
          _buildHeaderCard(),
          for (int i = 0; i < _versions.length; i++) ...[
            const SizedBox(height: 8),
            _VersionCard(
              version: _versions[i],
              accentColor: _accentColors[i],
              statusLabel: _statusLabel(i),
            ),
          ],
          const SizedBox(height: 16),
          _buildFooter(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final surface = surfaceOf(context);
    final border = borderOf(context);
    final textPrimary = textPrimaryOf(context);
    final textMuted = textMutedOf(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STABLE CHANNEL TRACKER',
                  style: TextStyle(
                    fontSize: 10,
                    color: textMuted,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'OpenShift Active Versions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Updated hourly from cincinnati-graph-data',
                  style: TextStyle(fontSize: 11, color: textMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified, color: _kStatusGreen, size: 20),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final textMuted = textMutedOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.source, size: 12, color: textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: openshift/cincinnati-graph-data — '
                  'candidate → fast → stable promotion pipeline',
                  style: TextStyle(
                    fontSize: 10,
                    color: textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse(
                'https://github.com/openshift/cincinnati-graph-data',
              ),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text(
              'View on GitHub →',
              style: TextStyle(fontSize: 11, color: kRed),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final OcpVersion version;
  final Color accentColor;
  final String statusLabel;

  const _VersionCard({
    required this.version,
    required this.accentColor,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final surface = surfaceOf(context);
    final border = borderOf(context);
    final textPrimary = textPrimaryOf(context);
    final textMuted = textMutedOf(context);

    final cardContent = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: accentColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'OpenShift',
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              version.minorVersion,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                border: Border.all(
                                  color: accentColor,
                                  width: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Latest stable: ',
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted,
                              ),
                            ),
                            Text(
                              version.latestStable,
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Updated ${timeago.format(version.updatedAt)}',
                          style: TextStyle(fontSize: 10, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Open Release Status',
                    child: InkWell(
                      // Land users on the OpenShift Release Status
                      // dashboard (build status + tests for the patch
                      // release) rather than the raw cincinnati YAML.
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://openshift-release.apps.ci.l2s4.p1'
                          '.openshiftapps.com/releasestream/4-stable'
                          '/release/${version.latestStable}',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border, width: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: cardContent,
        ),
      ),
    );
  }
}
