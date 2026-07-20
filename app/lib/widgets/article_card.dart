import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/article.dart';
import '../theme/app_theme.dart';
import '../theme/text_metrics.dart';
import '../utils/favicons.dart';

const _kReleaseGreen = Color(0xFF00AA44);
const _kSecurityOrange = Color(0xFFFF6600);
const _kGitHubGreen = Color(0xFF238636);
const _kCriticalRed = Color(0xFFFF0000);
const _kModerateAmber = Color(0xFFFFAA00);

const _kTitleSize = 15.0;
const _kSummarySize = 13.0;
const _kTagSize = 11.0;

// The header's source icon and the gap to its right, reused both to lay out the
// header and to indent the full card's body text under the source *name*.
const _kSourceIconSize = 20.0;
const _kSourceIconGap = 8.0;

// Full-card body text (title/summary/tags) aligns under the source *name*, not
// the source icon: the name's left edge sits icon width + header gap to the
// right of the icon's left edge. Compact keeps everything flush left.
const _kSourceNameIndent = _kSourceIconSize + _kSourceIconGap;

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

// Exception to the compact card's 8dp rhythm: the gap between the title and the
// footer (tags) is opened to 16dp so the tags read as a distinct block rather
// than crowding the title. Every other compact gap stays at _kGapCompact.
const _kCompactTitleToFooterGap = 16.0;

// The ink strips inside a line box — see theme/text_metrics.dart, which the
// Settings screen shares.

// The tag pill sets no `height`, so Flutter uses the font's own line metrics
// (which carry a leading the multiplier would otherwise replace) and
// inkTop/inkBottom do not apply. Measured directly instead.
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
      case 'Last Week in Kubernetes Development':
        return const Color(0xFF326CE5); // Kubernetes brand blue (k8s community project)
      case 'Azure Red Hat OpenShift':
        return const Color(0xFF0078D4); // Microsoft Azure brand blue
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
        width: _kSourceIconSize,
        height: _kSourceIconSize,
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
        width: _kSourceIconSize,
        height: _kSourceIconSize,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Container(
          width: _kSourceIconSize,
          height: _kSourceIconSize,
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

  // The save button. Lives in the footer row of both the compact and full
  // cards, right-aligned. Capped to the 20dp source-icon height: `constraints`
  // alone isn't enough because IconButton's ButtonStyle enforces a 48dp tap
  // target, so shrinkWrap it too.
  Widget _buildBookmarkButton(Color muted,
      {AlignmentGeometry alignment = Alignment.center}) {
    return IconButton(
      onPressed: onBookmarkToggle,
      icon: Icon(
        isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
        color: isBookmarked ? kRed : muted,
      ),
      iconSize: 20,
      padding: EdgeInsets.zero,
      // The 40dp tap box is wider than the 20dp glyph. In the footer we align
      // it right so the icon shares the timestamp's right axis (both flush to
      // the content padding edge).
      alignment: alignment,
      constraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 20,
      ),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 20),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      tooltip: isBookmarked ? 'Remove bookmark' : 'Save article',
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
    // Both cards move the badge, tags and bookmark into a single footer row
    // below the body. The header keeps only icon · name · time.
    final hasFooter = badge != null || hasTags || showBookmarkButton;

    // Every gap below is `gap` of *visible* space: the nominal value minus the
    // blank strips inside the line boxes on either side of it. The source icon
    // and the card edges are real boxes, so they contribute no strip.
    final gap = compact ? _kGapCompact : _kGapFull;
    final titleHeight = compact ? _kTitleHeightCompact : _kTitleHeightFull;
    final titleInkTop = inkTop(_kTitleSize, titleHeight);
    final titleInkBottom = inkBottom(_kTitleSize, titleHeight);
    final summaryInkTop = inkTop(_kSummarySize, _kSummaryHeight);
    final summaryInkBottom = inkBottom(_kSummarySize, _kSummaryHeight);
    // The full card keeps the tag pill's 4dp padding (16dp of space can absorb
    // it); the compact card drops it — see _TagPill.
    final tagPadding = compact ? 0.0 : 4.0;
    final tagInkTop = _kTagInkTop + tagPadding;
    final tagInkBottom = _kTagInkBottom + tagPadding;

    // Both cards shift the body text right so it shares a left axis with the
    // source name in the header (icon width + header gap to the right of the
    // icon's left edge).
    final textIndent = _kSourceNameIndent;

    final topPad = gap;
    final headerToTitle = gap - titleInkTop;
    // Compact cards open the title→footer gap to 16dp (see the constant); every
    // other gap on both cards uses the card's own nominal.
    final titleToFooterGap = compact ? _kCompactTitleToFooterGap : gap;
    final titleToNext = hasSummary
        ? gap - titleInkBottom - summaryInkTop
        : titleToFooterGap - titleInkBottom - tagInkTop;
    final summaryToTags = gap - summaryInkBottom - tagInkTop;
    // Whatever ends the card sets the bottom padding. Full cards end on the
    // footer row: when it carries tags the tag pill's ink strip is the bottom
    // edge (same as the old body tags row); when it's only the badge/bookmark
    // box there is no ink strip, so the full nominal gap applies — as with the
    // header icon box at the top.
    final bottomPad = hasFooter
        ? (hasTags ? gap - tagInkBottom : gap)
        : hasTags
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
                          const SizedBox(width: _kSourceIconGap),
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
                          // Both cards keep the first line to icon · name ·
                          // time; the badge, tags and bookmark drop to the
                          // footer row below the body.
                          const SizedBox(width: 8),
                          Text(
                            timeago.format(when),
                            style: AppTextStyles.caption.copyWith(color: muted),
                          ),
                        ],
                      ),
                      SizedBox(height: headerToTitle),
                      Padding(
                        padding: EdgeInsets.only(left: textIndent),
                        child: Text(
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
                      ),
                      if (hasSummary) ...[
                        SizedBox(height: titleToNext),
                        Padding(
                          padding: EdgeInsets.only(left: textIndent),
                          child: Text(
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
                        ),
                      ],
                      // Footer row — badge + tags on the body text axis (left),
                      // save button pinned to the card's right edge.
                      if (hasFooter) ...[
                        SizedBox(
                          height: hasSummary ? summaryToTags : titleToNext,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(left: textIndent),
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (badge != null) badge,
                                    for (final tag in visibleTags)
                                      _TagPill(
                                        tag: tag,
                                        color: _tagColor(tag),
                                        onTap: onTagTap,
                                        compact: compact,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (showBookmarkButton)
                              _buildBookmarkButton(
                                muted,
                                alignment: Alignment.centerRight,
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
