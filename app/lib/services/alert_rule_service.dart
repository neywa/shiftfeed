/// CRUD operations for the user's custom alert rules stored in
/// `user_alert_rules`. All methods are no-ops if the user is not signed in
/// — callers should gate UI access on [UserService.isSignedIn] or Pro.
///
/// `watchRules()` returns a Supabase realtime stream — same pattern as
/// [BookmarkService] — so the Settings screen reactively reflects changes
/// from any device the user is signed in on.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_service.dart';

/// Name of the Supabase table holding alert rules.
const String _kTable = 'user_alert_rules';

/// One custom alert rule belonging to a user.
class AlertRule {
  /// Server-assigned id, null for unsaved rules.
  final String? id;

  /// Human-readable rule name shown in the Settings list.
  final String name;

  /// Whether the rule is currently active.
  final bool enabled;

  /// Categories the rule applies to (empty list ⇒ all categories).
  final List<String> categories;

  /// CVSS score threshold, null disables the threshold check.
  final double? cvssMinimum;

  /// Keywords that must appear in the article title or summary
  /// (empty list ⇒ no keyword filter).
  final List<String> keywords;

  const AlertRule({
    this.id,
    required this.name,
    this.enabled = true,
    this.categories = const [],
    this.cvssMinimum,
    this.keywords = const [],
  });

  /// Builds an [AlertRule] from a Supabase row.
  factory AlertRule.fromJson(Map<String, dynamic> json) {
    final cvss = json['cvss_minimum'];
    return AlertRule(
      id: json['id'] as String?,
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      categories: List<String>.from(json['categories'] ?? const []),
      cvssMinimum: cvss == null ? null : (cvss as num).toDouble(),
      keywords: List<String>.from(json['keywords'] ?? const []),
    );
  }

  /// Serialises the rule for an insert/update. `user_id` is added by the
  /// service; `id` and `created_at` are managed by the database.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'enabled': enabled,
        'categories': categories,
        'cvss_minimum': cvssMinimum,
        'keywords': keywords,
      };

  /// Returns a copy of this rule with the given fields overridden.
  AlertRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<String>? categories,
    double? cvssMinimum,
    bool clearCvss = false,
    List<String>? keywords,
  }) {
    return AlertRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      categories: categories ?? this.categories,
      cvssMinimum: clearCvss ? null : (cvssMinimum ?? this.cvssMinimum),
      keywords: keywords ?? this.keywords,
    );
  }
}

class AlertRuleService {
  AlertRuleService._();
  static final AlertRuleService _instance = AlertRuleService._();
  static AlertRuleService get instance => _instance;

  SupabaseClient get _client => Supabase.instance.client;

  /// Fetches all rules belonging to the signed-in user, newest first.
  /// Returns an empty list if no user is signed in.
  Future<List<AlertRule>> getRules() async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return [];
    final rows = await _client
        .from(_kTable)
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => AlertRule.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Inserts [rule] for the signed-in user and returns the row as
  /// persisted (with the database-assigned id).
  Future<AlertRule> createRule(AlertRule rule) async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) {
      throw StateError('Cannot create alert rule: no signed-in user.');
    }
    final payload = {...rule.toJson(), 'user_id': uid}..remove('id');
    final row = await _client
        .from(_kTable)
        .insert(payload)
        .select()
        .single();
    return AlertRule.fromJson(row);
  }

  /// Updates an existing rule. Throws [ArgumentError] if `rule.id` is
  /// null.
  Future<AlertRule> updateRule(AlertRule rule) async {
    if (rule.id == null) {
      throw ArgumentError('updateRule requires rule.id to be non-null.');
    }
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) {
      throw StateError('Cannot update alert rule: no signed-in user.');
    }
    final payload = rule.toJson()..remove('id');
    final row = await _client
        .from(_kTable)
        .update(payload)
        .eq('id', rule.id!)
        .eq('user_id', uid)
        .select()
        .single();
    return AlertRule.fromJson(row);
  }

  /// Deletes the rule with the given id. No-op if not signed in.
  Future<void> deleteRule(String ruleId) async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return;
    await _client
        .from(_kTable)
        .delete()
        .eq('id', ruleId)
        .eq('user_id', uid);
  }

  /// Flips the `enabled` flag of a rule.
  Future<void> toggleRule(String ruleId, bool enabled) async {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return;
    await _client
        .from(_kTable)
        .update({'enabled': enabled})
        .eq('id', ruleId)
        .eq('user_id', uid);
  }

  /// Live stream of the current user's rules. Empty stream when not
  /// signed in.
  Stream<List<AlertRule>> watchRules() {
    final uid = UserService.instance.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client
        .from(_kTable)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .map(
          (rows) => rows.map(AlertRule.fromJson).toList(),
        );
  }
}
