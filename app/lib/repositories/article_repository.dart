import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article.dart';
import '../models/cve_alert.dart';
import '../models/digest.dart';
import '../models/ocp_version.dart';

class ArticleRepository {
  // Read at call time rather than caching — the Supabase Flutter client
  // is a process-wide singleton, but going through `instance.client` on
  // every call sidesteps any worry about mid-session auth changes
  // affecting the held reference.
  SupabaseClient get _client => Supabase.instance.client;

  bool _hasReachedFreeLimit = false;

  /// True when a free-tier caller hit the page-2 wall on the most recent
  /// [fetchArticles] call. Reset whenever a fresh `offset = 0` page is
  /// fetched.
  bool get hasReachedFreeLimit => _hasReachedFreeLimit;

  // Feed visibility is controlled by Supabase RLS on the articles table:
  //   - Unauthenticated / free users: only global articles
  //     (submitted_by IS NULL).
  //   - Authenticated Pro users: global + their own custom-feed articles.
  // No explicit filter needed here — the JWT in the Supabase client
  // determines what rows are returned.
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
      var query = _client.from('articles').select();

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
      // ignore: avoid_print
      print('fetchArticles error: $e');
      return [];
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
        final response = await _client
            .from('articles')
            .select()
            .contains('tags', [tag])
            .order('published_at', ascending: false)
            .limit(limit);
        return (response as List)
            .map((row) => Article.fromJson(row as Map<String, dynamic>))
            .toList();
      }

      final response = await _client
          .from('articles')
          .select()
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
      // ignore: avoid_print
      print('searchArticles error: $e');
      return [];
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
      final response = await _client
          .from('articles')
          .select()
          .inFilter('url', urls)
          .order('published_at', ascending: false, nullsFirst: false);
      return (response as List)
          .map((row) => Article.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('fetchArticlesByUrls error: $e');
      return [];
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
      // ignore: avoid_print
      print('fetchLatestDigest error: $e');
      return null;
    }
  }

  Future<List<CveAlert>> fetchCveAlerts({int limit = 10}) async {
    try {
      final response = await _client.from('cve_alerts').select();
      final all = (response as List)
          .map((row) => CveAlert.fromJson(row as Map<String, dynamic>))
          .toList();
      all.sort((a, b) {
        final ad = a.createdAt;
        final bd = b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      return all.take(limit).toList();
    } catch (e) {
      // ignore: avoid_print
      print('fetchCveAlerts error: $e');
      return [];
    }
  }

  Future<List<OcpVersion>> fetchOcpVersions() async {
    try {
      final response = await _client
          .from('ocp_versions')
          .select()
          .order('minor_version', ascending: false);
      return (response as List)
          .map((row) => OcpVersion.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('fetchOcpVersions error: $e');
      return [];
    }
  }

  Future<Map<String, int>> fetchSourceCounts({int days = 7}) async {
    try {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
          .toIso8601String();
      final response = await _client
          .from('articles')
          .select('source')
          .gte('published_at', since);
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
      final response = await _client
          .from('articles')
          .select('tags')
          .gte('published_at', since);

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
      'ocp-4.14', 'ocp-4.15', 'ocp-4.16', 'ocp-4.17',
      'ocp-4.18', 'ocp-4.19', 'ocp-4.20', 'ocp-4.21',
    };
    if (tag.toUpperCase().startsWith('CVE-')) return true;
    return noise.contains(tag.toLowerCase());
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
      final response = await _client.from('articles').select('source');
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
