import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/article.dart';

/// Local persistence of resolved [Article] bodies for bookmarked URLs.
///
/// Bookmarks themselves (URL list) live in [BookmarkService] — that part
/// has always been local-or-cloud. This cache is additive: titles +
/// summaries + tags + published-at for the URLs the user has saved, so
/// the Saved screen renders offline instead of hanging on
/// [ArticleRepository.fetchArticlesByUrls].
///
/// Stored as a single JSON object in SharedPreferences keyed by URL.
/// Small footprint — bookmarks are typically O(tens), each Article JSON
/// is a few hundred bytes. NO new database dependency.
class BookmarkArticleCache {
  BookmarkArticleCache._();
  static final BookmarkArticleCache instance = BookmarkArticleCache._();

  static const String _kPrefsKey = 'bookmark_article_cache_v1';

  Map<String, Article>? _memory;

  /// Reads the persisted blob (once per process), returning a defensive
  /// copy each call.
  Future<Map<String, Article>> load() async {
    final cache = await _ensureLoaded();
    return Map<String, Article>.from(cache);
  }

  /// Merges [articles] into the cache (overwriting existing entries by
  /// URL) and persists. Articles whose URL is not in [articles] stay
  /// put — call [pruneToUrls] when you want to drop unbookmarked
  /// entries.
  Future<void> save(Iterable<Article> articles) async {
    final cache = await _ensureLoaded();
    var changed = false;
    for (final a in articles) {
      cache[a.url] = a;
      changed = true;
    }
    if (changed) await _persist(cache);
  }

  /// Removes any cached entries whose URL is not in [urls]. Use after a
  /// sync to keep the on-disk blob aligned with the current bookmark
  /// list.
  Future<void> pruneToUrls(Iterable<String> urls) async {
    final cache = await _ensureLoaded();
    final keep = urls.toSet();
    final before = cache.length;
    cache.removeWhere((k, _) => !keep.contains(k));
    if (cache.length != before) await _persist(cache);
  }

  Future<Map<String, Article>> _ensureLoaded() async {
    final cached = _memory;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    final loaded = <String, Article>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          try {
            final value = entry.value;
            if (value is Map<String, dynamic>) {
              loaded[entry.key] = Article.fromJson(value);
            }
          } catch (e) {
            // Skip a single corrupt entry — don't blow away the whole
            // cache because one row got malformed across a model change.
            debugPrint('[BookmarkArticleCache] dropped corrupt entry: $e');
          }
        }
      } catch (e) {
        debugPrint('[BookmarkArticleCache] decode failed, resetting: $e');
        await prefs.remove(_kPrefsKey);
      }
    }
    _memory = loaded;
    return loaded;
  }

  Future<void> _persist(Map<String, Article> cache) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      for (final entry in cache.entries) entry.key: entry.value.toJson(),
    });
    await prefs.setString(_kPrefsKey, encoded);
  }
}
