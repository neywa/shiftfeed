import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await NotificationService.initialize();

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

  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  await messaging.subscribeToTopic('all');
  await messaging.subscribeToTopic('security');
  await messaging.subscribeToTopic('releases');

  final token = await messaging.getToken();
  debugPrint('FCM Token: $token');

  runApp(
    ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
