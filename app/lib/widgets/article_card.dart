import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/article.dart';
import '../theme/app_theme.dart';
import '../utils/favicons.dart';

const _kReleaseGreen = Color(0xFF00AA44);
const _kSecurityOrange = Color(0xFFFF6600);
const _kGitHubGreen = Color(0xFF238636);
const _kCriticalRed = Color(0xFFFF0000);
const _kModerateAmber = Color(0xFFFFAA00);

class ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  final bool compact;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.compact = false,
  });

  bool get _isRelease => article.tags.contains('release');
  bool get _isSecurity =>
      article.tags.contains('security') || article.tags.contains('cve');

  String? get _severity {
    if (article.tags.contains('critical')) return 'CRITICAL';
    if (article.tags.contains('important')) return 'IMPORTANT';
    if (article.tags.contains('moderate')) return 'MODERATE';
    return null;
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return _kCriticalRed;
      case 'IMPORTANT':
        return _kSecurityOrange;
      case 'MODERATE':
        return _kModerateAmber;
    }
    return _kSecurityOrange;
  }

  Color _sourceAccentColor(String source) {
    switch (source) {
      case 'HackerNoon':
        return const Color(0xFF00FF00);
      default:
        return kRed;
    }
  }

  Color _accentColor() {
    final severity = _severity;
    if (severity != null) return _severityColor(severity);
    if (_isSecurity) return _kSecurityOrange;
    if (_isRelease) return _kReleaseGreen;
    return _sourceAccentColor(article.source);
  }

  Color _tagColor(String tag) {
    if (tag == 'release') return _kReleaseGreen;
    if (tag == 'security' || tag == 'cve') return _kSecurityOrange;
    return kRed;
  }

  Widget _buildSourceIcon(Color border) {
    if (article.source == 'GitHub Releases') {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: _kGitHubGreen,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.rocket_launch,
          size: 12,
          color: Colors.white,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        faviconAsset(article.source),
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Container(
          width: 20,
          height: 20,
          color: border,
        ),
      ),
    );
  }

  Widget? _buildBadge() {
    final severity = _severity;
    if (severity != null) {
      return _badge(label: severity, color: _severityColor(severity));
    }
    if (_isSecurity) {
      return _badge(label: 'SECURITY', color: _kSecurityOrange);
    }
    if (_isRelease) {
      return _badge(label: 'RELEASE', color: _kReleaseGreen);
    }
    return null;
  }

  Widget _badge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = textSecondaryOf(context);
    final muted = textMutedOf(context);
    final border = theme.dividerColor;
    final titleColor = theme.colorScheme.onSurface;

    final when = article.publishedAt ?? article.createdAt;
    final maxTags = compact ? 2 : 3;
    final visibleTags = article.tags.take(maxTags).toList();
    final hasSummary = !compact &&
        article.summary != null &&
        article.summary!.isNotEmpty;
    final titleMaxLines = compact ? 1 : 2;
    final badge = _buildBadge();

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: _accentColor()),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: compact ? 10 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _buildSourceIcon(border),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              article.source.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 11,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            badge,
                          ],
                          const Spacer(),
                          Text(
                            timeago.format(when),
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        article.title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          forceStrutHeight: true,
                          height: 1.4,
                        ),
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                          fontFamily: GoogleFonts.ibmPlexSans().fontFamily,
                        ),
                      ),
                      if (hasSummary) ...[
                        const SizedBox(height: 8),
                        Text(
                          article.summary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (visibleTags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          runSpacing: 4,
                          children: [
                            for (int i = 0; i < visibleTags.length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Text(
                                '#${visibleTags[i]}',
                                style: TextStyle(
                                  color: _tagColor(visibleTags[i]),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
