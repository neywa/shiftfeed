import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article.dart';
import '../models/cve_alert.dart';
import '../models/digest.dart';
import '../models/ocp_version.dart';
import '../services/user_service.dart';

/// Thrown by [ArticleRepository] when an underlying Supabase / HTTP call
/// fails. Callers that care about distinguishing "fetch failed (likely
/// offline)" from "fetch succeeded but returned empty" should catch this
/// — the original error is preserved in [cause]. Other call sites can
/// ignore it and the empty/null fallback paths still work via the
/// methods that haven't opted in to rethrow.
class RepoException implements Exception {
  final String operation;
  final Object cause;

  RepoException(this.operation, this.cause);

  @override
  String toString() => 'RepoException($operation): $cause';
}

class ArticleRepository {
  // Read at call time rather than caching — the Supabase Flutter client
  // is a process-wide singleton, but going through `instance.client` on
  // every call sidesteps any worry about mid-session auth changes
  // affecting the held reference.
  SupabaseClient get _client => Supabase.instance.client;

  bool _hasReachedFreeLimit = false;

  // Defense-in-depth visibility filter for `articles` reads. This MIRRORS
  // the two Supabase RLS select policies on the table — global rows
  // (`submitted_by IS NULL`) plus the signed-in user's own custom-feed
  // rows (`submitted_by = auth.uid()`) — so the client never even
  // requests another user's custom-feed rows. RLS remains the
  // authoritative security boundary; this is a second layer so a future
  // RLS misconfiguration can't silently leak custom feeds. The current
  // user is re-read at call time (like `_client`) so a mid-session
  // sign-in / sign-out is reflected immediately.
  PostgrestFilterBuilder<T> _visibleToCurrentUser<T>(
    PostgrestFilterBuilder<T> query,
  ) {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) {
      // Signed out: global rows only.
      return query.filter('submitted_by', 'is', null);
    }
    // Signed in: global rows + this user's own custom rows.
    return query.or('submitted_by.is.null,submitted_by.eq.$uid');
  }

  /// True when a free-tier caller hit the page-2 wall on the most recent
  /// [fetchArticles] call. Reset whenever a fresh `offset = 0` page is
  /// fetched.
  bool get hasReachedFreeLimit => _hasReachedFreeLimit;

  // Feed visibility is enforced by Supabase RLS on the articles table:
  //   - Unauthenticated / free users: only global articles
  //     (submitted_by IS NULL).
  //   - Authenticated Pro users: global + their own custom-feed articles.
  // RLS (via the JWT in the Supabase client) is authoritative; the
  // `_visibleToCurrentUser` filter applied below mirrors those policies as
  // a defense-in-depth guardrail so a future RLS regression can't leak
  // another user's custom feed.
  Future<List<Article>> fetchArticles({
    int limit = 50,
    int offset = 0,
    String? source,
    String? tag,
    bool isPro = true,
  }) async {
    if (offset > 0 && !isPro) {
      _hasReachedFreeLimit = true;
      return [];
    }
    if (offset == 0) {
      _hasReachedFreeLimit = false;
    }
    try {
      var query = _visibleToCurrentUser(_client.from('articles').select());

      if (source != null) {
        query = query.eq('source', source);
      }
      if (tag != null) {
        query = query.contains('tags', [tag]);
      }

      final response = await query
          .order('published_at', ascending: false, nullsFirst: false)
          .limit(limit)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((row) => Article.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchArticles error: $e');
      throw RepoException('fetchArticles', e);
    }
  }

  Future<List<Article>> searchArticles({
    required String query,
    int limit = 50,
  }) async {
    try {
      if (query.startsWith('#')) {
        final tag = query.substring(1).toLowerCase().trim();
        if (tag.isEmpty) return [];
        final response = await _visibleToCurrentUser(
          _client.from('articles').select(),
        )
            .contains('tags', [tag])
            .order('published_at', ascending: false)
            .limit(limit);
        return (response as List)
            .map((row) => Article.fromJson(row as Map<String, dynamic>))
            .toList();
      }

      final response = await _visibleToCurrentUser(
        _client.from('articles').select(),
      )
          .textSearch(
            'search_vector',
            query,
            config: 'english',
            type: TextSearchType.websearch,
          )
          .order('published_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((row) => Article.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('searchArticles error: $e');
      throw RepoException('searchArticles', e);
    }
  }

  /// Fetches the [Article] rows whose `url` is in [urls].
  ///
  /// Order is determined server-side by `published_at` desc — callers that
  /// want to preserve a specific URL order should re-sort using a lookup
  /// map. URLs that don't exist in the `articles` table are silently
  /// omitted (e.g. bookmarked articles that have aged out of the feed).
  Future<List<Article>> fetchArticlesByUrls(List<String> urls) async {
    if (urls.isEmpty) return [];
    try {
      final response = await _visibleToCurrentUser(
        _client.from('articles').select(),
      )
          .inFilter('url', urls)
          .order('published_at', ascending: false, nullsFirst: false);
      return (response as List)
          .map((row) => Article.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchArticlesByUrls error: $e');
      throw RepoException('fetchArticlesByUrls', e);
    }
  }

  /// Fetches `cve`-tagged rows from `articles` for the CVE screen.
  ///
  /// Deliberately NOT [fetchArticles] with `tag: 'cve'`: that method
  /// carries the free-tier page-2 wall (`isPro`), and the CVE screen is
  /// free for everyone. Deliberately NOT `cve_alerts` either — that table
  /// is a per-CVE index keyed on `cve_id` with only `detected_at` (when we
  /// noticed it), whereas the screen wants the article's true
  /// `published_at` plus the full tag list.
  ///
  /// **The `url` secondary sort is load-bearing.** `published_at` has
  /// heavy ties — a scrape run batch-inserts a whole advisory feed with
  /// timestamps inside the same second — and Postgres gives no stable
  /// order among rows that tie on every ORDER BY key. Without a
  /// tiebreaker, `range()` pagination re-shuffles tied rows between
  /// requests, so page 2 can repeat or skip rows from page 1. `url` is the
  /// table's unique key, which makes the total ordering deterministic.
  /// (`cve_id` is a column on `cve_alerts`, not here.)
  Future<List<Article>> fetchCveArticles({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _visibleToCurrentUser(
        _client.from('articles').select(),
      )
          .contains('tags', ['cve'])
          .order('published_at', ascending: false, nullsFirst: false)
          .order('url', ascending: true)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((row) => Article.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchCveArticles error: $e');
      throw RepoException('fetchCveArticles', e);
    }
  }

  Future<Digest?> fetchLatestDigest() async {
    try {
      final response = await _client
          .from('digests')
          .select()
          .order('digest_date', ascending: false)
          .limit(1);
      final rows = response as List;
      if (rows.isEmpty) return null;
      return Digest.fromJson(rows.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('fetchLatestDigest error: $e');
      throw RepoException('fetchLatestDigest', e);
    }
  }

  /// Fetches the [limit] most recently detected CVE alerts.
  ///
  /// Ordering and limiting are server-side: the table has no per-user
  /// scoping, so there is nothing to re-sort client-side.
  Future<List<CveAlert>> fetchCveAlerts({int limit = 10}) async {
    try {
      final response = await _client
          .from('cve_alerts')
          .select()
          .order('detected_at', ascending: false, nullsFirst: false)
          .limit(limit);
      return (response as List)
          .map((row) => CveAlert.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('fetchCveAlerts error: $e');
      return [];
    }
  }

  Future<List<OcpVersion>> fetchOcpVersions() async {
    try {
      // No server-side ORDER BY — `minor_version` is a TEXT column so
      // lex sort puts '4.9' before '4.18'. Both call sites (versions
      // screen, home sidebar) re-sort numerically by `minorInt` anyway.
      final response = await _client.from('ocp_versions').select();
      // Tolerant per-row parse: one malformed row is skipped, not fatal.
      return OcpVersion.parseList(response as List);
    } catch (e) {
      debugPrint('fetchOcpVersions error: $e');
      throw RepoException('fetchOcpVersions', e);
    }
  }

  Future<Map<String, int>> fetchSourceCounts({int days = 7}) async {
    try {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
          .toIso8601String();
      final response = await _visibleToCurrentUser(
        _client.from('articles').select('source'),
      ).gte('published_at', since);
      final list = response as List;
      final counts = <String, int>{};
      for (final row in list) {
        final source = (row as Map<String, dynamic>)['source'] as String;
        counts[source] = (counts[source] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      // ignore: avoid_print
      print('fetchSourceCounts error: $e');
      return {};
    }
  }

  Future<List<String>> fetchTopTags({int limit = 10, int days = 30}) async {
    try {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
          .toIso8601String();
      final response = await _visibleToCurrentUser(
        _client.from('articles').select('tags'),
      ).gte('published_at', since);

      final list = response as List;
      final tagCounts = <String, int>{};

      for (final row in list) {
        final tags = List<String>.from(
          (row as Map<String, dynamic>)['tags'] ?? const [],
        );
        for (final tag in tags) {
          if (_isNoisyTag(tag)) continue;
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }

      final sorted = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sorted.take(limit).map((e) => e.key).toList();
    } catch (e) {
      // ignore: avoid_print
      print('fetchTopTags error: $e');
      return [];
    }
  }

  bool _isNoisyTag(String tag) {
    const noise = {
      'blog', 'community', 'hackernoon', 'reddit',
      'stable-channel', 'rhsa', 'rhba', 'advisory',
    };
    final lower = tag.toLowerCase();
    if (lower.startsWith('cve-')) return true;
    // Filter every per-minor OCP version tag (`ocp-4.14`, `ocp-4.22`, …)
    // — they're emitted on every OCP article and would dominate Top Tags.
    if (lower.startsWith('ocp-4.')) return true;
    return noise.contains(lower);
  }

  static final Uri _scrapeRunsUrl = Uri.parse(
    'https://api.github.com/repos/Neywa/shiftfeed/actions/workflows/scrape.yml/runs?per_page=1&status=success',
  );

  Future<DateTime?> fetchLastScrapedAt() async {
    try {
      final response = await http.get(
        _scrapeRunsUrl,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final runs = body['workflow_runs'] as List?;
      if (runs == null || runs.isEmpty) return null;
      final run = runs.first as Map<String, dynamic>;
      final raw = (run['updated_at'] ?? run['run_started_at']) as String?;
      if (raw == null) return null;
      return DateTime.parse(raw).toLocal();
    } catch (e) {
      // ignore: avoid_print
      print('fetchLastScrapedAt error: $e');
      return null;
    }
  }

  Future<List<String>> fetchSources() async {
    try {
      final response = await _visibleToCurrentUser(
        _client.from('articles').select('source'),
      );
      final sources = (response as List)
          .map((row) => (row as Map<String, dynamic>)['source'] as String)
          .toSet()
          .toList()
        ..sort();
      return sources;
    } catch (e) {
      // ignore: avoid_print
      print('fetchSources error: $e');
      return [];
    }
  }
}
