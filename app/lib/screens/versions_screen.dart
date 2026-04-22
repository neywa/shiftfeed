import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../models/ocp_version.dart';
import '../repositories/article_repository.dart';
import '../theme/app_theme.dart';

const Color _kStatusGreen = Color(0xFF00AA44);
const Color _kStatusAmber = Color(0xFFFFAA00);
const Color _kStatusGrey = Color(0xFF555555);

class VersionsScreen extends StatefulWidget {
  const VersionsScreen({super.key});

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  final ArticleRepository _repository = ArticleRepository();

  List<OcpVersion> _versions = [];
  List<Color> _accentColors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    setState(() => _isLoading = true);
    final all = await _repository.fetchOcpVersions();
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kRed),
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
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 8),
          for (int i = 0; i < _versions.length; i++)
            _VersionCard(
              version: _versions[i],
              accentColor: _accentColors[i],
              statusLabel: _statusLabel(i),
            ),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse(
                        'https://github.com/openshift/cincinnati-graph-data'
                        '/blob/master/channels/stable-${version.minorVersion}.yaml',
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
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
