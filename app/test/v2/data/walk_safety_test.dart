// 산책 안전 지수 — 판정 규칙 · 격자 변환 · 응답 파싱 (#336).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/walk_safety.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

WalkSafetyReading _r({double temp = 20, int? pm25, int? pm10, int? pty, double? rain, String? station}) =>
    WalkSafetyReading(
      tempC: temp,
      humidity: 50,
      rain1hMm: rain,
      precipType: pty,
      pm10: pm10,
      pm25: pm25,
      station: station,
      observedAt: DateTime(2026, 9, 7, 14),
    );

const _mix = DogProfile(serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);
const _pug = DogProfile(serverId: 2, name: 'Pug', breed: '퍼그', size: DogSize.small, ageMonths: 30);
const _old = DogProfile(serverId: 3, name: 'Old', breed: '리트리버', size: DogSize.large, ageMonths: 100);
const _big = DogProfile(serverId: 4, name: 'Big', breed: '리트리버', size: DogSize.large, ageMonths: 40);
const _tiny = DogProfile(serverId: 5, name: 'Tiny', breed: '말티즈', size: DogSize.small, ageMonths: 40);

void main() {
  group('판정 — 초안 수치표', () {
    test('5~24°C · PM2.5 ≤ 35 · 비 없음 → 좋아요', () {
      final v = WalkSafety.judge(_r(temp: 22, pm25: 20), hour: 14, dog: _mix);
      expect(v.level, WalkSafetyLevel.good);
      expect(v.headline, '지금 나가기 좋아요');
      expect(v.reasons, ['22°C', '미세먼지 보통']);
    });

    test('25~29°C 낮 시간 → 짧게 · 7초 룰', () {
      final v = WalkSafety.judge(_r(temp: 27, pm25: 10), hour: 15, dog: _mix);
      expect(v.level, WalkSafetyLevel.short);
      expect(v.headline, contains('7초 룰'));
    });

    test('27°C 라도 저녁 8시면 좋아요 — 같은 기온, 다른 시간', () {
      expect(WalkSafety.judge(_r(temp: 27, pm25: 10), hour: 20, dog: _mix).level, WalkSafetyLevel.good);
    });

    test('PM2.5 36~75 → 짧게', () {
      expect(WalkSafety.judge(_r(temp: 20, pm25: 50), hour: 14, dog: _mix).level, WalkSafetyLevel.short);
    });

    test('30°C 낮 시간 → 피하세요 · 저녁 7시 뒤에', () {
      final v = WalkSafety.judge(_r(temp: 31, pm25: 10), hour: 13, dog: _mix);
      expect(v.level, WalkSafetyLevel.avoid);
      expect(v.headline, '지금은 피하고 저녁 7시 뒤에');
      expect(v.shouldAskBeforeWalk, isTrue);
    });

    test('PM2.5 > 75 → 피하세요 · 미세먼지', () {
      final v = WalkSafety.judge(_r(temp: 20, pm25: 90, station: '성수'), hour: 14, dog: _mix);
      expect(v.level, WalkSafetyLevel.avoid);
      expect(v.headline, '지금은 피하세요 · 미세먼지가 나빠요');
      expect(v.reasons, contains('미세먼지 매우나쁨(성수)'));
    });

    test('-5°C 이하 → 추워요, 소형견은 0°C 부터', () {
      expect(WalkSafety.judge(_r(temp: -6, pm25: 10), hour: 14, dog: _mix).level, WalkSafetyLevel.cold);
      expect(WalkSafety.judge(_r(temp: -1, pm25: 10), hour: 14, dog: _tiny).level, WalkSafetyLevel.cold);
      expect(WalkSafety.judge(_r(temp: -1, pm25: 10), hour: 14, dog: _mix).level, WalkSafetyLevel.good);
    });

    test('비가 오면 좋아요 대신 짧게 — 근거에 "비"', () {
      final v = WalkSafety.judge(_r(temp: 20, pm25: 10, pty: 1), hour: 14, dog: _mix);
      expect(v.level, WalkSafetyLevel.short);
      expect(v.headline, '짧게 다녀오세요 · 비가 와요');
      expect(v.reasons, contains('비'));
    });

    test('미세먼지를 못 받으면 기온만으로 판정하고 "못 받았어요" 라고 적는다 — 없는 값으로 좋다고 하지 않는다', () {
      final v = WalkSafety.judge(_r(temp: 20), hour: 14, dog: _mix);
      expect(v.level, WalkSafetyLevel.good);
      expect(v.reasons, contains('미세먼지는 못 받았어요'));
    });

    test('"정보 없음" 이라고 말하지 않는다 — 공기는 늘 있고 우리가 못 잰 것이다 (#668)', () {
      // 서버가 에어코리아를 한 번 못 부르면 PM 이 비어 온다. 그때 "정보 없음" 은 값이 0 이거나
      // 공기가 깨끗하다는 뜻으로도 읽힌다 — 못 받은 것과 없는 것을 뭉개는 말이다(#515).
      final v = WalkSafety.judge(_r(temp: 20), hour: 14, dog: _mix);
      expect(v.reasons.join(' '), isNot(contains('정보 없음')));
      expect(v.reasons.join(' '), contains('못 받'));
    });
  });

  group('보정', () {
    test('단두종은 더위에 한 단계 보수적 — 27°C 낮이면 피하세요', () {
      final v = WalkSafety.judge(_r(temp: 27, pm25: 10), hour: 14, dog: _pug);
      expect(v.level, WalkSafetyLevel.avoid);
      expect(v.reasons, contains('단두종'));
    });

    test('노령견(84개월 이상)도 한 단계 보수적', () {
      final v = WalkSafety.judge(_r(temp: 27, pm25: 10), hour: 14, dog: _old);
      expect(v.level, WalkSafetyLevel.avoid);
      expect(v.reasons, contains('노령견'));
    });

    test('대형견은 28°C 낮부터 피하세요, 27°C 는 짧게', () {
      expect(WalkSafety.judge(_r(temp: 28, pm25: 10), hour: 14, dog: _big).level, WalkSafetyLevel.avoid);
      expect(WalkSafety.judge(_r(temp: 27, pm25: 10), hour: 14, dog: _big).level, WalkSafetyLevel.short);
    });

    test('아이가 없어도 판정한다 — 보정 없이', () {
      expect(WalkSafety.judge(_r(temp: 27, pm25: 10), hour: 14).level, WalkSafetyLevel.short);
    });

    test('단두종 판정 — 한글·영문 품종 문자열', () {
      expect(WalkSafety.isBrachycephalic('프렌치 불독'), isTrue);
      expect(WalkSafety.isBrachycephalic('Shih Tzu'), isTrue);
      expect(WalkSafety.isBrachycephalic('골든 리트리버'), isFalse);
    });
  });

  group('격자 변환 — 기상청 상수 그대로', () {
    test('서울시청 → (60, 127)', () {
      expect(kmaGrid(37.5665, 126.9780), (nx: 60, ny: 127));
    });
    test('부산 중구 → (98, 76)', () {
      expect(kmaGrid(35.1796, 129.0756), (nx: 98, ny: 76));
    });
    test('서울숲(성수) → (61, 126)', () {
      expect(kmaGrid(37.5445, 127.0410), (nx: 61, ny: 126));
    });
  });

  group('등급', () {
    test('등급 라벨 — PM2.5 우선, 없으면 PM10', () {
      expect(WalkSafety.pmLabel(10, null), '좋음');
      expect(WalkSafety.pmLabel(35, null), '보통');
      expect(WalkSafety.pmLabel(36, null), '나쁨');
      expect(WalkSafety.pmLabel(76, null), '매우나쁨');
      expect(WalkSafety.pmLabel(null, 81), '나쁨');
      // 둘 다 없으면 등급이 아니라 "못 받음" 이다 — "정보 없음" 은 0 이나 좋음으로도 읽힌다(#668).
      expect(WalkSafety.pmLabel(null, null), '못 받음');
    });
  });
}
