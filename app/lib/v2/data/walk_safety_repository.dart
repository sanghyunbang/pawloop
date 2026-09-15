// 산책 안전 지수의 데이터 — 우리 서버가 기상청·에어코리아를 대신 부른다 (#336).
//
// 키는 앱에 없다(#40: 바이너리에 남고 폐기하려면 재배포). 앱이 보내는 것은 **5km 격자 번호(nx, ny)뿐**
// 이고, 요청에 인증도 없다 — 서버는 누구의 격자인지 모른다(A안 #235 와의 절충). 위경도는 어디에도
// 보내지 않는다. 그 사실은 위치기반서비스 이용약관 제3조 4)에 적혀 있다.
//
// 서버가 503 을 주면(기상청 실황 없음·서버에 키 없음) 카드가 없다 — 가짜를 보여 주지 않는다.
// 에어코리아가 승인 전이면 PM 이 비어 오고, 판정은 기온으로만 한다("미세먼지 정보 없음").
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../domain/pet.dart';
import 'walk_safety.dart';
import '../../core/net/net_timeouts.dart';

class WalkSafetyRepository {
  WalkSafetyRepository({http.Client? client, String? baseUrl, DateTime Function()? now})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? Env.apiBase,
        _now = now ?? DateTime.now;

  final http.Client _client;
  final String baseUrl;
  final DateTime Function() _now;

  /// 보통 요청과 같은 상한(#573). 전에는 8초였는데 **왜 8인지 적힌 곳이 없었다** —
  /// 그런 숫자는 다음 사람이 또 복사한다.
  static const Duration timeout = NetTimeouts.standard;

  /// 지금 값 한 묶음. 서버가 못 주면(503·연결 없음·깨진 본문) `null` — 카드 없음.
  ///
  /// <b>서버 실패에는 카드를 안 띄우기로 했다</b>(#515 에서 다시 본 자리). 사용자가 할 수
  /// 있는 것이 없기 때문이다 — 안전 지수는 곁가지고, 홈에는 이미 할 수 있는 일을 말하는
  /// 자리가 따로 있다(오늘의 케어의 "다시 시도", 그리고 #517 이 더한 "위치를 켜면 …").
  /// 연결이 없는 날마다 홈에 "지수를 못 받았어요" 한 줄이 더 늘면 그건 안내가 아니라 소음이다.
  ///
  /// <b>권한이 없어서 못 받은 것은 다르다</b> — 그건 사용자가 고칠 수 있으므로 카드가 말한다
  /// (`WalkSafetyCard._permissionRow`, #517). "할 수 있는 일이 있으면 말하고, 없으면 비운다"
  /// 가 이 카드의 규칙이다.
  Future<WalkSafetyReading?> fetch(double lat, double lng) async {
    final grid = kmaGrid(lat, lng);
    // 인증 헤더를 붙이지 않는다 — AuthedClient 가 아니라 맨 http 다. 누구의 격자인지 서버가 모른다.
    final uri = Uri.parse('$baseUrl/api/walk-safety/now').replace(queryParameters: {
      'nx': '${grid.nx}',
      'ny': '${grid.ny}',
    });
    http.Response res;
    try {
      res = await _client.get(uri, headers: const {'Accept': 'application/json'}).timeout(timeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[WalkSafety] 서버 호출 실패: $e');
      return null;
    }
    if (res.statusCode != 200) return null;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
    return parseWalkSafetyNow(json, fallbackAt: _now());
  }
}

/// 서버 `WalkSafetyNow`(openapi) → 관측값. `tempC` 가 없으면 `null` — 반쪽으로 판정하지 않는다.
WalkSafetyReading? parseWalkSafetyNow(Object? json, {required DateTime fallbackAt}) {
  if (json is! Map) return null;
  final temp = json['tempC'];
  if (temp is! num) return null;
  int? asInt(Object? v) => v is num ? v.round() : null;
  double? asDouble(Object? v) => v is num ? v.toDouble() : null;
  final station = json['station'];
  return WalkSafetyReading(
    tempC: temp.toDouble(),
    humidity: asInt(json['humidity']),
    rain1hMm: asDouble(json['rain1hMm']),
    precipType: asInt(json['precipType']),
    pm10: asInt(json['pm10']),
    pm25: asInt(json['pm25']),
    station: station is String && station.isNotEmpty ? station : null,
    observedAt: DateTime.tryParse('${json['observedAt']}')?.toLocal() ?? fallbackAt,
  );
}

/// 최근 판정 한 장 — 홈 카드와 산책 시작이 같이 본다. 30분 지나면 다시 받는다.
class WalkSafetyStore {
  WalkSafetyStore._();

  static final ValueNotifier<WalkSafetyVerdict?> latest = ValueNotifier<WalkSafetyVerdict?>(null);
  static WalkSafetyReading? reading;
  static DateTime? fetchedAt;
  static const Duration ttl = Duration(minutes: 30);
  static Future<void>? _inFlight;

  static bool isFresh(DateTime now) => fetchedAt != null && now.difference(fetchedAt!) < ttl;

  /// 위치가 있으면 받아서 판정한다. 이미 받는 중이면 그 결과를 기다린다.
  static Future<void> refresh({
    required WalkSafetyRepository repository,
    required Future<({double lat, double lng})?> Function() locate,
    DogProfile? dog,
    DateTime Function()? now,
    bool force = false,
  }) {
    final at = (now ?? DateTime.now)();
    if (!force && isFresh(at)) return Future.value();
    final pending = _inFlight;
    if (pending != null) return pending;
    final run = () async {
      try {
        final where = await locate();
        if (where == null) return;
        final r = await repository.fetch(where.lat, where.lng);
        if (r == null) return;
        reading = r;
        fetchedAt = at;
        latest.value = WalkSafety.judge(r, hour: at.hour, dog: dog);
      } finally {
        _inFlight = null;
      }
    }();
    _inFlight = run;
    return run;
  }

  /// 캐시를 비운다. 세션이 끝날 때([clearSessionTraces])와 테스트가 부른다 —
  /// 앞사람의 위치로 낸 판정이 다음 사람 홈 카드에 남으면 안 된다(#513).
  static void clear() {
    latest.value = null;
    reading = null;
    fetchedAt = null;
    _inFlight = null;
  }
}
