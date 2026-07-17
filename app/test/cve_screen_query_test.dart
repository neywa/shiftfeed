// Tests for the CVE screen's ordering + filtering logic.
//
// `fetchCveArticles` itself talks to Supabase and isn't unit-testable
// without standing up the client, so what's pinned here is the ordering
// CONTRACT it depends on: given rows in the shape the query returns, the
// sort is total and stable. The tiebreaker is the reason this matters —
// see the comment on the pagination group below.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/article.dart';
import 'package:shiftfeed/models/cve_severity.dart';

Article _article({
  required String url,
  String title = 'Advisory',
  List<String> tags = const ['cve'],
  String? publishedAt,
}) {
  return Article.fromJson({
    'id': url,
    'title': title,
    'url': url,
    'source': 'Red Hat',
    'tags': tags,
    'summary': null,
    'published_at': publishedAt,
    'created_at': '2026-07-16T00:00:00+00:00',
  });
}

/// Mirrors the server-side ORDER BY in
/// `ArticleRepository.fetchCveArticles`: published_at desc, then url asc.
int _serverOrder(Article a, Article b) {
  final da = a.publishedAt;
  final db = b.publishedAt;
  if (da != null && db != null && da != db) return db.compareTo(da);
  if (da == null && db != null) return 1;
  if (da != null && db == null) return -1;
  return a.url.compareTo(b.url);
}

void main() {
  group('date ordering', () {
    test('newest first', () {
      final rows = [
        _article(url: 'https://a', publishedAt: '2026-07-01T00:00:00+00:00'),
        _article(url: 'https://b', publishedAt: '2026-07-16T00:00:00+00:00'),
        _article(url: 'https://c', publishedAt: '2026-07-08T00:00:00+00:00'),
      ]..sort(_serverOrder);
      expect(rows.map((a) => a.url), ['https://b', 'https://c', 'https://a']);
    });

    test('rows with no published_at sort last, not first', () {
      final rows = [
        _article(url: 'https://none', publishedAt: null),
        _article(url: 'https://dated', publishedAt: '2026-07-01T00:00:00+00:00'),
      ]..sort(_serverOrder);
      expect(rows.first.url, 'https://dated');
    });
  });

  group('pagination stability', () {
    // THE reason `url` is in the ORDER BY. A scrape run batch-inserts a
    // whole advisory feed with published_at values inside the same second,
    // so ties are the norm, not an edge case. Postgres gives no stable
    // order among rows tying on every sort key — so without a tiebreaker
    // two `range()` calls can interleave the tied rows differently and
    // page 2 repeats or skips rows from page 1.
    final tied = [
      for (final n in ['e', 'a', 'd', 'b', 'c'])
        _article(url: 'https://$n', publishedAt: '2026-07-16T09:00:00+00:00'),
    ];

    test('ties break deterministically on url', () {
      final sorted = [...tied]..sort(_serverOrder);
      expect(
        sorted.map((a) => a.url),
        ['https://a', 'https://b', 'https://c', 'https://d', 'https://e'],
      );
    });

    test('repeated loads of the same tied rows produce the same order', () {
      // Simulates the server handing back tied rows in a different
      // arbitrary order on a second request.
      final first = [...tied]..sort(_serverOrder);
      final shuffled = [tied[3], tied[0], tied[4], tied[2], tied[1]];
      final second = [...shuffled]..sort(_serverOrder);
      expect(first.map((a) => a.url), second.map((a) => a.url));
    });

    test('paging tied rows yields no duplicates and no gaps', () {
      final sorted = [...tied]..sort(_serverOrder);
      final page1 = sorted.take(2).toList();
      final page2 = sorted.skip(2).take(2).toList();
      final seen = [...page1, ...page2].map((a) => a.url).toList();
      expect(seen.toSet().length, seen.length, reason: 'duplicate across pages');
      expect(seen, ['https://a', 'https://b', 'https://c', 'https://d']);
    });
  });

  group('severity ordering', () {
    test('sorts most-severe first across both vocabularies', () {
      // Mixed Red Hat + NVD words — the sort must compare normalized
      // buckets, not raw strings.
      final rows = [
        _article(url: 'https://med', tags: ['cve', 'medium']),
        _article(url: 'https://crit', tags: ['cve', 'critical']),
        _article(url: 'https://low', tags: ['cve', 'low']),
        _article(url: 'https://imp', tags: ['cve', 'important']),
      ]..sort((a, b) {
          final sa = CveSeverity.fromTags(a.tags)?.rank ?? 0;
          final sb = CveSeverity.fromTags(b.tags)?.rank ?? 0;
          return sb.compareTo(sa);
        });
      expect(
        rows.map((a) => a.url),
        ['https://crit', 'https://imp', 'https://med', 'https://low'],
      );
    });

    test('unscored articles sink below every scored one', () {
      // cve_tagger's regex path mints cve-tagged blog mentions with no
      // severity; they must not outrank a real CRITICAL.
      final rows = [
        _article(url: 'https://blog', tags: ['cve']),
        _article(url: 'https://low', tags: ['cve', 'low']),
      ]..sort((a, b) {
          final sa = CveSeverity.fromTags(a.tags)?.rank ?? 0;
          final sb = CveSeverity.fromTags(b.tags)?.rank ?? 0;
          return sb.compareTo(sa);
        });
      expect(rows.first.url, 'https://low');
    });
  });

  group('severity filter', () {
    final rows = [
      _article(url: 'https://crit', tags: ['cve', 'critical']),
      _article(url: 'https://imp', tags: ['cve', 'important']),
      _article(url: 'https://high', tags: ['cve', 'high']),
      _article(url: 'https://blog', tags: ['cve']),
    ];

    List<Article> filter(Set<CveSeverity> sel) => rows.where((a) {
          final s = CveSeverity.fromTags(a.tags);
          return s != null && sel.contains(s);
        }).toList();

    test('HIGH matches both Red Hat important and NVD high', () {
      // The payoff of normalizing: one chip, both vocabularies.
      expect(
        filter({CveSeverity.high}).map((a) => a.url),
        ['https://imp', 'https://high'],
      );
    });

    test('multi-select unions the buckets', () {
      expect(
        filter({CveSeverity.critical, CveSeverity.high}).length,
        3,
      );
    });

    test('an unscored article matches no severity filter', () {
      expect(
        filter(CveSeverity.values.toSet()).map((a) => a.url),
        isNot(contains('https://blog')),
      );
    });
  });
}
