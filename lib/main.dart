import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const BbmpPendingPolesApp());
}

class BbmpPendingPolesApp extends StatelessWidget {
  const BbmpPendingPolesApp({Key? key}) : super(key: key);

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
          background: Color(0xFF0F172A),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

