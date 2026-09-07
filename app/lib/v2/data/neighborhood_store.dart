// lib/v2/data/neighborhood_store.dart
//
// 고른 동네를 기기에 적고 **코드만** 서버에 보낸다 — 이슈 #342.
//
// ## 좌표가 나가는 자리가 아니다
//
// 서버로 보내는 값은 `{"neighborhoodCode":"1120052000"}` 하나다. 중심 좌표는 기기에만
// 남는다 — 지도의 첫 화면이 그 값을 쓰고, 서버는 그것을 받지도 저장하지도 않는다(#235 A안).
//
// `LocationUploadPolicy` 를 지나지 않는 이유가 있다: 그 게이트는 **단말이 잰 좌표**가
// 나가는 자리를 막는 장치인데, 여기서 나가는 것은 사람이 목록에서 고른 코드다. 보낼 좌표가
// 없으므로 게이트가 거를 것도 없다 — `place_catalog` 가 같은 자리에 있다.
//
// ## 왜 기기에도 두나
//
// 지도의 기본 중심과 커뮤니티의 "우리 동네" 토글이 **로그인 전에도, 오프라인에서도** 그
// 값을 읽는다. 서버에만 두면 게스트가 동네를 고를 수 없다(#324 의 게스트 홈과 같은 자리다).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';
import '../domain/neighborhood.dart';

/// 동네가 바뀐 횟수. 지도·커뮤니티가 이것을 보고 다시 읽는다.
final ValueNotifier<int> kNeighborhoodRev = ValueNotifier<int>(0);

class NeighborhoodStore {
  NeighborhoodStore({AuthedClient? client, String? baseUrl})
      : _authed = client ?? AuthedClient.instance,
        _baseUrl = baseUrl ?? Env.apiBase;

  final AuthedClient _authed;
  final String _baseUrl;

  static const _key = 'v2.neighborhood';

  /// 고른 동네. 없으면 `null`.
  Future<Neighborhood?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return Neighborhood.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  /// 기기에 적고 **코드만** 서버에 보낸다.
  ///
  /// 서버 전송이 실패해도 기기의 값은 남긴다 — 로그인 전에 고른 사람도 지도가 그 동네로
  /// 열려야 하고, 다음에 로그인하면 [syncToServer] 가 다시 보낸다. 돌려주는 값은
  /// **서버까지 갔는가**다.
  Future<bool> save(Neighborhood neighborhood) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(neighborhood.toJson()));
    kNeighborhoodRev.value++;
    return syncToServer(neighborhood.code);
  }

  /// 지운다. 서버 쪽도 빈 문자열로 지운다.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    kNeighborhoodRev.value++;
    await syncToServer('');
  }

  /// `PUT /auth/me` 로 코드만 보낸다. **좌표도 이름도 안 보낸다** —
  /// 이름은 서버가 자기 표에서 붙이고(그래야 남의 화면에 거짓 동네가 안 뜬다),
  /// 좌표는 애초에 서버가 쓰지 않는다.
  Future<bool> syncToServer(String code) async {
    try {
      final response = await _authed.putJson(
        Uri.parse('$_baseUrl/auth/me'),
        body: {'neighborhoodCode': code},
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) {
        debugPrint('[Neighborhood] 서버 저장 실패: ${response.statusCode}');
      }
      return false;
    } catch (e) {
      // 게스트·오프라인이면 여기로 온다. 기기의 값은 이미 저장됐으므로 화면은 그대로 산다.
      if (kDebugMode) debugPrint('[Neighborhood] 서버 저장 오류: ${e.runtimeType}');
      return false;
    }
  }
}
