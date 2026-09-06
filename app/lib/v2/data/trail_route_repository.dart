import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';

/// 산책로 코스 하나의 선 — 계약의 `TrailRoute` (이슈 #291).
///
/// 좌표는 **`[경도, 위도]`** 다 — 계약의 `Walk.path` 와 같은 순서이고, 산책 경로 그림
/// (`RouteArt.lngLat`)도 같은 순서를 쓴다. 지도에 그릴 때 `NLatLng(lat, lng)` 로 뒤집는다.
class TrailRoute {
  final String courseId;
  final String name;
  final int lengthM;
  final List<List<double>> lngLat;

  const TrailRoute({
    required this.courseId,
    required this.name,
    required this.lengthM,
    required this.lngLat,
  });

  factory TrailRoute.fromJson(Map<String, dynamic> j) {
    final raw = j['points'];
    final points = <List<double>>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is List && p.length >= 2) {
          final lng = _toDouble(p[0]);
          final lat = _toDouble(p[1]);
          if (lng != null && lat != null) points.add([lng, lat]);
        }
      }
    }
    return TrailRoute(
      courseId: '${j['courseId'] ?? ''}',
      name: '${j['name'] ?? ''}',
      lengthM: (j['lengthM'] is num) ? (j['lengthM'] as num).round() : 0,
      lngLat: points,
    );
  }

  static double? _toDouble(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
}

/// `GET /api/places/trails/{courseId}/route` — 이슈 #291.
///
/// **요청에 사용자 좌표가 없다.** 실리는 것은 두루누비의 코스 번호 하나다 — 공공데이터의
/// 키이지 사람의 위치가 아니다. 그래서 `LocationUploadPolicy` 와 무관하게 A안 빌드에서도
/// 부른다(지도가 있는 빌드에서만 그리긴 한다).
///
/// 실패는 `null` 이다. 선을 못 받아도 카드는 그대로다 — 산책로 항목은 카탈로그의 점으로
/// 이미 화면에 있고, 선은 덧그림이다.
class TrailRouteRepository {
  TrailRouteRepository({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Env.apiBase;

  final http.Client _client;
  final String _baseUrl;

  /// 같은 코스를 두 번 받지 않는다 — 시트를 열 때마다 부르는 자리다.
  final Map<String, TrailRoute> _memory = {};

  Future<TrailRoute?> fetch(String courseId) async {
    final cached = _memory[courseId];
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/api/places/trails/${Uri.encodeComponent(courseId)}/route');
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      // bodyBytes 에서 직접 디코딩한다 — res.body 는 charset 이 없으면 한글이 깨진다(#81).
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      final route = TrailRoute.fromJson(decoded.cast<String, dynamic>());
      if (route.lngLat.length < 2) return null;
      _memory[courseId] = route;
      return route;
    } catch (_) {
      return null;
    }
  }
}
