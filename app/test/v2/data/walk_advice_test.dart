// 산책 조언 — 규칙 표를 값으로 잠근다 (#669).
//
// 예전의 세 줄은 `const` 라 어떤 값을 넣어도 같은 말이 나왔다. 그래서 여기서는 문구가
// 아니라 **어떤 값에서 어떤 줄이 나오고 어떤 줄이 안 나오는지**를 잰다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/walk_advice.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

WalkSafetyReading _r({
  double temp = 20,
  int? humidity = 50,
  int? pm25,
  int? pm10,
  int? pty,
  double? rain,
}) =>
    WalkSafetyReading(
      tempC: temp,
      humidity: humidity,
      rain1hMm: rain,
      precipType: pty,
      pm10: pm10,
      pm25: pm25,
      observedAt: DateTime(2026, 9, 18, 14),
    );

const _mix = DogProfile(serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);
const _pug = DogProfile(serverId: 2, name: 'Pug', breed: '퍼그', size: DogSize.small, ageMonths: 30);
const _old = DogProfile(serverId: 3, name: 'Old', breed: '리트리버', size: DogSize.large, ageMonths: 100);
const _tiny = DogProfile(serverId: 4, name: 'Tiny', breed: '말티즈', size: DogSize.small, ageMonths: 40);

/// 강아지 말 넷 — 고양이 화면에 이 낱말이 나오면 #719 다. '견' 한 글자로 재면 "못 견뎌요" 에 걸린다.
const _dogWords = ['소형견', '중형견', '대형견', '노령견'];
bool _hasDogWord(Iterable<String> texts) => texts.any((t) => _dogWords.any(t.contains));

List<WalkAdviceKind> _kinds(
  WalkSafetyReading r, {
  required int hour,
  DogProfile? dog,
}) =>
    WalkAdvice.pick(r, hour: hour, dog: dog).map((a) => a.kind).toList();

void main() {
  group('더위', () {
    test('22°C · 미세먼지 좋음 · 가을 낮 → 할 말이 없다. 아스팔트 얘기가 안 나온다', () {
      final lines = WalkAdvice.pick(_r(temp: 22, pm25: 12), hour: 14, dog: _mix);
      expect(lines, isEmpty);
      expect(lines.map((a) => a.text).join(), isNot(contains('아스팔트')));
    });

    test('25°C 낮 → 바닥 7초 룰. 28°C 가 안 됐으니 시간대 얘기는 없다', () {
      expect(_kinds(_r(temp: 25), hour: 14, dog: _mix), [WalkAdviceKind.hotGround]);
    });

    test('30°C 낮 → 아스팔트와 시간대 둘 다', () {
      expect(_kinds(_r(temp: 30), hour: 13, dog: _mix),
          [WalkAdviceKind.hotGround, WalkAdviceKind.coolHours]);
    });

    test('같은 27°C 라도 밤 9시면 아스팔트 얘기가 없다 — 바닥이 식었다', () {
      expect(_kinds(_r(temp: 27), hour: 21, dog: _mix), isEmpty);
      expect(_kinds(_r(temp: 27), hour: 9, dog: _mix), isEmpty);
    });

    test('29°C 는 밤에도 시간대를 말한다 — 기온만 보는 줄이다', () {
      expect(_kinds(_r(temp: 29), hour: 21, dog: _mix), [WalkAdviceKind.coolHours]);
    });

    test('24.9°C 낮은 아직 아니다 — 경계는 25°C', () {
      expect(_kinds(_r(temp: 24.9), hour: 14, dog: _mix), isEmpty);
    });
  });

  group('추위', () {
    test('5°C 이하 → 짧게 · 발 닦기', () {
      expect(_kinds(_r(temp: 5), hour: 14, dog: _mix), [WalkAdviceKind.cold]);
      expect(_kinds(_r(temp: 6), hour: 14, dog: _mix), isEmpty);
    });

    test('0°C 이하 + 소형견 → 옷까지', () {
      expect(_kinds(_r(temp: -1), hour: 14, dog: _tiny),
          [WalkAdviceKind.cold, WalkAdviceKind.coat]);
    });

    test('0°C 이하라도 중형견이면 옷 얘기가 없다 — 남 얘기다', () {
      expect(_kinds(_r(temp: -1), hour: 14, dog: _mix), [WalkAdviceKind.cold]);
    });

    test('아이를 모르면 옷 얘기가 없다', () {
      expect(_kinds(_r(temp: -1), hour: 14), [WalkAdviceKind.cold]);
    });

    test('고양이도 옷 얘기는 나오되 문장에 "견" 이 없다 (#719)', () {
      const kitten = DogProfile(
          serverId: 5, name: 'Nabi', breed: '코숏', size: DogSize.small, ageMonths: 40, species: PetSpecies.cat);
      final lines = WalkAdvice.pick(_r(temp: -1), hour: 14, dog: kitten);
      expect(lines.map((l) => l.kind), [WalkAdviceKind.cold, WalkAdviceKind.coat]);
      expect(_hasDogWord(lines.map((l) => l.text)), isFalse, reason: lines.map((l) => l.text).join(' / '));
    });
  });

  group('미세먼지 — 판정과 같은 경계를 본다', () {
    test('PM2.5 36~75 → 짧게 · 발과 털 닦기', () {
      expect(_kinds(_r(pm25: WalkSafety.pm25Moderate + 1), hour: 14, dog: _mix),
          [WalkAdviceKind.dust]);
      expect(_kinds(_r(pm25: WalkSafety.pm25Moderate), hour: 14, dog: _mix), isEmpty);
    });

    test('PM2.5 80 → 실내 놀이. "짧게" 는 같이 안 나온다 — 두 줄이 어긋난다', () {
      expect(_kinds(_r(pm25: 80), hour: 14, dog: _mix), [WalkAdviceKind.indoorPlay]);
    });

    test('PM10 만 와도 같은 경계로 본다', () {
      expect(_kinds(_r(pm10: 100), hour: 14, dog: _mix), [WalkAdviceKind.dust]);
      expect(_kinds(_r(pm10: 200), hour: 14, dog: _mix), [WalkAdviceKind.indoorPlay]);
      expect(_kinds(_r(pm10: 50), hour: 14, dog: _mix), isEmpty);
    });

    test('미세먼지 값이 없으면 먼지 얘기를 안 한다 — 모르는 것으로 겁주지 않는다', () {
      expect(_kinds(_r(), hour: 14, dog: _mix), isEmpty);
    });
  });

  group('비 · 습도', () {
    test('비가 오면 미끄러움 · 발 말리기', () {
      expect(_kinds(_r(pty: 1), hour: 14, dog: _mix), [WalkAdviceKind.rain]);
      expect(_kinds(_r(rain: 0.4), hour: 14, dog: _mix), [WalkAdviceKind.rain]);
    });

    test('습도 80% 는 더울 때만 말한다 — 20°C 에 습하다고 해 봐야 할 일이 없다', () {
      expect(_kinds(_r(temp: 26, humidity: 85), hour: 14, dog: _mix),
          [WalkAdviceKind.hotGround, WalkAdviceKind.humid]);
      expect(_kinds(_r(temp: 20, humidity: 85), hour: 14, dog: _mix), isEmpty);
    });

    test('습도를 못 받았으면 습도 얘기가 없다', () {
      expect(_kinds(_r(temp: 26, humidity: null), hour: 14, dog: _mix), [WalkAdviceKind.hotGround]);
    });
  });

  group('우리 아이', () {
    test('단두종이고 더울 때만 단두종 얘기', () {
      expect(_kinds(_r(temp: 26), hour: 14, dog: _pug),
          [WalkAdviceKind.hotGround, WalkAdviceKind.brachy]);
      expect(_kinds(_r(temp: 20), hour: 14, dog: _pug), isEmpty);
    });

    test('우리 아이가 단두종이 아니면 단두종 얘기가 안 나온다', () {
      expect(_kinds(_r(temp: 26), hour: 14, dog: _mix), [WalkAdviceKind.hotGround]);
      expect(_kinds(_r(temp: 26), hour: 14), [WalkAdviceKind.hotGround]);
    });

    test('노령견은 더위와 추위 양쪽에서 — 20°C 에는 안 나온다', () {
      expect(_kinds(_r(temp: 26), hour: 14, dog: _old),
          [WalkAdviceKind.hotGround, WalkAdviceKind.senior]);
      expect(_kinds(_r(temp: 3), hour: 14, dog: _old), [WalkAdviceKind.cold, WalkAdviceKind.senior]);
      expect(_kinds(_r(temp: 20), hour: 14, dog: _old), isEmpty);
    });

    test('나이 든 고양이의 문장에도 "견" 이 없다 (#719)', () {
      const oldCat = DogProfile(
          serverId: 6, name: 'Old', breed: '코숏', size: DogSize.medium, ageMonths: 100, species: PetSpecies.cat);
      final lines = WalkAdvice.pick(_r(temp: 26), hour: 14, dog: oldCat);
      expect(lines.map((l) => l.kind), contains(WalkAdviceKind.senior));
      expect(_hasDogWord(lines.map((l) => l.text)), isFalse, reason: lines.map((l) => l.text).join(' / '));
    });
  });

  group('최대 세 줄', () {
    test('다 해당해도 셋만 — 급한 순서로 앞에서 자른다', () {
      const pug7 =
          DogProfile(serverId: 9, name: 'Pug', breed: '퍼그', size: DogSize.small, ageMonths: 100);
      final lines = WalkAdvice.pick(
        _r(temp: 31, humidity: 90, pm25: 120, pty: 1),
        hour: 14,
        dog: pug7,
      );
      expect(lines.length, 3);
      expect(lines.map((a) => a.kind).toList(),
          [WalkAdviceKind.indoorPlay, WalkAdviceKind.hotGround, WalkAdviceKind.coolHours]);
      expect(lines.length, lessThanOrEqualTo(WalkAdvice.maxLines));
    });
  });
}
