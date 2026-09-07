// 산책 중 한 손 기록의 규칙 — 이슈 #340.
//
// ## 왜 화면이 아니라 여기서 재나
//
// 트래킹 화면은 네이버 지도와 geolocator 를 물고 있어 위젯 테스트로 못 띄운다. 규칙이
// 그 안에 있었다면 "5초 안에 다시 누르면 취소" 를 재는 방법이 에뮬레이터에서 손으로
// 걸어 보는 것뿐이었다. `WalkMomentLog` 가 화면 밖에 있는 이유가 이 파일이다.
//
// 시각은 `tap` 이 인자로 받는다 — 안에서 `DateTime.now()` 를 불렀다면 이 테스트가 5초를
// 진짜로 기다리거나 가짜 시간을 써야 했다. 가짜 시간은 경합을 감춘다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/walk_moment.dart';

final _t0 = DateTime(2026, 9, 7, 19, 0, 0);

void main() {
  group('표기는 계약과 한 벌', () {
    test('세 종류의 wire 가 서버의 CareType 값과 같다', () {
      expect(
        [for (final k in WalkMomentKind.values) k.wire],
        ['poop', 'pee', 'water'],
        reason: '앱에서만 쓰는 이름을 지어내면 서버가 400 을 준다 — 물은 이미 있던 water 다',
      );
      expect(WalkMomentKind.tryParse('poop'), WalkMomentKind.poop);
      expect(WalkMomentKind.tryParse('POOP'), isNull, reason: '소문자 한 벌이다');
      expect(WalkMomentKind.tryParse(null), isNull);
    });
  });

  group('기록에 좌표가 없다 (A안 #235)', () {
    test('toJson 이 위도·경도를 안 싣는다 — 경로 위의 몇 번째 점만 든다', () {
      final json = const WalkMoment(kind: WalkMomentKind.poop, tSec: 90, pathIndex: 7).toJson();

      expect(json.keys, containsAll(<String>['kind', 'tSec', 'pathIndex']));
      expect(
        json.keys.where((k) => const ['lat', 'lng', 'latitude', 'longitude', 'point'].contains(k)),
        isEmpty,
        reason: '''
좌표가 사는 자리가 하나 늘면 그 자리는 언젠가 다른 경로로 새어 나간다. 위치는 이미
WalkDraft.path 에 있고 그 path 는 이 빌드에서 서버로 안 나간다.''',
      );
    });

    test('경로가 아직 없을 때 눌러도 기록은 남는다 — 횟수와 시각이 이 기능의 값이다', () {
      final log = WalkMomentLog();

      log.tap(WalkMomentKind.pee, tSec: 5, now: _t0);

      expect(log.moments.single.pathIndex, isNull);
      expect(log.tally[WalkMomentKind.pee], 1);
    });

    test('음수 인덱스는 없는 것으로 읽는다 — 깨진 초안이 그림을 엉뚱한 데 찍지 않게', () {
      final parsed = WalkMoment.tryParse({'kind': 'poop', 'tSec': 3, 'pathIndex': -2});

      expect(parsed!.pathIndex, isNull);
    });

    test('모르는 종류는 null — 옛 초안 하나가 큐 전체를 못 읽게 하면 안 된다', () {
      expect(WalkMoment.tryParse({'kind': 'grooming', 'tSec': 1}), isNull);
      expect(WalkMoment.tryParse('배변'), isNull);
    });
  });

  group('한 탭이 기록, 5초 안의 두 번째 탭이 취소', () {
    test('누르면 바로 기록이다 — 확인을 묻지 않는다', () {
      final log = WalkMomentLog();

      final result = log.tap(WalkMomentKind.poop, tSec: 60, now: _t0, pathIndex: 3);

      expect(result, WalkMomentTap.recorded);
      expect(log.moments.single.tSec, 60);
      expect(log.moments.single.pathIndex, 3);
    });

    test('5초 안에 같은 버튼을 다시 누르면 그 하나가 빠진다', () {
      final log = WalkMomentLog();
      log.tap(WalkMomentKind.poop, tSec: 60, now: _t0);

      final result = log.tap(
        WalkMomentKind.poop,
        tSec: 63,
        now: _t0.add(const Duration(seconds: 3)),
      );

      expect(result, WalkMomentTap.cancelled);
      expect(log.moments, isEmpty);
    });

    test('5초가 지나면 두 번째 탭은 두 번째 기록이다 — 배변은 하루에 여러 번이 정상이다', () {
      final log = WalkMomentLog();
      log.tap(WalkMomentKind.poop, tSec: 60, now: _t0);

      final result = log.tap(
        WalkMomentKind.poop,
        tSec: 200,
        now: _t0.add(const Duration(seconds: 6)),
      );

      expect(result, WalkMomentTap.recorded);
      expect(log.tally[WalkMomentKind.poop], 2);
    });

    test('다른 종류를 누르면 취소가 아니라 기록이다', () {
      final log = WalkMomentLog();
      log.tap(WalkMomentKind.poop, tSec: 60, now: _t0);

      final result = log.tap(
        WalkMomentKind.pee,
        tSec: 61,
        now: _t0.add(const Duration(seconds: 1)),
      );

      expect(result, WalkMomentTap.recorded);
      expect(log.tally[WalkMomentKind.poop], 1);
      expect(log.tally[WalkMomentKind.pee], 1);
    });

    test('취소한 뒤 곧바로 또 누르면 다시 기록이다 — 취소가 취소를 부르지 않는다', () {
      final log = WalkMomentLog();
      log.tap(WalkMomentKind.water, tSec: 10, now: _t0);
      log.tap(WalkMomentKind.water, tSec: 12, now: _t0.add(const Duration(seconds: 2)));

      final again = log.tap(
        WalkMomentKind.water,
        tSec: 13,
        now: _t0.add(const Duration(seconds: 3)),
      );

      expect(again, WalkMomentTap.recorded);
      expect(log.tally[WalkMomentKind.water], 1);
    });

    test('취소 창은 마지막 탭에서만 열린다', () {
      final log = WalkMomentLog();
      log.tap(WalkMomentKind.poop, tSec: 60, now: _t0);

      expect(log.undoableAt(_t0.add(const Duration(seconds: 4))), WalkMomentKind.poop);
      expect(log.undoableAt(_t0.add(const Duration(seconds: 5))), isNull);
    });

    test('이어 걷기로 살아난 것들은 취소 창을 열지 않는다', () {
      final log = WalkMomentLog()
        ..addAll(const [WalkMoment(kind: WalkMomentKind.poop, tSec: 30)]);

      expect(log.tally[WalkMomentKind.poop], 1);
      expect(
        log.undoableAt(_t0),
        isNull,
        reason: '앱이 죽었다 살아난 뒤에 "다시 누르면 취소" 가 떠 있으면 뜻이 없다',
      );
    });
  });

  group('요약 문장', () {
    test('센 것만 적는다 — 0회를 보여 주면 못 한 일처럼 읽힌다', () {
      final tally = WalkMomentTally.of(const [
        WalkMoment(kind: WalkMomentKind.poop, tSec: 10),
        WalkMoment(kind: WalkMomentKind.poop, tSec: 40),
        WalkMoment(kind: WalkMomentKind.water, tSec: 70),
      ]);

      expect(tally.summary, '배변 2회 · 물 1회');
      expect(tally.isEmpty, isFalse);
    });

    test('하나도 없으면 빈 문장이고 isEmpty 다 — 화면이 줄 자체를 안 그린다', () {
      const tally = WalkMomentTally({});

      expect(tally.summary, isEmpty);
      expect(tally.isEmpty, isTrue);
    });
  });
}
