import 'package:flutter/material.dart';
import 'v2/screens/main_shell.dart';

/// v2 디자인 진입점.
/// 실행: flutter run -t lib/main_v2.dart
void main() => runApp(const HeatTripV2App());

class HeatTripV2App extends StatelessWidget {
  const HeatTripV2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heat Trip',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3E8F9),
      ),
      home: const MainShell(),
    );
  }
}
