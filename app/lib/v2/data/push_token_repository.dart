// lib/v2/data/push_token_repository.dart
//
// 기기 토큰 등록 — `PUT /api/push/tokens {token, platform}` (이슈 #83).
//
// 서버는 upsert 라 응답이 204 하나다 — 새로 만들었는지는 앱이 알 필요가 없다. 같은 기기에서
// 다른 계정이 등록하면 토큰의 주인이 바뀐다(옛 계정의 알림이 새 사람의 기기에 오면 안 된다).
//
// **실패해도 던지지 않는다.** 푸시는 덧이다 — 로그인이나 홈이 토큰 등록 하나 때문에 막히면 안 된다.
// 토큰 값은 로그에 안 찍는다: 그것을 아는 사람은 그 기기로 알림을 보낼 수 있다.
library;

import 'package:flutter/foundation.dart';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

class PushTokenRepository {
  PushTokenRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = (baseUrl ?? Env.apiBase).replaceAll(RegExp(r'/+$'), ''),
        _authed = client ?? AuthedClient.instance;

  final String baseUrl;
  final AuthedClient _authed;

  /// 계약의 `platform` — `android` · `ios` 둘뿐이다(서버가 그 패턴으로 거른다).
  static const String android = 'android';
  static const String ios = 'ios';

  /// 등록했으면 true. 실패는 false — 던지지 않는다.
  Future<bool> register(String token, {required String platform}) async {
    try {
      final res = await _authed.putJson(
        Uri.parse('$baseUrl/api/push/tokens'),
        body: {'token': token, 'platform': platform},
      );
      if (res.statusCode == 204) return true;
      debugPrint('[Push] 토큰 등록 실패 — ${res.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[Push] 토큰 등록 실패 — ${e.runtimeType}');
      return false;
    }
  }
}
