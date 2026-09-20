// 장소에서 출발해 돌아오는 추천 산책 코스 — 이슈 #725. 계약의 `PlaceLoop`.
//
// 서버가 OpenRouteService 를 대신 불러 한 번 받은 코스를 저장해 둔다 — 앱은 `contentId` 와
// 부탁하는 길이만 보낸다. 좌표는 **장소의 것**이라 누구의 위치도 아니고, 그래서 토큰 없이 부른다
// (`trail_route_repository.dart` 와 같은 길).
//
// 못 받으면 `null` 이다 — 키 없음 · 하루 한도 소진 · 바깥 실패(`available: false`) 와 404 · 5xx 를
// 한 답으로 뭉친다. 시트는 "지금은 추천 코스를 못 받아요" 한 줄만 적고 나머지(걷기 · 길찾기 · 글)는
// 그대로 둔다. 선은 덧이지 본문이 아니다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/net/net_timeouts.dart';

/// 추천 코스 하나. [lngLat] 은 `[경도, 위도]` — `TrailRoute.lngLat`·`startWalk(courseLine:)` 과 같은 순서.
class PlaceLoop {
  final String contentId;

  /// 부탁한 길이(m) — 서버가 500 단위로 맞춘 값.
  final int targetM;

  /// 실제 길이(m). 화면은 **이 값**을 적는다 — 2km 를 부탁했는데 2.1km 면 2.1km 라고.
  final int distanceM;

  /// 도보 예상 시간(초).
  final int durationS;

  final List<List<double>> lngLat;

  const PlaceLoop({
    required this.contentId,
    required this.targetM,
    required this.distanceM,
    required this.durationS,
    required this.lngLat,
  });

  /// "2.1km" · "800m".
  String get distanceLabel =>
      distanceM >= 1000 ? '${(distanceM / 1000).toStringAsFixed(1)}km' : '${distanceM}m';

  /// "약 28분".
  String get timeLabel => '약 ${(durationS / 60).round()}분';

  /// `available` 이 참이고 선이 두 점 이상일 때만. 아니면 `null` — 못 받은 것과 같은 답이다.
  static PlaceLoop? tryParse(Map<String, dynamic> j) {
    if (j['available'] != true) return null;
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
    if (points.length < 2) return null;
    final distance = _toInt(j['distanceM']);
    if (distance == null) return null;
    return PlaceLoop(
      contentId: '${j['contentId'] ?? ''}',
      targetM: _toInt(j['targetM']) ?? distance,
      distanceM: distance,
      durationS: _toInt(j['durationS']) ?? (distance / 1.25).round(),
      lngLat: points,
    );
  }

  static double? _toDouble(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

  static int? _toInt(Object? v) => v is num ? v.round() : int.tryParse('$v');
}

class PlaceLoopRepository {
  PlaceLoopRepository({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Env.apiBase;

  final http.Client _client;
  final String _baseUrl;

  /// 같은 장소·길이를 두 번 받지 않는다 — 칩을 왔다 갔다 하는 자리다. 못 받은 것은 기억하지
  /// 않는다(잠깐의 실패가 시트를 여는 내내 남으면 안 된다).
  final Map<String, PlaceLoop> _memory = {};

  /// 그 장소에서 출발해 돌아오는 코스. 못 받으면 `null`.
  Future<PlaceLoop?> fetch(String contentId, {required int lengthM}) async {
    final key = '$contentId:$lengthM';
    final cached = _memory[key];
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/api/places/${Uri.encodeComponent(contentId)}/loop')
        .replace(queryParameters: {'lengthM': '$lengthM'});
    try {
      final res = await _client.get(uri).timeout(NetTimeouts.standard);
      if (res.statusCode != 200) return null;
      // bodyBytes 에서 직접 디코딩한다 — res.body 는 charset 이 없으면 한글이 깨진다(#81).
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      final loop = PlaceLoop.tryParse(decoded.cast<String, dynamic>());
      if (loop != null) _memory[key] = loop;
      return loop;
    } catch (_) {
      return null;
    }
  }
}
