import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenShift News',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEE0000),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
