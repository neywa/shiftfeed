// Unit tests for the display-time severity normalization.
//
// The scraper stores TWO severity vocabularies in `articles.tags` and
// deliberately never maps between them: Red Hat's Hydra API says
// low/moderate/important/critical, NVD says low/medium/high/critical. That
// split is correct for storage — the scales genuinely differ — but it left
// a UI gap: `article_card.dart` styles only critical/important/moderate, so
// the NVD-sourced rows render as a plain SECURITY badge with their severity
// invisible. These tests pin the collapse that closes it.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/cve_severity.dart';

void main() {
  group('CveSeverity.fromWord', () {
    test('Red Hat important collapses onto high', () {
      expect(CveSeverity.fromWord('important'), CveSeverity.high);
    });

    test('Red Hat moderate collapses onto medium', () {
      expect(CveSeverity.fromWord('moderate'), CveSeverity.medium);
    });

    test('NVD high/medium/low pass through unchanged', () {
      expect(CveSeverity.fromWord('high'), CveSeverity.high);
      expect(CveSeverity.fromWord('medium'), CveSeverity.medium);
      expect(CveSeverity.fromWord('low'), CveSeverity.low);
    });

    test('critical is shared by both vocabularies', () {
      expect(CveSeverity.fromWord('critical'), CveSeverity.critical);
    });

    test('case and surrounding whitespace are tolerated', () {
      expect(CveSeverity.fromWord('CRITICAL'), CveSeverity.critical);
      expect(CveSeverity.fromWord(' Important '), CveSeverity.high);
    });

    test('non-severity words return null, not a default bucket', () {
      // Every CVE article carries ~a dozen unrelated tags; silently
      // bucketing one of them would mislabel the row.
      for (final tag in ['cve', 'security', 'rhsa', 'ocp-4.18', '']) {
        expect(CveSeverity.fromWord(tag), isNull, reason: tag);
      }
    });
  });

  group('CveSeverity badge styling', () {
    test('every display bucket has a distinct styled color', () {
      // The regression this guards: a bucket with no case in the switch
      // falls through to a generic badge, which is exactly the bug on
      // article_card.dart for NVD-sourced high/medium.
      final colors = {for (final s in CveSeverity.values) s: s.color};
      expect(colors.length, CveSeverity.values.length);
      expect(colors.values.toSet().length, CveSeverity.values.length,
          reason: 'two buckets share a color — they would be indistinguishable');
    });

    test('rank orders critical > high > medium > low', () {
      final sorted = [...CveSeverity.values]
        ..sort((a, b) => a.rank.compareTo(b.rank));
      expect(sorted, [
        CveSeverity.low,
        CveSeverity.medium,
        CveSeverity.high,
        CveSeverity.critical,
      ]);
    });

    test('labels are uppercase badge text', () {
      expect(CveSeverity.critical.label, 'CRITICAL');
      expect(CveSeverity.high.label, 'HIGH');
    });
  });

  group('CveSeverity.fromTags', () {
    test('finds the severity word among unrelated tags', () {
      expect(
        CveSeverity.fromTags(
          ['cve', 'security', 'CVE-2026-25679', 'important', 'cvss:8.1'],
        ),
        CveSeverity.high,
      );
    });

    test('takes the worst when a multi-CVE article carries several', () {
      // The scraper stamps such an article with the MAX cvss; the badge
      // must describe the same CVE as the score.
      expect(
        CveSeverity.fromTags(['low', 'critical', 'moderate']),
        CveSeverity.critical,
      );
    });

    test('takes the worst across the two vocabularies', () {
      // 'important' (Red Hat) outranks 'medium' (NVD) after normalization.
      expect(CveSeverity.fromTags(['medium', 'important']), CveSeverity.high);
    });

    test('returns null when no severity tag is present', () {
      // Real case: cve_tagger's regex path mints cve-tagged articles from
      // blog mentions with no severity at all.
      expect(CveSeverity.fromTags(['cve', 'CVE-2026-1', 'blog']), isNull);
    });

    test('returns null for an empty tag list', () {
      expect(CveSeverity.fromTags(const []), isNull);
    });
  });

  group('cvssFromTags', () {
    test('parses the cvss:X.X contract', () {
      expect(cvssFromTags(['cve', 'cvss:8.1', 'important']), 8.1);
    });

    test('parses an integer-valued score', () {
      expect(cvssFromTags(['cvss:10']), 10.0);
    });

    test('returns null when unscored', () {
      expect(cvssFromTags(['cve', 'security']), isNull);
    });

    test('is deterministic if the one-tag invariant is ever violated', () {
      // The scraper promises exactly one cvss: tag per article, enforced
      // write-side. alert_rule_matcher.py iterates a SET and keeps the
      // last it sees, so a second tag makes ITS score vary run to run. We
      // take the max instead: same answer every render, regardless.
      expect(cvssFromTags(['cvss:4.3', 'cvss:9.8']), 9.8);
      expect(cvssFromTags(['cvss:9.8', 'cvss:4.3']), 9.8);
    });

    test('ignores a malformed score rather than throwing', () {
      expect(cvssFromTags(['cvss:none']), isNull);
      expect(cvssFromTags(['cvss:none', 'cvss:7.5']), 7.5);
    });
  });

  group('cveIdsFromTags', () {
    test('extracts and uppercases every CVE id', () {
      expect(
        cveIdsFromTags(['cve', 'CVE-2026-25679', 'cve-2026-1', 'security']),
        ['CVE-2026-25679', 'CVE-2026-1'],
      );
    });

    test('does not mistake the bare cve marker tag for an id', () {
      expect(cveIdsFromTags(['cve', 'security']), isEmpty);
    });

    test('de-duplicates', () {
      expect(
        cveIdsFromTags(['CVE-2026-1', 'cve-2026-1']),
        ['CVE-2026-1'],
      );
    });
  });
}
