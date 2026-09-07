// 산책 안전 지수 데이터 — 우리 서버에 격자 번호만, 인증 없이 (#336).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_safety.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

const _base = 'https://api.example.test';

http.Response _json(Object body, {int status = 200}) => http.Response(jsonEncode(body), status,
    headers: const {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _now({double temp = 26.2, Object? pm25 = 18, Object? pm10 = 31, Object? station = '성수'}) => {
      'tempC': temp,
      'humidity': 49,
      'rain1hMm': 0.0,
      'precipType': 0,
      'pm10': pm10,
      'pm25': pm25,
      'station': station,
      'observedAt': '2026-09-07T05:10:00Z',
    };

({WalkSafetyRepository repo, List<http.Request> calls}) fixture(Future<http.Response> Function(http.Request) handler) {
  final calls = <http.Request>[];
  final client = MockClient((req) async {
    calls.add(req);
    return handler(req);
  });
  return (
    repo: WalkSafetyRepository(client: client, baseUrl: _base, now: () => DateTime(2026, 9, 7, 14, 10)),
    calls: calls,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyStore.resetForTest();
  });

  test('우리 서버에 5km 격자 번호만 보낸다 — 위경도도 인증 헤더도 없다', () async {
    final f = fixture((_) async => _json(_now()));
    final r = await f.repo.fetch(37.5445, 127.0410);

    expect(r, isNotNull);
    expect(r!.tempC, 26.2);
    expect(r.pm25, 18);
    expect(r.station, '성수');
    final req = f.calls.single;
    expect(req.url.toString(), startsWith('$_base/api/walk-safety/now'));
    expect(req.url.queryParameters, {'nx': '61', 'ny': '126'});
    expect(req.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')),
        reason: '누구의 격자인지 서버가 모르게 둔다');
    expect(req.url.toString(), isNot(contains('37.5')));
    expect(req.url.toString(), isNot(contains('127.0')));
  });

  test('서버 응답 파싱 — PM 이 null 이면 그대로 없음, tempC 가 없으면 전체가 null', () {
    final r = parseWalkSafetyNow(_now(pm25: null, pm10: null, station: null), fallbackAt: DateTime(2026, 9, 7))!;
    expect(r.pm25, isNull);
    expect(r.pm10, isNull);
    expect(r.station, isNull);
    expect(WalkSafety.judge(r, hour: 14).reasons, contains('미세먼지 정보 없음'));
    expect(parseWalkSafetyNow({'humidity': 49}, fallbackAt: DateTime(2026, 9, 7)), isNull);
    expect(parseWalkSafetyNow({'error': {}}, fallbackAt: DateTime(2026, 9, 7)), isNull);
  });

  test('503(기상청 없음)·연결 실패·깨진 본문이면 null — 카드가 없다', () async {
    expect(await fixture((_) async => _json({'error': {'code': 'UPSTREAM'}}, status: 503)).repo.fetch(37.5, 127.0), isNull);
    expect(await fixture((_) async => throw http.ClientException('끊김')).repo.fetch(37.5, 127.0), isNull);
    expect(await fixture((_) async => http.Response('<html>', 200)).repo.fetch(37.5, 127.0), isNull);
  });

  group('WalkSafetyStore', () {
    const dog = DogProfile(serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);

    test('받아서 판정하고, 30분 안에는 다시 받지 않는다', () async {
      final f = fixture((_) async => _json(_now(temp: 31)));
      var located = 0;
      Future<({double lat, double lng})?> locate() async {
        located++;
        return (lat: 37.5445, lng: 127.0410);
      }

      await WalkSafetyStore.refresh(repository: f.repo, locate: locate, dog: dog, now: () => DateTime(2026, 9, 7, 14));
      expect(WalkSafetyStore.latest.value!.level, WalkSafetyLevel.avoid);
      expect(WalkSafetyStore.isFresh(DateTime(2026, 9, 7, 14, 20)), isTrue);

      await WalkSafetyStore.refresh(repository: f.repo, locate: locate, dog: dog, now: () => DateTime(2026, 9, 7, 14, 20));
      expect(located, 1, reason: '캐시가 살아 있으면 위치도 다시 안 묻는다');

      await WalkSafetyStore.refresh(repository: f.repo, locate: locate, dog: dog, now: () => DateTime(2026, 9, 7, 14, 50));
      expect(located, 2);
    });

    test('위치가 없으면(게스트·권한 없음) 아무것도 부르지 않는다', () async {
      final f = fixture((_) async => _json(_now()));
      await WalkSafetyStore.refresh(repository: f.repo, locate: () async => null, now: () => DateTime(2026, 9, 7, 14));
      expect(WalkSafetyStore.latest.value, isNull);
      expect(f.calls, isEmpty);
    });
  });
}
