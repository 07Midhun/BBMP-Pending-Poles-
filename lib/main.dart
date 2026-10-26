import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/database_service.dart';
import 'services/sync_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BbmpPendingPolesApp());
}

class BbmpPendingPolesApp extends StatelessWidget {
  const BbmpPendingPolesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BBMP Pending Poles',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF0284C7),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0284C7),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      home: const InitializerScreen(),
    );
  }
}

class InitializerScreen extends StatefulWidget {
  const InitializerScreen({super.key});

  @override
  State<InitializerScreen> createState() => _InitializerScreenState();
}

class _InitializerScreenState extends State<InitializerScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    bool isLoggedInToday = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUser = prefs.getString('saved_username');
      final loginDate = prefs.getString('login_date');
      final today = DateTime.now().toIso8601String().split('T')[0];

      isLoggedInToday = (savedUser != null && loginDate == today);
    } catch (e) {
      debugPrint('SharedPreferences error: $e');
    }

    // Safely init DB and Sync in background without blocking screen navigation
    try {
      DatabaseService.instance.database.catchError((e) {
        debugPrint('Database init error: $e');
        return DatabaseService.instance.database;
      });
    } catch (e) {
      debugPrint('DatabaseService error: $e');
    }

    try {
      SyncService.instance;
    } catch (e) {
      debugPrint('SyncService error: $e');
    }

    if (!mounted) return;

    if (isLoggedInToday) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF38BDF8),
        ),
      ),
    );
  }
}



