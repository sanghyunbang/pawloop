// 산책 안전 지수 데이터 — 기상청·에어코리아를 기기에서 부르고, 좌표는 어디에도 안 보낸다 (#336).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_safety.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: const {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _kma({String temp = '26.2', String pty = '0'}) => {
      'response': {
        'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
        'body': {
          'items': {
            'item': [
              {'category': 'PTY', 'obsrValue': pty},
              {'category': 'REH', 'obsrValue': '49'},
              {'category': 'RN1', 'obsrValue': '0'},
              {'category': 'T1H', 'obsrValue': temp},
            ]
          }
        }
      }
    };

const _keyError = {
  'OpenAPI_ServiceResponse': {
    'cmmMsgHeader': {'errMsg': 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR', 'returnReasonCode': '30'}
  }
};

({WalkSafetyRepository repo, List<Uri> calls}) fixture({
  Object? kma,
  Object? stations,
  Object? air,
  String key = 'KEY',
}) {
  final calls = <Uri>[];
  final client = MockClient((req) async {
    calls.add(req.url);
    final p = req.url.path;
    if (p.contains('getUltraSrtNcst')) return _json(kma ?? _kma());
    if (p.contains('getMsrstnList')) return _json(stations ?? _keyError);
    if (p.contains('getMsrstnAcctntRltmMesureDnsty')) return _json(air ?? _keyError);
    return http.Response('not found', 404);
  });
  return (
    repo: WalkSafetyRepository(client: client, serviceKey: key, now: () => DateTime(2026, 9, 7, 14, 10)),
    calls: calls,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyRepository.resetForTest();
    WalkSafetyStore.resetForTest();
  });

  test('기상청 기준 시각 — 매시 40분에 나오는 실황이라 40분 전을 시 단위로 내린다(KST)', () {
    expect(WalkSafetyRepository.kmaBase(DateTime.utc(2026, 9, 7, 5, 10)), (date: '20260907', time: '1300'));
    expect(WalkSafetyRepository.kmaBase(DateTime.utc(2026, 9, 7, 5, 45)), (date: '20260907', time: '1400'));
    expect(WalkSafetyRepository.kmaBase(DateTime.utc(2026, 9, 6, 15, 20)), (date: '20260906', time: '2300'),
        reason: '00:20 KST 에는 00:00 실황이 아직 없다(00:40 에 나온다) — 전날 23:00 실황을 쓴다');
  });

  test('키가 없으면 아무것도 부르지 않는다', () async {
    final f = fixture(key: '');
    expect(await f.repo.fetch(37.5445, 127.0410), isNull);
    expect(f.calls, isEmpty);
  });

  test('기상청은 5km 격자 번호로 부른다 — 위경도가 요청에 없다', () async {
    final f = fixture();
    final r = await f.repo.fetch(37.5445, 127.0410);

    expect(r, isNotNull);
    expect(r!.tempC, 26.2);
    final kma = f.calls.firstWhere((u) => u.path.contains('getUltraSrtNcst'));
    expect(kma.host, 'apis.data.go.kr');
    expect(kma.queryParameters['nx'], '61');
    expect(kma.queryParameters['ny'], '126');
    expect(kma.queryParameters['base_date'], '20260907');
    expect(kma.queryParameters['base_time'], '1300');
    expect(kma.queryParameters['serviceKey'], 'KEY');
    for (final u in f.calls) {
      expect(u.toString(), isNot(contains('37.5')), reason: '좌표가 그대로 나가면 안 된다');
      expect(u.toString(), isNot(contains('127.0')));
    }
  });

  test('에어코리아가 승인 전(등록되지 않은 키)이면 PM 없이 돌아온다 — 카드는 기온으로 판정한다', () async {
    final f = fixture();
    final r = (await f.repo.fetch(37.5445, 127.0410))!;
    expect(r.pm25, isNull);
    expect(r.pm10, isNull);
    expect(r.station, isNull);
    expect(WalkSafety.judge(r, hour: 14).reasons, contains('미세먼지 정보 없음'));
  });

  test('에어코리아가 되면 가장 가까운 측정소 이름으로 부르고 PM 이 붙는다 · 목록은 캐시된다', () async {
    final stations = {
      'response': {
        'body': {
          'items': [
            {'stationName': '성수', 'dmX': '37.5449', 'dmY': '127.0436'},
            {'stationName': '중구', 'dmX': '37.5642', 'dmY': '126.9748'},
          ]
        }
      }
    };
    final air = {
      'response': {
        'body': {
          'items': [
            {'stationName': '성수', 'dataTime': '2026-09-07 14:00', 'pm10Value': '31', 'pm25Value': '18'}
          ]
        }
      }
    };
    final f = fixture(stations: stations, air: air);
    final r = (await f.repo.fetch(37.5445, 127.0410))!;

    expect(r.pm25, 18);
    expect(r.pm10, 31);
    expect(r.station, '성수');
    final airCall = f.calls.firstWhere((u) => u.path.contains('getMsrstnAcctntRltmMesureDnsty'));
    expect(airCall.queryParameters['stationName'], '성수');

    // 두 번째 호출은 측정소 목록을 다시 받지 않는다.
    await f.repo.fetch(37.5665, 126.9780);
    expect(f.calls.where((u) => u.path.contains('getMsrstnList')).length, 1);
    expect((await SharedPreferences.getInstance()).getString(WalkSafetyRepository.stationsKey), isNotNull);
  });

  test('기상청이 실패하면 전체가 null — 반쪽으로 판정하지 않는다', () async {
    final f = fixture(kma: _keyError);
    expect(await f.repo.fetch(37.5445, 127.0410), isNull);
  });

  group('WalkSafetyStore', () {
    const dog = DogProfile(serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);

    test('받아서 판정하고, 30분 안에는 다시 받지 않는다', () async {
      final f = fixture(kma: _kma(temp: '31'));
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

    test('위치가 없으면(게스트·권한 없음) 아무것도 없다', () async {
      final f = fixture();
      await WalkSafetyStore.refresh(repository: f.repo, locate: () async => null, now: () => DateTime(2026, 9, 7, 14));
      expect(WalkSafetyStore.latest.value, isNull);
      expect(f.calls, isEmpty);
    });
  });
}
