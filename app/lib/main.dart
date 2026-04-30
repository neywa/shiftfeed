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
import 'services/device_token_service.dart';
import 'services/entitlement_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';

// RevenueCat publishable SDK keys — safe to ship in source (mobile SDK keys
// are designed for client embedding, like the Supabase anon key).
// TODO: replace the Apple placeholder with the real key before iOS testing.
const String _rcApiKeyAndroid = 'goog_kryEWTjzpwJhvzTbeBEbQfmJXGG';
const String _rcApiKeyApple = 'REVENUECAT_APPLE_KEY';

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

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await Firebase.initializeApp();
    await NotificationService.initialize();
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
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

    final isPro = await EntitlementService.instance.isPro();
    await NotificationService.applyTopicSubscriptions(isPro: isPro);

    final token = await messaging.getToken();
    debugPrint('FCM Token: $token');
  }

  runApp(
    ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(),
      child: const MyApp(),
    ),
  );
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
