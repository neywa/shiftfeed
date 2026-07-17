import 'package:flutter/material.dart';

/// Display-time normalization of the two severity vocabularies that
/// coexist in `articles.tags`.
///
/// The scraper deliberately does NOT merge them (see CLAUDE.md, "Tag
/// conventions"): Red Hat's Hydra API says `low/moderate/important/
/// critical`, NVD says `low/medium/high/critical`, and they are genuinely
/// different scales — Red Hat's `important` spans NVD's `high` *and*
/// `critical`. `cve_enrichment.py` records which source won rather than
/// mapping between them, so both vocabularies land in the same column.
///
/// That's correct for storage and useless for a UI: a severity filter
/// can't offer the user six overlapping buckets. So we collapse to ONE
/// scale **at display time only** — nothing here writes back, and the
/// stored tags stay exactly as the scraper wrote them.
///
/// The collapse is lossy in the direction Red Hat's scale is coarser
/// (`important` → [high] loses the fact that it might have been an NVD
/// `critical`). That's an accepted tradeoff for a filterable UI; anything
/// needing the true source scale must read the tags directly.
enum CveSeverity {
  critical,
  high,
  medium,
  low;

  /// Rank for sorting — higher is more severe.
  int get rank => switch (this) {
        CveSeverity.critical => 4,
        CveSeverity.high => 3,
        CveSeverity.medium => 2,
        CveSeverity.low => 1,
      };

  /// Uppercase badge text.
  String get label => name.toUpperCase();

  /// Badge accent. Every bucket gets one — unlike `article_card.dart`,
  /// which styles only critical/important/moderate and lets NVD-sourced
  /// `high`/`medium` fall through to a plain SECURITY badge.
  Color get color => switch (this) {
        CveSeverity.critical => const Color(0xFFFF0000),
        CveSeverity.high => const Color(0xFFFF6600),
        CveSeverity.medium => const Color(0xFFFFAA00),
        CveSeverity.low => const Color(0xFF888888),
      };

  /// Maps a single raw severity word from either vocabulary onto the
  /// display scale. Returns null for anything unrecognised, which is how
  /// [fromTags] skips the ~dozen non-severity tags on a CVE article.
  static CveSeverity? fromWord(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'critical':
        return CveSeverity.critical;
      // Red Hat `important` and NVD `high` collapse to the same bucket.
      case 'important':
      case 'high':
        return CveSeverity.high;
      // Red Hat `moderate` and NVD `medium` likewise.
      case 'moderate':
      case 'medium':
        return CveSeverity.medium;
      case 'low':
        return CveSeverity.low;
      default:
        return null;
    }
  }

  /// The article's severity: the most severe recognised word in [tags].
  ///
  /// Takes the max rather than the first match because a multi-CVE
  /// article can carry more than one severity word, and the scraper
  /// already stamps such articles with the *max* CVSS score — taking the
  /// max here keeps the badge and the score describing the same CVE.
  static CveSeverity? fromTags(Iterable<String> tags) {
    CveSeverity? worst;
    for (final tag in tags) {
      final s = fromWord(tag);
      if (s == null) continue;
      if (worst == null || s.rank > worst.rank) worst = s;
    }
    return worst;
  }
}

/// Parses the `cvss:X.X` tag into a score.
///
/// The scraper's contract is exactly one `cvss:` tag per article (see
/// CLAUDE.md) — but that invariant is enforced on the write side, and a
/// regression there would silently make this vary between renders. So we
/// take the max of whatever we find: deterministic regardless, and it
/// matches [CveSeverity.fromTags] picking the worst severity.
double? cvssFromTags(Iterable<String> tags) {
  double? best;
  for (final tag in tags) {
    final lower = tag.toLowerCase();
    if (!lower.startsWith('cvss:')) continue;
    final value = double.tryParse(lower.substring(5).trim());
    if (value == null) continue;
    if (best == null || value > best) best = value;
  }
  return best;
}

/// Every `CVE-YYYY-N` id on the article, uppercased, in tag order.
///
/// The scraper writes these uppercase; we match case-insensitively and
/// normalize because the id is rendered verbatim.
List<String> cveIdsFromTags(Iterable<String> tags) {
  final ids = <String>[];
  for (final tag in tags) {
    if (!tag.toLowerCase().startsWith('cve-')) continue;
    final id = tag.toUpperCase();
    if (!ids.contains(id)) ids.add(id);
  }
  return ids;
}
