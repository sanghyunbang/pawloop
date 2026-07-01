import 'package:flutter/foundation.dart';
import 'package:heat_trip_flutter/features/auth/service/token_storage.dart';

/// 전역 로그인 상태. 앱 시작 시 [init], 로그인/로그아웃 시 갱신.
class AuthState {
  static final ValueNotifier<bool> loggedIn = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final token = await TokenStorage.getToken();
    loggedIn.value = token != null && token.isNotEmpty;
  }

  static void markLoggedIn() => loggedIn.value = true;

  static Future<void> logout() async {
    await TokenStorage.clearToken();
    loggedIn.value = false;
  }
}
