/// Manages the user's custom RSS feed sources stored in
/// `user_rss_sources`. Pro users can add up to [CustomRssSource.maxSources]
/// feeds; the scraper fetches them hourly and stamps the resulting
/// articles with `submitted_by` so RLS scopes them to the owner.
///
/// All methods are no-ops for unauthenticated callers — gate UI access
/// on Pro entitlement before exposing this service.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_service.dart';

const String _kTable = 'user_rss_sources';

/// One row in `user_rss_sources` describing a Pro user's custom feed.
class CustomRssSource {
  /// Maximum number of feeds a user is allowed.
  static const int maxSources = 10;

  /// Server-assigned id, null for unsaved rows.
  final String? id;

  /// Feed URL (RSS or Atom).
  final String url;

  /// User-defined display name.
  final String label;

  /// Whether the scraper should fetch this feed.
  final bool enabled;

  /// When the row was inserted (server-assigned).
  final DateTime? addedAt;

  /// Most recent fetch error, or null if the last fetch was healthy.
  final String? lastError;

  const CustomRssSource({
    this.id,
    required this.url,
    required this.label,
    this.enabled = true,
    this.addedAt,
    this.lastError,
  });

  factory CustomRssSource.fromJson(Map<String, dynamic> json) {
    return CustomRssSource(
      id: json['id'] as String?,
      url: json['url'] as String,
      label: json['label'] as String,
      enabled: json['enabled'] as bool? ?? true,
      addedAt: json['added_at'] == null
          ? null
          : DateTime.parse(json['added_at'] as String),
      lastError: json['last_error'] as String?,
    );
  }

  /// Serialises for an insert/update. `user_id`, `id` and `added_at` are
  /// managed by the service / database.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'url': url,
        'label': label,
        'enabled': enabled,
      };
}

/// Thrown by [CustomRssService.addSource] when the user already has the
/// maximum number of sources allowed.
class RssSourceLimitException implements Exception {
  final String message =
      'Maximum of ${CustomRssSource.maxSources} sources reached';
  @override
  String toString() => message;
}

/// Thrown by [CustomRssService.addSource] when the URL fails client-side
/// validation (e.g. missing scheme).
class RssUrlInvalidException implements Exception {
  final String message;
  const RssUrlInvalidException(this.message);
  @override
  String toString() => message;
}

class CustomRssService {
  CustomRssService._();
  static final CustomRssService _instance = CustomRssService._();
  static CustomRssService get instance => _instance;

  // Read at call time so mid-session auth changes (sign-in / sign-out)
  // are reflected — Supabase Flutter's client object is a process-wide
  // singleton, so this stays cheap.
  SupabaseClient get _client => Supabase.instance.client;

  /// All sources for the signed-in user, newest first. Empty when
  /// signed out.
  Future<List<CustomRssSource>> getSources() async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from(_kTable)
          .select()
          .eq('user_id', uid)
          .order('added_at', ascending: false);
      return (rows as List)
          .map((r) => CustomRssSource.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('CustomRssService.getSources failed: $e');
      rethrow;
    }
  }

  /// Inserts a new source. Validates [url] client-side, enforces the
  /// per-user maximum, and returns the persisted row.
  ///
  /// Throws [RssUrlInvalidException] if the URL is malformed,
  /// [RssSourceLimitException] if the user already has
  /// [CustomRssSource.maxSources] feeds, or [StateError] if not signed
  /// in.
  Future<CustomRssSource> addSource({
    required String url,
    required String label,
  }) async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) {
      throw StateError('Cannot add RSS source: no signed-in user.');
    }
    final trimmedUrl = url.trim();
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) {
      throw const RssUrlInvalidException('Label is required.');
    }
    if (!_isValidUrl(trimmedUrl)) {
      throw const RssUrlInvalidException(
        'URL must start with http:// or https://',
      );
    }

    final existing = await getSources();
    if (existing.length >= CustomRssSource.maxSources) {
      throw RssSourceLimitException();
    }

    try {
      final payload = {
        'url': trimmedUrl,
        'label': trimmedLabel,
        'enabled': true,
        'user_id': uid,
      };
      final row = await _client
          .from(_kTable)
          .insert(payload)
          .select()
          .single();
      return CustomRssSource.fromJson(row);
    } catch (e) {
      debugPrint('CustomRssService.addSource failed: $e');
      rethrow;
    }
  }

  /// Deletes a source by id. No-op if not signed in.
  Future<void> deleteSource(String sourceId) async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return;
    try {
      await _client
          .from(_kTable)
          .delete()
          .eq('id', sourceId)
          .eq('user_id', uid);
    } catch (e) {
      debugPrint('CustomRssService.deleteSource failed: $e');
      rethrow;
    }
  }

  /// Flips the `enabled` flag.
  Future<void> toggleSource(String sourceId, bool enabled) async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return;
    try {
      await _client
          .from(_kTable)
          .update({'enabled': enabled})
          .eq('id', sourceId)
          .eq('user_id', uid);
    } catch (e) {
      debugPrint('CustomRssService.toggleSource failed: $e');
      rethrow;
    }
  }

  /// Realtime stream of the current user's sources. Empty stream when
  /// signed out — same pattern as [BookmarkService] / [AlertRuleService].
  Stream<List<CustomRssSource>> watchSources() {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client
        .from(_kTable)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .map((rows) {
          final list = rows
              .map((r) => CustomRssSource.fromJson(r))
              .toList()
            ..sort((a, b) {
              final ad = a.addedAt;
              final bd = b.addedAt;
              if (ad == null && bd == null) return 0;
              if (ad == null) return 1;
              if (bd == null) return -1;
              return bd.compareTo(ad);
            });
          return list;
        });
  }

  bool _isValidUrl(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }
}
