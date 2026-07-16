// Unit tests for CveAlert parsing.
//
// These pin the column contract for `cve_alerts`. The model once read
// `json['created_at']` — a column that does not exist on this table. Dart
// returns null for a missing key, so every row parsed with a null timestamp
// and nothing threw: the sort in ArticleRepository.fetchCveAlerts flattened
// to a no-op and the "LATEST CVES" sidebar showed arbitrary rows, while the
// timeago stamp (guarded on non-null) never rendered at all.
//
// The real column is `detected_at`. `articles` is the table with a genuine
// `created_at`, which is where the mistake came from.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/cve_alert.dart';

/// A row shaped exactly like a live `cve_alerts` row — every column the
/// table actually has, so this fixture can't drift from the schema.
Map<String, dynamic> _row({
  String id = 'e18780ec-0d62-4dbd-bed3-d80a8011c0cb',
  String cveId = 'CVE-2026-25679',
  String title = 'CVE-2026-25679: net/url: Incorrect parsing of IPv6 literals',
  String articleUrl =
      'https://access.redhat.com/security/cve/CVE-2026-25679',
  String? severity, // present-but-null on all 290 live rows
  String? detectedAt = '2026-04-22T07:40:32.019358+00:00',
  bool notified = false,
}) {
  return {
    'id': id,
    'cve_id': cveId,
    'title': title,
    'article_url': articleUrl,
    'severity': severity,
    'detected_at': detectedAt,
    'notified': notified,
  };
}

void main() {
  group('CveAlert.fromJson', () {
    test('parses a well-formed row', () {
      final alert = CveAlert.fromJson(_row());

      expect(alert.cveId, 'CVE-2026-25679');
      expect(alert.title, contains('net/url'));
      expect(
        alert.articleUrl,
        'https://access.redhat.com/security/cve/CVE-2026-25679',
      );
      expect(alert.detectedAt, isNotNull);
      expect(
        alert.detectedAt!.toUtc(),
        DateTime.utc(2026, 4, 22, 7, 40, 32, 19, 358),
      );
    });

    test('reads detected_at, NOT created_at', () {
      // The regression pin. On the old code this row parsed a non-null
      // timestamp off `created_at`; the column doesn't exist on this table,
      // so the only correct outcome is null.
      final row = _row(detectedAt: null)
        ..remove('detected_at')
        ..['created_at'] = '2026-04-22T07:40:32.019358+00:00';

      expect(CveAlert.fromJson(row).detectedAt, isNull);
    });

    test('a null detected_at parses to null rather than throwing', () {
      // The sidebar guards the timeago stamp on non-null, so null must be a
      // survivable value, not an exception.
      expect(CveAlert.fromJson(_row(detectedAt: null)).detectedAt, isNull);
    });

    test('throws on a malformed row (null required field)', () {
      final bad = _row()..['cve_id'] = null;
      expect(() => CveAlert.fromJson(bad), throwsA(anything));
    });

    test('an unmapped severity column does not disturb parsing', () {
      // `cve_alerts.severity` exists but the scraper never writes it (see
      // upsert_cve_alert in scraper/supabase_client.py — it sends only
      // cve_id/title/article_url), so it is null on every live row. The
      // model deliberately doesn't carry it; severity is derived from
      // `articles.tags` (critical/important/moderate) instead. This pins
      // that a populated value would still parse, should that ever change.
      final alert = CveAlert.fromJson(_row(severity: 'important'));

      expect(alert.cveId, 'CVE-2026-25679');
      expect(alert.detectedAt, isNotNull);
    });
  });
}
