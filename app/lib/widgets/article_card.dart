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
const _kSummarySize = 13.0;
const _kTagSize = 11.0;

// The full card keeps generous line spacing (its title can wrap to two lines).
// The compact card trims the title's line box down to roughly the glyph box: a
// height below the font's natural 1.3em means the glyphs overflow their box
// slightly, which is safe there (one line, no clipping) and is what keeps its
// 8dp gaps from going negative.
const _kTitleHeightFull = 1.5;
const _kTitleHeightCompact = 1.0;
const _kSummaryHeight = 1.5;

// Both cards space their contents optically: the gap is measured to the glyphs,
// not to the line boxes. A line box carries a blank strip above the glyphs and
// another below the baseline, so each gap subtracts the strips of its
// neighbours. The compact card uses 8dp, the full card 16dp.
const _kGapCompact = 8.0;
const _kGapFull = 16.0;

// The strips, per em, for text with an explicit `height` — measured off a device
// screenshot rather than derived from IBM Plex Sans's nominal metrics. As
// google_fonts renders it, the visible top is the ascender (~0.73em, not the
// 0.698em cap height) and the descent runs deeper than nominal; deriving these
// from the published numbers was wrong by up to 0.9dp.
const _kFontBox = 1.3; // the font's natural line box
const _kInkTopEm = 0.292; // ascent -> first glyph row
const _kInkBottomEm = 0.32; // baseline -> box bottom

/// Blank strip inside a [Text]'s line box, above its glyphs.
/// [height] is the style's line-height multiplier; its extra leading splits
/// evenly top and bottom (every [Text] here sets leadingDistribution.even).
double _inkTop(double size, double height) =>
    (height - _kFontBox) * size / 2 + _kInkTopEm * size;

/// Blank strip inside a [Text]'s line box, below its baseline.
double _inkBottom(double size, double height) =>
    (height - _kFontBox) * size / 2 + _kInkBottomEm * size;

// The tag pill sets no `height`, so Flutter uses the font's own line metrics
// (which carry a leading the multiplier would otherwise replace) and the two
// formulas above do not apply. Measured directly instead.
const _kTagInkTop = 3.60;
const _kTagInkBottom = 3.56;

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
    final hasTags = visibleTags.isNotEmpty;

    // Every gap below is `gap` of *visible* space: the nominal value minus the
    // blank strips inside the line boxes on either side of it. The source icon
    // and the card edges are real boxes, so they contribute no strip.
    final gap = compact ? _kGapCompact : _kGapFull;
    final titleHeight = compact ? _kTitleHeightCompact : _kTitleHeightFull;
    final titleInkTop = _inkTop(_kTitleSize, titleHeight);
    final titleInkBottom = _inkBottom(_kTitleSize, titleHeight);
    final summaryInkTop = _inkTop(_kSummarySize, _kSummaryHeight);
    final summaryInkBottom = _inkBottom(_kSummarySize, _kSummaryHeight);
    // The full card keeps the tag pill's 4dp padding (16dp of space can absorb
    // it); the compact card drops it — see _TagPill.
    final tagPadding = compact ? 0.0 : 4.0;
    final tagInkTop = _kTagInkTop + tagPadding;
    final tagInkBottom = _kTagInkBottom + tagPadding;

    final topPad = gap;
    final headerToTitle = gap - titleInkTop;
    final titleToNext = hasSummary
        ? gap - titleInkBottom - summaryInkTop
        : gap - titleInkBottom - tagInkTop;
    final summaryToTags = gap - summaryInkBottom - tagInkTop;
    // Whatever ends the card sets the bottom padding.
    final bottomPad = hasTags
        ? gap - tagInkBottom
        : hasSummary
            ? gap - summaryInkBottom
            : gap - titleInkBottom;

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      // The accent stripe below is a square-cornered box flush with the card's
      // left edge, so it has to be clipped to the rounded shape or its corners
      // poke out past the card's.
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
                  padding: EdgeInsets.fromLTRB(16, topPad, 16, bottomPad),
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
                              iconSize: 20,
                              padding: EdgeInsets.zero,
                              // The button must not exceed the 20dp source
                              // icon, or it drives the header row's height and
                              // the gaps around the icon stop holding — the row
                              // has to be exactly as tall as the icon.
                              // `constraints` alone is not enough: IconButton's
                              // ButtonStyle enforces a 48dp tap target on top of
                              // it, so shrinkWrap it too.
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 20,
                              ),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(40, 20),
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              tooltip: isBookmarked
                                  ? 'Remove bookmark'
                                  : 'Save article',
                            ),
                        ],
                      ),
                      SizedBox(height: headerToTitle),
                      Text(
                        article.title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: _kTitleSize,
                          fontWeight: FontWeight.w700,
                          height: titleHeight,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                      if (hasSummary) ...[
                        SizedBox(height: titleToNext),
                        Text(
                          article.summary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondary,
                            fontSize: _kSummarySize,
                            height: _kSummaryHeight,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                      ],
                      if (hasTags) ...[
                        SizedBox(
                          height: hasSummary ? summaryToTags : titleToNext,
                        ),
                        Wrap(
                          // The pills carry no padding of their own, so the
                          // Wrap owns the whole gap between them.
                          spacing: 16,
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
      // The pill has no visible box, so any padding just reads as space around
      // the glyphs — and horizontally it would shove the '#' off the card's
      // text axis, which the icon, title and summary all sit on. So the pill's
      // box *is* its glyph box: the Wrap owns the gap between tags, and in
      // compact mode the card owns the vertical gaps (measured to the glyphs).
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 4),
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
