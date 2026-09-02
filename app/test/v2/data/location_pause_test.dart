// '위치 정보 수집 일시 중단' 이 실제로 중단하는가.
//
// 이 토글은 위치정보법 제24조의 이용중지 요구권을 화면으로 만든 것이다. 그런데 두
// 군데가 새고 있었다.
//
//  1. 값이 메모리 `ValueNotifier` 에만 있었다 — 앱을 껐다 켜면 중단이 풀렸다.
//     사용자는 껐다고 믿는 채로 다시 켜진 앱을 썼다.
//  2. `LocationService` 가 저장소에 둘인데, 레거시(감정 지도·둘러보기·포유) 쪽은
//     이 토글을 아예 보지 않았다. 켜도 절반만 들었다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/features/foryou_v2/state/location_service.dart'
    as legacy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocationService.paused.value = false;
    // 동의가 기본 false 라 켜 주지 않으면 전부 notConsented 로 막힌다 — 이 파일이
    // 재려는 것은 '일시중지' 라서 그 앞의 관문을 열어 둔다. (#180)
    LocationService.consented.value = true;
  });

  tearDown(() => LocationService.consented.value = false);

  group('껐다 켜도 남는다', () {
    test('중단하면 디스크에 남는다', () async {
      expect(await LocationService.setPaused(true), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LocationService.pausedKey), isTrue);
    });

    test('앱을 다시 켠 것처럼 복원하면 중단 상태로 돌아온다', () async {
      await LocationService.setPaused(true);

      // 재시작 = 메모리는 초기값, 디스크는 그대로.
      LocationService.paused.value = false;
      await LocationService.restorePaused();

      expect(LocationService.paused.value, isTrue,
          reason: '이게 거짓이면 사용자는 껐다고 믿는데 앱은 켜져 있다');
    });

    test('한 번도 안 건드렸으면 중단이 아니다', () async {
      await LocationService.restorePaused();
      expect(LocationService.paused.value, isFalse);
    });

    test('다시 시작하면 그것도 남는다', () async {
      await LocationService.setPaused(true);
      await LocationService.setPaused(false);

      LocationService.paused.value = true;
      await LocationService.restorePaused();

      expect(LocationService.paused.value, isFalse);
    });
  });

  group('중단 중에는 좌표를 안 준다', () {
    test('정본 서비스가 Geolocator 를 건드리지 않는다', () async {
      await LocationService.setPaused(true);

      // 테스트 환경에는 플랫폼 채널이 없다. 여기서 Geolocator 로 내려가면
      // MissingPluginException 이 난다 — 안 난다는 것이 곧 단락 증거다.
      final fix = await LocationService.locate();
      expect(fix.denial, LocationDenial.pausedByUser,
          reason: '동의는 켜 두었으므로 여기서 걸리는 것은 일시중지여야 한다');
    });

    test('레거시 서비스도 토글을 듣는다', () async {
      await LocationService.setPaused(true);

      final (lat, lng) = await legacy.LocationService().getCurrentLatLng();

      expect(lat, isNull);
      expect(lng, isNull);
    });
  });
}
