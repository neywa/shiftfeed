import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/article.dart';
import '../theme/app_theme.dart';
import '../utils/favicons.dart';

const _kReleaseGreen = Color(0xFF00AA44);
const _kSecurityOrange = Color(0xFFFF6600);
const _kGitHubGreen = Color(0xFF238636);
const _kCriticalRed = Color(0xFFFF0000);
const _kModerateAmber = Color(0xFFFFAA00);

const _kTitleSize = 15.0;
const _kTagSize = 11.0;

// The full card keeps generous line spacing. The compact card trims the title's
// line box down to roughly the glyph box: a height below the font's natural
// 1.3em means the glyphs overflow their box slightly, which is safe here (one
// line, no clipping) and is what keeps the gaps below positive.
const _kTitleHeightFull = 1.5;
const _kTitleHeightCompact = 1.0;

// Compact spacing is optical — the 8dp gaps are measured to the glyphs, not to
// the line boxes. A line box carries a blank strip above the glyphs and another
// below the baseline, so each gap subtracts the strips of its neighbours.
//
// These four are those strips, measured off a device screenshot rather than
// derived from IBM Plex Sans's nominal metrics: as google_fonts renders it, the
// visible top is the ascender (~0.73em, not the 0.698em cap height) and the
// descent runs deeper than nominal. Deriving them was wrong by up to 0.9dp.
// To re-measure after a font or size change, screenshot the feed and compare
// glyph rows against the card edges.
const _kGap = 8.0;
const _kTitleInkTop = 2.13; // 15dp title at height 1.0
const _kTitleInkBottom = 2.06;
const _kTagInkTop = 3.60; // 11dp tag at its natural line height
const _kTagInkBottom = 3.92;

class ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  final bool compact;
  final bool showBookmarkButton;
  final bool isBookmarked;
  final VoidCallback? onBookmarkToggle;
  final ValueChanged<String>? onTagTap;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.compact = false,
    this.showBookmarkButton = false,
    this.isBookmarked = false,
    this.onBookmarkToggle,
    this.onTagTap,
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

  /// Brand-aligned accent for the left stripe when no severity / security
  /// / release tag has overridden it. Falls back to [kRed] for unknown
  /// sources (incl. user-defined custom RSS feeds), matching the rest of
  /// the app's accent. Sources that always carry semantic tags
  /// (`GitHub Releases`, `Red Hat Security`, `OCP Versions`) never reach
  /// this method and so don't need entries here.
  Color _sourceAccentColor(String source) {
    switch (source) {
      case 'Red Hat Blog':
      case 'Red Hat Developer':
        return kRed; // Red Hat brand red (matches kRed)
      case 'Kubernetes Blog':
        return const Color(0xFF326CE5); // Kubernetes brand blue
      case 'CNCF Blog':
        return const Color(0xFF1976D2); // CNCF brand blue
      case 'Istio Blog':
        return const Color(0xFF466BB0); // Istio brand blue
      case 'Hacker News':
        return const Color(0xFFFF6600); // HN/Y-Combinator orange
      case 'HackerNoon':
        return const Color(0xFF00CC00); // HackerNoon green
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
    final t = tag.toLowerCase();

    // Security / CVE tags — orange
    if (t == 'cve' || t == 'security' || t == 'advisory' ||
        t.startsWith('cve-')) {
      return const Color(0xFFFF6600);
    }

    // Severity tags — color coded
    if (t == 'critical') return const Color(0xFFFF0000);
    if (t == 'important') return const Color(0xFFFF6600);
    if (t == 'moderate') return const Color(0xFFFFAA00);

    // Release tags — green
    if (t == 'release' || t == 'stable-channel') {
      return const Color(0xFF00AA44);
    }

    // HackerNoon brand tag
    if (t == 'hackernoon') return const Color(0xFF00CC00);

    // Everything else — muted gray
    return const Color(0xFF888888);
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

    // Compact: 8dp of visible space above the icon, and below whichever text
    // ends the card — minus that text's blank strip below its baseline.
    final bottomPad = visibleTags.isNotEmpty
        ? _kGap - _kTagInkBottom
        : _kGap - _kTitleInkBottom;

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.none,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: _accentColor()),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? _kGap : 16,
                    16,
                    compact ? bottomPad : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _buildSourceIcon(border),
                          const SizedBox(width: 8),
                          Expanded(
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
                          const SizedBox(width: 8),
                          Text(
                            timeago.format(when),
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          if (showBookmarkButton)
                            IconButton(
                              onPressed: onBookmarkToggle,
                              icon: Icon(
                                isBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_outline,
                                color: isBookmarked ? kRed : muted,
                              ),
                              iconSize: compact ? 20 : 22,
                              padding: EdgeInsets.zero,
                              // In compact mode the button must not exceed the
                              // 20dp source icon, or it drives the header row's
                              // height and the 8dp gaps around the icon stop
                              // holding. `constraints` alone is not enough:
                              // IconButton's ButtonStyle enforces a 48dp tap
                              // target on top of it, so shrinkWrap it too.
                              constraints: compact
                                  ? const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 20,
                                    )
                                  : const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                              style: compact
                                  ? IconButton.styleFrom(
                                      minimumSize: const Size(40, 20),
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    )
                                  : null,
                              tooltip: isBookmarked
                                  ? 'Remove bookmark'
                                  : 'Save article',
                            ),
                        ],
                      ),
                      SizedBox(height: compact ? _kGap - _kTitleInkTop : 10),
                      Text(
                        article.title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: _kTitleSize,
                          fontWeight: FontWeight.w700,
                          height: compact
                              ? _kTitleHeightCompact
                              : _kTitleHeightFull,
                          leadingDistribution: TextLeadingDistribution.even,
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
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                      ],
                      if (visibleTags.isNotEmpty) ...[
                        SizedBox(
                          height: compact
                              ? _kGap - _kTitleInkBottom - _kTagInkTop
                              : 8,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final tag in visibleTags)
                              _TagPill(
                                tag: tag,
                                color: _tagColor(tag),
                                onTap: onTagTap,
                                compact: compact,
                              ),
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

class _TagPill extends StatelessWidget {
  final String tag;
  final Color color;
  final ValueChanged<String>? onTap;
  final bool compact;

  const _TagPill({
    required this.tag,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      // The pill has no visible box, so in compact mode its vertical padding
      // would just read as extra space around the glyphs — the card measures
      // the 8dp gaps to the glyphs themselves and owns that spacing instead.
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 0 : 4),
      child: Text(
        '#$tag',
        style: TextStyle(
          color: color,
          fontSize: _kTagSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (onTap == null) return label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap!(tag),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: label,
      ),
    );
  }
}
