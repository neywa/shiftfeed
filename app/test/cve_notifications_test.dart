// Per-severity CVE notification wiring.
//
// Two silent failure modes are pinned here.
//
// 1. TOPIC DRIFT. The four `cve_*` topic strings are a cross-language
//    contract with the scraper (SEVERITY_TOPICS in
//    scraper/sources/cve_severity.py). Nothing at compile time connects
//    them; a renamed topic on either side produces an app that subscribes
//    to a topic no one publishes to, and pushes that silently stop.
//
// 2. ORPHANED RETIREMENT. `security` used to carry every CVE. Dropping it
//    from kProNotificationTopics without unsubscribing leaves old installs
//    subscribed to a topic they can no longer see a switch for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftfeed/models/cve_severity.dart';
import 'package:shiftfeed/screens/cve_notifications_screen.dart';
import 'package:shiftfeed/services/notification_service.dart';
import 'package:shiftfeed/widgets/paywall_sheet.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('topic names', () {
    test('are exactly the four the scraper publishes to', () {
      // Pinned as literals on purpose. Deriving these from the enum in the
      // test as well as the source would let a rename sail through both.
      expect(kCveTopics, ['cve_critical', 'cve_high', 'cve_medium', 'cve_low']);
    });

    test('cover every CveSeverity bucket', () {
      expect(kCveTopics.length, CveSeverity.values.length);
      for (final s in CveSeverity.values) {
        expect(kCveTopics, contains(cveTopicFor(s)));
      }
    });

    test('are ordered worst-first, matching the CVE screen', () {
      expect(cveTopicFor(CveSeverity.critical), 'cve_critical');
      expect(cveTopicFor(CveSeverity.high), 'cve_high');
      expect(cveTopicFor(CveSeverity.medium), 'cve_medium');
      expect(cveTopicFor(CveSeverity.low), 'cve_low');
    });
  });

  group('retirement of the old security topic', () {
    test('security is no longer a Pro topic', () {
      expect(kProNotificationTopics, isNot(contains('security')));
    });

    test('security is listed as retired', () {
      expect(kRetiredTopics, contains('security'));
    });

    test('a non-Pro device still unsubscribes from security', () async {
      // The whole point of retirement: it cannot be conditional on Pro, or
      // lapsed/free devices keep the orphaned subscription forever.
      final plan = await NotificationService.planTopicSubscriptions(
        isPro: false,
      );
      expect(
        plan,
        contains(const TopicAction(topic: 'security', subscribe: false)),
      );
    });

    test('a Pro device unsubscribes from security too', () async {
      final plan = await NotificationService.planTopicSubscriptions(
        isPro: true,
      );
      expect(
        plan,
        contains(const TopicAction(topic: 'security', subscribe: false)),
      );
      expect(
        plan.where((a) => a.topic == 'security' && a.subscribe),
        isEmpty,
        reason: 'security must never be subscribed to again',
      );
    });

    test('retirement is planned before any subscribe', () async {
      final plan = await NotificationService.planTopicSubscriptions(
        isPro: true,
      );
      expect(plan.first.topic, 'security');
    });
  });

  group('defaults', () {
    test('every CVE topic is OFF on first launch', () async {
      for (final topic in kCveTopics) {
        expect(
          await NotificationService.getTopicEnabled(topic),
          isFalse,
          reason: '$topic must be opt-in',
        );
      }
    });

    test('all and releases keep their historical opt-out default', () async {
      // An upgrade must not silently mute someone's existing briefing.
      expect(await NotificationService.getTopicEnabled('all'), isTrue);
      expect(await NotificationService.getTopicEnabled('releases'), isTrue);
    });

    test('a fresh Pro device subscribes to no CVE topic', () async {
      final plan = await NotificationService.planTopicSubscriptions(
        isPro: true,
      );
      for (final topic in kCveTopics) {
        expect(
          plan,
          contains(TopicAction(topic: topic, subscribe: false)),
          reason: '$topic must stay off until opted into',
        );
      }
    });
  });

  group('plan reconciliation', () {
    test('Pro + enabled pref subscribes only that severity', () async {
      SharedPreferences.setMockInitialValues({'notif_cve_critical': true});
      final plan = await NotificationService.planTopicSubscriptions(
        isPro: true,
      );
      final subscribed =
          plan.where((a) => a.subscribe).map((a) => a.topic).toList();
      expect(subscribed, containsAll(['cve_critical', 'all', 'releases']));
      expect(subscribed, isNot(contains('cve_high')));
      expect(subscribed, isNot(contains('cve_low')));
    });

    test('a lapsed Pro unsubscribes from everything, prefs regardless',
        () async {
      SharedPreferences.setMockInitialValues({
        'notif_cve_critical': true,
        'notif_cve_high': true,
        'notif_all': true,
      });
      final plan = await NotificationService.planTopicSubscriptions(
        isPro: false,
      );
      expect(
        plan.where((a) => a.subscribe),
        isEmpty,
        reason: 'no subscription may survive losing Pro',
      );
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CveNotificationsScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders one switch per severity, labelled as the CVE screen',
        (tester) async {
      await pump(tester);
      expect(find.byType(SwitchListTile), findsNWidgets(4));
      for (final s in CveSeverity.values) {
        expect(find.text(s.label), findsOneWidget);
      }
    });

    testWidgets('all switches start off', (tester) async {
      await pump(tester);
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches.map((s) => s.value), everyElement(isFalse));
    });

    testWidgets('a non-Pro user cannot enable a switch', (tester) async {
      // EntitlementService.isPro() resolves false here: no dev override
      // pref is set and the test platform is not Android/iOS.
      await pump(tester);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      final first =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile).first);
      expect(first.value, isFalse, reason: 'the flip must revert');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('notif_cve_critical'),
        isNull,
        reason: 'a blocked flip must not persist a pref',
      );
    });

    testWidgets('a blocked flip shows the paywall', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      // By type, not by copy — the upsell wording is free to change.
      expect(find.byType(PaywallSheet), findsOneWidget);
    });
  });
}
