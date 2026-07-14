import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'services/connectivity_notifier.dart';
import 'services/device_token_service.dart';
import 'services/entitlement_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';
import 'theme/app_theme.dart';
import 'theme/layout_notifier.dart';
import 'theme/theme_notifier.dart';

// RevenueCat publishable SDK keys — safe to ship in source (mobile SDK keys
// are designed for client embedding, like the Supabase anon key).
const String _rcApiKeyAndroid = 'goog_kryEWTjzpwJhvzTbeBEbQfmJXGG';
const String _rcApiKeyApple = 'appl_rWUmfnWfGhUXnUnEPNlPjQIRJfT';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  String url = supabaseUrl;
  String anonKey = supabaseAnonKey;

  if (url.isEmpty || anonKey.isEmpty) {
    try {
      await dotenv.load(fileName: 'assets/.env');
      url = dotenv.env['SUPABASE_URL'] ?? '';
      anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    } catch (e) {
      debugPrint('Could not load .env file: $e');
    }
  }

  if (url.isEmpty || anonKey.isEmpty) {
    throw Exception(
      'Supabase credentials not found. '
      'Set SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define '
      'or assets/.env file.',
    );
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  // Load persisted UI prefs before runApp so the first frame already
  // reflects the user's saved theme + layout — no flash of defaults.
  final initialThemeMode = await ThemeNotifier.loadInitial();
  final initialViewMode = await LayoutNotifier.loadInitial();

  // Connectivity service is process-wide; init once here so the first
  // frame already knows the online state and the offline banner doesn't
  // flicker in after launch.
  await ConnectivityNotifier.instance.init();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    // Push is best-effort. Everything in here must degrade to "no push" on
    // failure — it sits in front of runApp(), so anything that escapes costs
    // the user the whole app (an unguarded APNs failure here once showed a
    // white screen instead of the feed).
    try {
      await Firebase.initializeApp();
      await NotificationService.initialize();
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      try {
        final rcKey = Platform.isAndroid ? _rcApiKeyAndroid : _rcApiKeyApple;
        await EntitlementService.instance.init(rcKey);
      } catch (e) {
        debugPrint('RevenueCat init failed: $e');
      }
      await UserService.instance.init();
      DeviceTokenService.instance.listenForTokenRefresh();

      // Deliberately not awaited: on iOS this blocks on the APNs token, which
      // lands seconds after launch. Holding the first frame for it would just
      // trade a crashed white screen for a slow one.
      unawaited(_reapplyTopicSubscriptions());

      // Pro can now flip mid-session (sign-in/out as well as purchase/restore),
      // so keep FCM topic subscriptions reconciled with entitlement instead of
      // only applying them once at startup. Registered after the line above so
      // the startup linkUser inside UserService.init() doesn't double-trigger.
      EntitlementService.instance.addListener(_reapplyTopicSubscriptions);

      unawaited(_logFcmToken());
    } catch (e) {
      debugPrint('Push notification setup failed: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(initial: initialThemeMode),
        ),
        ChangeNotifierProvider<LayoutNotifier>(
          create: (_) => LayoutNotifier(initial: initialViewMode),
        ),
        ChangeNotifierProvider<ConnectivityNotifier>.value(
          value: ConnectivityNotifier.instance,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

// Debug aid only. Gated on the APNs token because getToken() throws the same
// apns-token-not-set exception the topic calls do.
Future<void> _logFcmToken() async {
  try {
    if (!await NotificationService.ensureApnsToken()) return;
    debugPrint('FCM Token: ${await FirebaseMessaging.instance.getToken()}');
  } catch (e) {
    debugPrint('FCM token fetch failed: $e');
  }
}

// Serializes topic reconciliation triggered by EntitlementService changes.
// _topicsDirty re-runs the loop if another change lands mid-reconcile so the
// last-applied state always reflects the latest entitlement.
bool _reapplyingTopics = false;
bool _topicsDirty = false;

Future<void> _reapplyTopicSubscriptions() async {
  _topicsDirty = true;
  if (_reapplyingTopics) return;
  _reapplyingTopics = true;
  try {
    while (_topicsDirty) {
      _topicsDirty = false;
      final isPro = await EntitlementService.instance.isPro();
      await NotificationService.applyTopicSubscriptions(isPro: isPro);
    }
  } catch (e) {
    debugPrint('Topic re-subscription failed: $e');
  } finally {
    _reapplyingTopics = false;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb) return;
    try {
      _appLinks = AppLinks();
      final initialUri = await _appLinks!.getInitialLink();
      debugPrint('[DeepLink] initial link: $initialUri');
      if (initialUri != null) {
        await UserService.instance.handleDeepLink(initialUri);
      }
      _linkSub = _appLinks!.uriLinkStream.listen(
        (uri) {
          debugPrint('[DeepLink] stream event received: $uri');
          // Fire-and-forget — but surface unhandled errors instead of
          // letting them become silent unhandled-future exceptions.
          UserService.instance.handleDeepLink(uri).catchError((Object e) {
            debugPrint('[DeepLink] handleDeepLink error: $e');
          });
        },
        onError: (Object e) {
          debugPrint('[DeepLink] stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('[DeepLink] init failed: $e');
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, notifier, _) => MaterialApp(
        title: 'ShiftFeed',
        theme: lightTheme(),
        darkTheme: appTheme(),
        themeMode: notifier.mode,
        home: const HomeScreen(),
      ),
    );
  }
}
