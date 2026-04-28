/// Routed bookmark storage.
///
/// Free / signed-out users: a `List<String>` of URLs lives in
/// SharedPreferences under the `bookmarks` key.
///
/// Pro / signed-in users: rows live in `public.user_bookmarks` on Supabase
/// with realtime updates. An in-memory `_cache` mirrors the active backend
/// so [isBookmarked] / [getBookmarks] stay synchronous-feeling even while
/// network writes are in flight.
///
/// All add/remove operations are optimistic — the cache (and therefore the
/// UI) updates first; failed Supabase writes roll back and re-emit on the
/// stream. A single broadcast [StreamController] feeds [watchBookmarks] in
/// both modes so call-sites don't need to know which backend is active.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'entitlement_service.dart';
import 'user_service.dart';

/// Storage key for the URL list used by free / signed-out users.
const String _kPrefsBookmarksKey = 'bookmarks';

/// Legacy SharedPreferences key — used to hold full Article JSON before
/// Phase 2. Read once on first init, URLs extracted, then deleted.
const String _kLegacyBookmarksKey = 'bookmarked_articles';

/// SharedPreferences flag set after a successful local→cloud migration.
const String _kMigratedFlagKey = 'bookmarks_migrated_to_cloud';

/// Name of the Supabase table holding per-user bookmark rows.
const String _kCloudTable = 'user_bookmarks';

class BookmarkService {
  BookmarkService._();
  static BookmarkService? _instance;
  static BookmarkService get instance => _instance ??= BookmarkService._();

  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();

  List<String> _cache = const [];
  bool _initialised = false;
  StreamSubscription<List<Map<String, dynamic>>>? _cloudSub;

  bool get _useCloud =>
      UserService.instance.isSignedIn && _entitlementCachedPro;
  // Cached snapshot of isPro() taken at init or auth-state change. Avoids
  // making isBookmarked / getBookmarks async-fetch RC on every call.
  bool _entitlementCachedPro = false;

  /// One-time service bootstrap.
  ///
  /// Picks the active backend (cloud vs local), populates [_cache], and
  /// subscribes to [UserService.authStateChanges] so the backend can switch
  /// without restarting the app.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    _entitlementCachedPro = await EntitlementService.instance.isPro();
    await _loadInitialCache();
    UserService.instance.authStateChanges.listen((state) async {
      if (state.event == AuthChangeEvent.signedIn) {
        _entitlementCachedPro =
            await EntitlementService.instance.isPro();
        await _loadInitialCache();
      } else if (state.event == AuthChangeEvent.signedOut) {
        _entitlementCachedPro = false;
        await _cloudSub?.cancel();
        _cloudSub = null;
        await _loadInitialCache();
      }
    });
  }

  Future<void> _loadInitialCache() async {
    if (_useCloud) {
      await _initFromCloud();
    } else {
      await _initFromPrefs();
    }
  }

  Future<void> _initFromPrefs() async {
    await _cloudSub?.cancel();
    _cloudSub = null;
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyLocalFormatIfNeeded(prefs);
    _cache = prefs.getStringList(_kPrefsBookmarksKey) ?? const [];
    _controller.add(List.unmodifiable(_cache));
  }

  Future<void> _migrateLegacyLocalFormatIfNeeded(
    SharedPreferences prefs,
  ) async {
    final legacy = prefs.getStringList(_kLegacyBookmarksKey);
    if (legacy == null) return;
    final urls = <String>[];
    for (final entry in legacy) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final url = map['url'] as String?;
        if (url != null && url.isNotEmpty) urls.add(url);
      } catch (_) {
        // Skip malformed legacy entries.
      }
    }
    if (urls.isNotEmpty) {
      final existing = prefs.getStringList(_kPrefsBookmarksKey) ?? const [];
      final merged = <String>{...existing, ...urls}.toList();
      await prefs.setStringList(_kPrefsBookmarksKey, merged);
    }
    await prefs.remove(_kLegacyBookmarksKey);
  }

  Future<void> _initFromCloud() async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) {
      // Lost auth between checks — fall back to local.
      await _initFromPrefs();
      return;
    }
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from(_kCloudTable)
          .select('article_url')
          .eq('user_id', uid)
          .order('saved_at', ascending: false);
      _cache = (rows as List)
          .map((r) => (r as Map<String, dynamic>)['article_url'] as String)
          .toList();
      _controller.add(List.unmodifiable(_cache));
    } catch (e) {
      debugPrint('[BookmarkService] cloud init failed: $e');
      _cache = const [];
      _controller.add(List.unmodifiable(_cache));
    }

    await _cloudSub?.cancel();
    _cloudSub = client
        .from(_kCloudTable)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .listen((rows) {
          _cache = rows
              .map((r) => r['article_url'] as String)
              .toList();
          _controller.add(List.unmodifiable(_cache));
        });
  }

  /// Returns the list of bookmarked URLs from the cache.
  Future<List<String>> getBookmarks() async {
    if (!_initialised) await init();
    return List.unmodifiable(_cache);
  }

  /// Whether [url] is currently bookmarked, per the cache.
  Future<bool> isBookmarked(String url) async {
    if (!_initialised) await init();
    return _cache.contains(url);
  }

  /// Adds [url] optimistically, then persists. Rolls back on persist
  /// failure and emits the rolled-back list on [watchBookmarks].
  Future<void> addBookmark(String url) async {
    if (!_initialised) await init();
    if (_cache.contains(url)) return;
    final previous = List<String>.from(_cache);
    _cache = [url, ..._cache];
    _controller.add(List.unmodifiable(_cache));
    try {
      if (_useCloud) {
        final uid = UserService.instance.currentUser!.id;
        await Supabase.instance.client.from(_kCloudTable).upsert(
          {'user_id': uid, 'article_url': url},
          onConflict: 'user_id,article_url',
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_kPrefsBookmarksKey, _cache);
      }
    } catch (e) {
      debugPrint('[BookmarkService] addBookmark failed: $e');
      _cache = previous;
      _controller.add(List.unmodifiable(_cache));
    }
  }

  /// Removes [url] optimistically, then persists. Rolls back on persist
  /// failure.
  Future<void> removeBookmark(String url) async {
    if (!_initialised) await init();
    if (!_cache.contains(url)) return;
    final previous = List<String>.from(_cache);
    _cache = _cache.where((u) => u != url).toList();
    _controller.add(List.unmodifiable(_cache));
    try {
      if (_useCloud) {
        final uid = UserService.instance.currentUser!.id;
        await Supabase.instance.client
            .from(_kCloudTable)
            .delete()
            .eq('user_id', uid)
            .eq('article_url', url);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_kPrefsBookmarksKey, _cache);
      }
    } catch (e) {
      debugPrint('[BookmarkService] removeBookmark failed: $e');
      _cache = previous;
      _controller.add(List.unmodifiable(_cache));
    }
  }

  /// Toggles [url] — adds if absent, removes if present.
  Future<void> toggleBookmark(String url) async {
    if (await isBookmarked(url)) {
      await removeBookmark(url);
    } else {
      await addBookmark(url);
    }
  }

  /// Removes every bookmark from the active backend.
  Future<void> clearAll() async {
    if (!_initialised) await init();
    final previous = List<String>.from(_cache);
    _cache = const [];
    _controller.add(List.unmodifiable(_cache));
    try {
      if (_useCloud) {
        final uid = UserService.instance.currentUser!.id;
        await Supabase.instance.client
            .from(_kCloudTable)
            .delete()
            .eq('user_id', uid);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_kPrefsBookmarksKey, const []);
      }
    } catch (e) {
      debugPrint('[BookmarkService] clearAll failed: $e');
      _cache = previous;
      _controller.add(List.unmodifiable(_cache));
    }
  }

  /// Reactive view of the bookmark URL list. Emits the current cache on
  /// subscribe and again on every successful or rolled-back mutation.
  Stream<List<String>> watchBookmarks() async* {
    if (!_initialised) await init();
    yield List.unmodifiable(_cache);
    yield* _controller.stream;
  }

  /// One-time lift of the local SharedPreferences bookmarks into the
  /// authenticated user's `user_bookmarks` rows. Called by [UserService]
  /// after a successful sign-in. Idempotent — guarded by the
  /// `bookmarks_migrated_to_cloud` flag.
  Future<void> migrateLocalToCloud() async {
    if (!UserService.instance.isSignedIn) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kMigratedFlagKey) == true) return;
      await _migrateLegacyLocalFormatIfNeeded(prefs);
      final urls = prefs.getStringList(_kPrefsBookmarksKey) ?? const [];
      if (urls.isEmpty) {
        await prefs.setBool(_kMigratedFlagKey, true);
        return;
      }
      final uid = UserService.instance.currentUser!.id;
      final rows = urls
          .map((u) => {'user_id': uid, 'article_url': u})
          .toList();
      await Supabase.instance.client.from(_kCloudTable).upsert(
            rows,
            onConflict: 'user_id,article_url',
          );
      await prefs.remove(_kPrefsBookmarksKey);
      await prefs.setBool(_kMigratedFlagKey, true);
    } catch (e) {
      debugPrint('[BookmarkService] migrateLocalToCloud failed: $e');
    }
  }
}
