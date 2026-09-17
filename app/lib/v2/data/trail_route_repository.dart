import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/net/net_timeouts.dart';

/// 산책로 코스 하나가 **어디로 가는지** — 계약의 `TrailRoute` (이슈 #291 · #619).
///
/// 출처에 따라 답이 둘 중 하나다. **둘 다 비는 일은 없다** — 서버가 줄 것이 없으면 404 다.
///
/// | 출처 | [lngLat] | [waypoints] |
/// |:---|:---|:---|
/// | 두루누비 | GPX 선 300점 | 빈 목록 |
/// | 동네 길 | 빈 목록 | 거쳐 가는 곳 이름 |
///
/// 좌표는 **`[경도, 위도]`** 다 — 계약의 `Walk.path` 와 같은 순서이고, 산책 경로 그림
/// (`RouteArt.lngLat`)도 같은 순서를 쓴다. 지도에 그릴 때 `NLatLng(lat, lng)` 로 뒤집는다.
class TrailRoute {
  final String courseId;
  final String name;
  final int lengthM;
  final List<List<double>> lngLat;

  /// 거쳐 가는 곳의 **이름** — 좌표가 아니다 (#619).
  ///
  /// 동네 길의 원본에는 선 좌표가 없다. 이 이름들을 좌표로 바꿔 이으면 실제로 걷는 길이
  /// 아닌 직선이 되고, 사용자는 그 선을 믿고 걷는다 — 그래서 **바꾸지 않는다**.
  /// 자르는 일은 서버가 한다(구분자가 일곱 가지다).
  final List<String> waypoints;

  const TrailRoute({
    required this.courseId,
    required this.name,
    required this.lengthM,
    required this.lngLat,
    this.waypoints = const [],
  });

  /// 지도에 그릴 선이 있나. 두 점 미만은 선이 아니다.
  bool get hasLine => lngLat.length >= 2;

  /// 화면에 보여 줄 것이 하나라도 있나.
  bool get isEmpty => !hasLine && waypoints.isEmpty;

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
    final stops = <String>[];
    final rawStops = j['waypoints'];
    if (rawStops is List) {
      for (final s in rawStops) {
        final text = '${s ?? ''}'.trim();
        if (text.isNotEmpty) stops.add(text);
      }
    }
    return TrailRoute(
      courseId: '${j['courseId'] ?? ''}',
      name: '${j['name'] ?? ''}',
      lengthM: (j['lengthM'] is num) ? (j['lengthM'] as num).round() : 0,
      lngLat: points,
      waypoints: stops,
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

  /// 코스 하나의 선. 못 받으면 `null` 이고 **화면은 선만 안 그린다**.
  ///
  /// <b>여기는 일부러 실패를 말하지 않는다</b>(#515 에서 다시 본 자리). 장소 목록과 다르다 —
  /// 목록은 화면의 본문이라 못 받은 것을 "없다" 로 말하면 거짓말이 되지만, 선은 이미 떠 있는
  /// 카드 위의 덧그림이다. 그 하나 때문에 실패 카드를 띄우면 카드의 나머지(이름·거리·시간)를
  /// 읽던 사람의 흐름이 끊긴다.
  ///
  /// 다만 `null` 이 <b>세 가지를 뭉친다</b> — 없는 코스(404) · 서버가 못 줌(5xx) · 줄 것이
  /// 아무것도 없음. **"선이 없다" 는 더 이상 여기 없다**(#619) — 그건 `null` 이 아니라
  /// [TrailRoute.hasLine] 이 거짓인 답으로 온다. 남은 셋을 가를 필요가 생기면 그때
  /// `PlaceFailure` 와 같은 모양을 여기도 둔다.
  Future<TrailRoute?> fetch(String courseId) async {
    final cached = _memory[courseId];
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/api/places/trails/${Uri.encodeComponent(courseId)}/route');
    try {
      final res = await _client.get(uri).timeout(NetTimeouts.standard);
      if (res.statusCode != 200) return null;
      // bodyBytes 에서 직접 디코딩한다 — res.body 는 charset 이 없으면 한글이 깨진다(#81).
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      final route = TrailRoute.fromJson(decoded.cast<String, dynamic>());
      // 선이 없어도 경유지가 있으면 보여 줄 것이 있다(#619). 여기서 선만 보고 버리면
      // 동네 길은 다시 "눌러도 아무 일도 안 나는" 상태로 돌아간다.
      if (route.isEmpty) return null;
      _memory[courseId] = route;
      return route;
    } catch (_) {
      return null;
    }
  }
}
