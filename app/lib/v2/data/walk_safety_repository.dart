// 산책 안전 지수의 데이터 — 기상청·에어코리아를 **기기에서 직접** 부른다 (#336).
//
// 좌표는 회사 서버로 가지 않는다(A안, #235). 기상청에는 5km 격자 번호(nx, ny)가, 에어코리아에는
// 가장 가까운 측정소 **이름**이 간다 — 위경도 자체는 어느 쪽에도 보내지 않는다. 그 사실은
// 위치기반서비스 이용약관 제3조 4)에 적혀 있다.
//
// 키(`Env.publicDataServiceKey`)가 없으면 아무것도 부르지 않는다 — 가짜 카드를 보여 주지 않는다.
// 에어코리아 두 API 는 공공데이터포털에서 따로 활용신청해야 한다. 승인 전에는 응답이
// "등록되지 않은 서비스키" 라 PM 이 비어 오고, 판정은 기온으로만 한다("미세먼지 정보 없음").
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../domain/pet.dart';
import 'walk_safety.dart';

class WalkSafetyRepository {
  WalkSafetyRepository({http.Client? client, String? serviceKey, DateTime Function()? now})
      : _client = client ?? http.Client(),
        serviceKey = serviceKey ?? Env.publicDataServiceKey,
        _now = now ?? DateTime.now;

  final http.Client _client;
  final String serviceKey;
  final DateTime Function() _now;

  static const String stationsKey = 'air_stations_v1';
  static const Duration stationsTtl = Duration(hours: 24);
  static const Duration timeout = Duration(seconds: 8);

  /// 메모리 캐시 — 앱을 켠 동안 측정소 목록은 한 번만 받는다.
  static List<AirStation>? _stations;

  bool get enabled => serviceKey.isNotEmpty;

  /// 지금 값 한 묶음. 기상청이 실패하면 `null`(카드 없음). 에어코리아는 있으면 붙고 없으면 빈다.
  Future<WalkSafetyReading?> fetch(double lat, double lng) async {
    if (!enabled) return null;
    final weather = await _kma(lat, lng);
    if (weather == null) return null;
    final air = await _air(lat, lng);
    return WalkSafetyReading(
      tempC: weather.tempC,
      humidity: weather.humidity,
      rain1hMm: weather.rain1hMm,
      precipType: weather.precipType,
      pm10: air?.pm10,
      pm25: air?.pm25,
      station: air?.station,
      observedAt: _now(),
    );
  }

  /// 초단기실황의 기준 시각. 매시 40분에 그 시각(HH00) 실황이 나온다 — 40분 전을 시 단위로 내린다.
  /// 기상청 시각은 KST 다.
  static ({String date, String time}) kmaBase(DateTime now) {
    final kst = now.toUtc().add(const Duration(hours: 9)).subtract(const Duration(minutes: 40));
    String two(int v) => v.toString().padLeft(2, '0');
    return (date: '${kst.year}${two(kst.month)}${two(kst.day)}', time: '${two(kst.hour)}00');
  }

  Future<({double tempC, int? humidity, double? rain1hMm, int? precipType})?> _kma(double lat, double lng) async {
    final grid = kmaGrid(lat, lng);
    final base = kmaBase(_now());
    final uri = Uri.https('apis.data.go.kr', '/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst', {
      'serviceKey': serviceKey,
      'pageNo': '1',
      'numOfRows': '10',
      'dataType': 'JSON',
      'base_date': base.date,
      'base_time': base.time,
      'nx': '${grid.nx}',
      'ny': '${grid.ny}',
    });
    final json = await _getJson(uri);
    return parseKmaNowcast(json);
  }

  Future<({int? pm10, int? pm25, String station})?> _air(double lat, double lng) async {
    final stations = await _loadStations();
    final near = nearestStation(stations, lat, lng);
    if (near == null) return null;
    final uri = Uri.https('apis.data.go.kr', '/B552584/ArpltnInforInqireSvc/getMsrstnAcctntRltmMesureDnsty', {
      'serviceKey': serviceKey,
      'returnType': 'json',
      'numOfRows': '1',
      'pageNo': '1',
      'stationName': near.name,
      'dataTerm': 'DAILY',
      'ver': '1.3',
    });
    final q = parseAirQuality(await _getJson(uri));
    if (q == null) return null;
    return (pm10: q.pm10, pm25: q.pm25, station: near.name);
  }

  Future<List<AirStation>> _loadStations() async {
    final cached = _stations;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(stationsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['at'] is String) {
          final at = DateTime.tryParse(decoded['at'] as String);
          if (at != null && _now().difference(at) < stationsTtl) {
            final list = parseAirStations({'response': {'body': {'items': decoded['items']}}});
            if (list.isNotEmpty) return _stations = list;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WalkSafety] 측정소 캐시를 못 읽었다: $e');
    }
    final uri = Uri.https('apis.data.go.kr', '/B552584/MsrstnInfoInqireSvc/getMsrstnList', {
      'serviceKey': serviceKey,
      'returnType': 'json',
      'numOfRows': '1000',
      'pageNo': '1',
    });
    final json = await _getJson(uri);
    final list = parseAirStations(json);
    if (list.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = (json as Map)['response']['body']['items'];
      await prefs.setString(stationsKey, jsonEncode({'at': _now().toIso8601String(), 'items': items}));
    } catch (e) {
      if (kDebugMode) debugPrint('[WalkSafety] 측정소 캐시를 못 남겼다: $e');
    }
    return _stations = list;
  }

  Future<Object?> _getJson(Uri uri) async {
    try {
      final res = await _client.get(uri, headers: const {'Accept': 'application/json'}).timeout(timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (e) {
      if (kDebugMode) debugPrint('[WalkSafety] ${uri.path} 실패: $e');
      return null;
    }
  }

  static void resetForTest() => _stations = null;
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

  /// 위치가 있고 키가 있으면 받아서 판정한다. 이미 받는 중이면 그 결과를 기다린다.
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
        if (!repository.enabled) return;
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

  static void resetForTest() {
    latest.value = null;
    reading = null;
    fetchedAt = null;
    _inFlight = null;
  }
}
