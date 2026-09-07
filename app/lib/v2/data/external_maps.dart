// lib/v2/data/external_maps.dart
//
// 장소 상세 시트에서 바깥으로 나가는 길 둘 — 전화, 길찾기 (#328).
//
// ## 위치 제약과의 관계
//
// 여기서 넘기는 좌표는 **카탈로그(공공데이터)의 것**이지 사용자 위치가 아니다. 목적지만
// 지도 앱에 건네고, 출발지(현위치)는 그 앱이 스스로 잡는다. 우리 서버로 나가는 것은 없다
// (A안, #235·#238).
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalMaps {
  /// 실제로 여는 함수. 테스트가 갈아 끼운다 — 기본은 `url_launcher`.
  @visibleForTesting
  static Future<bool> Function(Uri uri) launcher = _launch;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// 전화 앱. 숫자와 `+` 만 남긴다 — 인허가 데이터의 전화는 "02-123-4567" 꼴이다.
  static Future<bool> call(String tel) async {
    final digits = tel.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return false;
    return _try(Uri(scheme: 'tel', path: digits));
  }

  /// 길찾기 — 네이버 지도 앱 → 아무 지도 앱(`geo:`) → 웹 순서로 시도한다.
  ///
  /// `nmap://` 은 네이버 지도가 깔려 있어야 열린다. 없으면 `launchUrl` 이 false 를 주거나
  /// 던지는데, 둘 다 "다음 후보" 로 본다.
  static Future<bool> directions({
    required double lat,
    required double lng,
    required String name,
  }) async {
    final encoded = Uri.encodeComponent(name);
    final candidates = <Uri>[
      Uri.parse('nmap://route/walk?dlat=$lat&dlng=$lng&dname=$encoded&appname=com.cetacealab.heattrip'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($encoded)'),
      Uri.parse('https://map.naver.com/p/search/$encoded'),
    ];
    for (final uri in candidates) {
      if (await _try(uri)) return true;
    }
    return false;
  }

  static Future<bool> _try(Uri uri) async {
    try {
      return await launcher(uri);
    } catch (_) {
      return false;
    }
  }
}
