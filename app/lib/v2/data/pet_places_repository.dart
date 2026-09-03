import 'dart:convert';
import 'package:http/http.dart' as http;

import 'location_upload_policy.dart';
import '../../core/config/env.dart';
import '../domain/pet.dart';

/// 반려동반 가능 장소 하나. 계약(`openapi.yaml`)의 `Place` 를 그대로 옮긴다.
///
/// **관광공사를 앱이 직접 부르지 않는다** (이슈 #40). 서비스키가 앱 바이너리 안에 있어야
/// 하는 구조였고, `--dart-define` 으로 옮겨도 문자열은 남아서 `strings` 한 번이면 나온다.
/// 키는 쿼터·과금이 걸린 자격증명이고 폐기하려면 앱을 새로 배포해야 한다 — 즉 즉시 대응이
/// 불가능하다. 지금은 서버가 대신 부르고 결과를 캐시한다.
class PetPlace {
  final String contentId;
  final String title;
  final String contentTypeId;
  final String addr;
  final String image;
  final String tel;
  final double lat;
  final double lng;
  final double distM; // locationBasedList2의 거리(m)

  const PetPlace({
    required this.contentId,
    required this.title,
    required this.contentTypeId,
    required this.addr,
    required this.image,
    required this.tel,
    required this.lat,
    required this.lng,
    this.distM = 0,
  });

  PetCategory get category => petCatByType(contentTypeId);

  String get distLabel =>
      distM <= 0 ? '' : (distM < 1000 ? '${distM.round()}m' : '${(distM / 1000).toStringAsFixed(1)}km');

  /// 서버 응답 하나를 읽는다.
  ///
  /// **키 이름이 KTO 의 것이 아니라 우리 계약의 것이다** — `contentid`/`mapx`/`firstimage`
  /// 가 아니라 `contentId`/`lng`/`image` 다. KTO 의 모양을 해석하는 일은 서버가 한다
  /// (이슈 #40). 여기서 그것을 또 알면 해석이 두 곳에 살게 되고, 한쪽만 고치면 조용히
  /// 갈라진다.
  factory PetPlace.fromJson(Map<String, dynamic> j) => PetPlace(
        contentId: '${j['contentId'] ?? ''}',
        title: '${j['title'] ?? ''}',
        contentTypeId: '${j['contentTypeId'] ?? ''}',
        addr: '${j['addr'] ?? ''}',
        image: '${j['image'] ?? ''}',
        tel: '${j['tel'] ?? ''}',
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        distM: _toDouble(j['distM']),
      );

  /// 숫자가 JSON 에서 `int` 로 올 수도 `double` 로 올 수도 있다.
  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }
}

/// 주변 장소를 **우리 백엔드에서** 받아 온다 — 이슈 #40.
///
/// ## 서비스키를 안 읽는다
///
/// 예전에는 서비스키가 비면 빈 목록을 돌려줬다. 그 줄이 남아 있으면
/// **키 없는 빌드에서 지도가 영구히 빈 화면**이 된다 — 완료 조건 4("서비스키 없이 앱을
/// 빌드해도 지도가 정상 표시된다")가 정확히 거기서 깨진다.
///
/// ## 실패를 빈 목록으로 다룬다
///
/// 예전 동작 그대로다. 서버도 예산이 소진되면 200 + 빈 배열을 주므로, 앱에서는
/// "한도 초과" 와 "이 주변에 장소가 없음" 이 같게 보인다. **한계를 그대로 적는다** —
/// 그 둘을 구분해 보여 주는 것은 별건이고, 그전까지 오류 신호는 서버 지표에만 있다.
class PetPlacesRepository {
  PetPlacesRepository({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Env.apiBase;

  final http.Client _client;
  final String _baseUrl;

  /// 내 주변 반려동반 가능 장소(거리순).
  ///
  /// [radius] 의 상한은 계약이 18,000m 로 정한다 — 서버가 셀 중심에서 20km 를 받아 두고
  /// 셀 반지름(약 1.4km)을 뺀 값이다. 넘겨도 서버가 거절하지 않고 자른다.
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async {
    // 좌표가 기기를 떠나는 자리다. 정책이 꺼져 있으면 **요청 자체를 안 만든다**(#235).
    // 빈 목록은 이 저장소가 실패에서도 주는 값이라 부르는 쪽이 이미 다룬다.
    //
    // 이 경로는 제품이 필요해서가 아니라 관광공사 서비스키를 앱에서 숨기려고 생겼다(#40).
    // 그래서 끄면 장소 목록이 빈다 — 좌표를 격자 셀로 접어 보내는 절충안은 셀이
    // 개인위치정보인지부터 정해야 해서(#235 §5) 지금은 통째로 끈다.
    if (!LocationUploadPolicy.canQueryNearbyPlaces) return const [];

    final uri = Uri.parse('$_baseUrl/api/places/nearby').replace(queryParameters: {
      'lat': '$lat',
      'lng': '$lng',
      'radius': '$radius',
      'limit': '$numOfRows',
      if (contentTypeId != null && contentTypeId.isNotEmpty) 'category': contentTypeId,
    });

    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      return _parse(res.bodyBytes);
    } catch (_) {
      return const [];
    }
  }

  /// 계약은 `Place` 배열이다 — KTO 의 `response.body.items.item` 중첩이 아니다.
  ///
  /// 본문을 `bodyBytes` 에서 직접 디코딩한다. `res.body` 는 서버가 charset 을 안 붙이면
  /// latin-1 로 읽어서 한글이 깨진다(#81 에서 겪었다).
  List<PetPlace> _parse(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => PetPlace.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.lat != 0 && p.lng != 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
