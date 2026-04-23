import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article.dart';
import '../models/cve_alert.dart';
import '../models/digest.dart';
import '../models/ocp_version.dart';

class ArticleRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Article>> fetchArticles({
    int limit = 50,
    int offset = 0,
    String? source,
    String? tag,
  }) async {
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
