// lib/v2/data/external_maps.dart
//
// 장소 상세 시트에서 바깥으로 나가는 길 둘 — 전화, 길찾기 (#328).
//
// ## 위치 제약과의 관계
//
// 여기서 넘기는 좌표는 **카탈로그(공공데이터)의 것**이지 사용자 위치가 아니다. 목적지만
// 지도 앱에 건네고, 출발지(현위치)는 그 앱이 스스로 잡는다. 우리 서버로 나가는 것은 없다
// (A안, #235·#238).
//
// ## 취소는 실패가 아니다 (2026-09-21)
//
// iOS 는 다른 앱을 열 때 "'네이버 지도'에서 열까요?" 를 묻고, 취소하면 `launchUrl` 이 false 를
// 준다. 예전에는 그 false 를 "앱이 없다" 로 읽어 다음 후보(웹 네이버 지도)를 열었다 — 취소했는데
// 사파리의 네이버 지도가 뜨는 것을 사장님이 폰에서 봤다. 이제 **열 수 있는지**(`canLaunchUrl`)를
// 먼저 묻고, 열 수 있다고 한 앱이 안 열리면 거기서 멈춘다. 그 false 는 사람의 답이다.
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 길찾기의 결과.
enum ExternalOpen {
  /// 지도 앱(또는 웹)이 열렸다.
  opened,

  /// 열 수 있는 앱이 있었는데 열리지 않았다 — iOS 의 "열까요?" 에서 취소한 자리다. 다른 후보로
  /// 넘어가지 않고, 화면도 아무 말 안 한다. 취소한 사람에게 "열 수 없어요" 는 거짓이다.
  declined,

  /// 열 것이 하나도 없었다 — 화면이 "지도 앱을 열 수 없어요" 를 말할 자리.
  unavailable,
}

class ExternalMaps {
  /// 실제로 여는 함수. 테스트가 갈아 끼운다 — 기본은 `url_launcher`.
  @visibleForTesting
  static Future<bool> Function(Uri uri) launcher = _launch;

  /// 열 수 있는지 묻는 함수. 테스트가 갈아 끼운다 — 기본은 `canLaunchUrl`.
  ///
  /// iOS 는 `Info.plist` 의 `LSApplicationQueriesSchemes` 에 적은 스킴만, Android 11+ 는
  /// 매니페스트 `<queries>` 에 적은 스킴만 "있다" 고 답한다. 둘 다 `nmap`·`geo` 를 적어 두었다 —
  /// 빼면 네이버 지도가 깔려 있어도 "없다" 가 되어 늘 웹으로 간다.
  @visibleForTesting
  static Future<bool> Function(Uri uri) canOpen = canLaunchUrl;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// 전화 앱. 숫자와 `+` 만 남긴다 — 인허가 데이터의 전화는 "02-123-4567" 꼴이다.
  static Future<bool> call(String tel) async {
    final digits = tel.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return false;
    return _try(Uri(scheme: 'tel', path: digits));
  }

  /// 길찾기 — 네이버 지도 앱 → 아무 지도 앱(`geo:`) → 웹 순서다.
  ///
  /// 앱 후보는 **열 수 있다고 한 것만** 연다. 없는 앱은 건너뛰고, 열 수 있다고 한 앱이 false 를
  /// 주면 [ExternalOpen.declined] 로 멈춘다 — 취소한 사람을 웹으로 데려가지 않는다. 열다가
  /// 던지면(그새 지워졌거나 OS 오류) 다음 후보로 간다. 웹은 마지막 후보라 묻지 않고 그냥 연다 —
  /// Android 11+ 는 `<queries>` 에 https 를 안 적으면 브라우저도 "없다" 고 답하기 때문이다.
  static Future<ExternalOpen> directions({
    required double lat,
    required double lng,
    required String name,
  }) async {
    final encoded = Uri.encodeComponent(name);
    final apps = <Uri>[
      Uri.parse('nmap://route/walk?dlat=$lat&dlng=$lng&dname=$encoded&appname=app.pawloop'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($encoded)'),
    ];
    for (final uri in apps) {
      if (!await _can(uri)) continue;
      final ok = await _tryOrNull(uri);
      if (ok == null) continue;
      return ok ? ExternalOpen.opened : ExternalOpen.declined;
    }
    final web = Uri.parse('https://map.naver.com/p/search/$encoded');
    return await _try(web) ? ExternalOpen.opened : ExternalOpen.unavailable;
  }

  static Future<bool> _can(Uri uri) async {
    try {
      return await canOpen(uri);
    } catch (_) {
      return false;
    }
  }

  /// 열었으면 그 답, 열다가 던졌으면 `null`.
  static Future<bool?> _tryOrNull(Uri uri) async {
    try {
      return await launcher(uri);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _try(Uri uri) async => (await _tryOrNull(uri)) ?? false;
}
