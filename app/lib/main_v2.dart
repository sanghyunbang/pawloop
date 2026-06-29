import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'core/config/env.dart';
import 'v2/screens/main_shell.dart';

/// v2 디자인 진입점.
/// 실행: flutter run -t lib/main_v2.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load();
  } catch (e) {
    debugPrint('[dotenv] load skipped: $e');
  }
  final id = Env.naverMapClientId;
  if (id.isNotEmpty) {
    try {
      await FlutterNaverMap().init(
        clientId: id,
        onAuthFailed: (ex) => debugPrint('[NaverMap] auth failed: $ex'),
      );
    } catch (e) {
      debugPrint('[NaverMap] init failed: $e');
    }
  } else {
    debugPrint('[NaverMap] NAVER_MAP_CLIENT_ID 미설정 — 지도 비활성');
  }
  runApp(const HeatTripV2App());
}

class HeatTripV2App extends StatelessWidget {
  const HeatTripV2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heat Trip',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
        scaffoldBackgroundColor: const Color(0xFFF3E8F9),
      ),
      home: const MainShell(),
    );
  }
}
