// 산책 조언 — 오늘 이 값에서 나오는 말만 (#669).
//
// 예전에는 안전 지수 시트에 조언 세 줄이 `const` 로 박혀 있었다. 그래서 2026-09-18 서울
// 22°C · 미세먼지 좋음 인데도 "아스팔트는 기온보다 최대 33°C 뜨거워요" 가 떴다.
// 판정([WalkSafety.judge])은 기온·습도·비·미세먼지·시각·견종을 제대로 보는데
// **그 판정이 조언에는 하나도 안 닿았다.**
//
// 그래서 같은 재료로 조언을 고르는 **순수 함수** 하나다. 네트워크도 상태도 없다 —
// 같은 값이면 같은 답이라 캐시할 것이 없고, 규칙 표를 통째로 테스트로 잠글 수 있다.
//
// 모델(LLM)은 안 쓴다. 운영의 `OPENAI_API_KEY` 가 비어 있기도 하지만, 그보다
// **지어낸 숫자가 아이를 다치게 한다** — 주간 요약에 `InsightNumberGuard` 가 있는 이유다.
// "40°C 까지 괜찮아요" 같은 문장은 검증할 방법이 없다. 나중에 모델을 쓰더라도 여기서
// 고른 줄의 **문장을 다듬는 데까지**다.
//
// 임계값은 판정이 쓰는 것을 **가져다 쓴다**(`WalkSafety.pm25Moderate` · [WalkSafety.isDaytime]
// · [WalkSafety.seniorMonths] · [WalkSafety.isBrachycephalic]). 두 군데에 따로 적으면
// 한쪽만 고쳐져 카드와 조언이 다른 말을 한다.
import 'package:flutter/material.dart' show IconData, Icons;

import '../domain/pet.dart';
import 'walk_safety.dart';

/// 조언이 나온 **자리**. 테스트가 문구가 아니라 규칙을 잠그도록 이름을 준다 —
/// 문장을 다듬어도 표는 그대로여야 한다.
enum WalkAdviceKind {
  /// 미세먼지 매우나쁨 — 오늘은 나가지 않는다.
  indoorPlay,

  /// 바닥 7초 룰.
  hotGround,

  /// 시간대를 옮긴다.
  coolHours,

  /// 추위 — 짧게 · 발 닦기.
  cold,

  /// 소형견에게 옷.
  coat,

  /// 미세먼지 나쁨 — 짧게 · 발과 털 닦기.
  dust,

  /// 비 — 미끄러움 · 발 말리기.
  rain,

  /// 고온다습 — 헐떡임.
  humid,

  /// 우리 아이가 단두종.
  brachy,

  /// 우리 아이가 노령견.
  senior,
}

/// 조언 한 줄.
class WalkAdviceLine {
  final WalkAdviceKind kind;
  final IconData icon;
  final String text;

  const WalkAdviceLine(this.kind, this.icon, this.text);
}

class WalkAdvice {
  WalkAdvice._();

  /// 한 번에 보여 주는 줄 수. 넘치면 **아래 목록 순서대로** 앞에서 셋만 남는다 —
  /// 그 순서가 곧 급한 순서다(실내 > 화상 > 시간대 > 추위 > 먼지 > 비 > 습도 > 아이).
  static const int maxLines = 3;

  /// 아스팔트가 발바닥을 데울 수 있는 기온. 바닥 52°C 는 기온 25°C 부터 나온다(#336 근거).
  static const double hotGroundC = 25;

  /// 시간대를 옮기라고 말하는 기온.
  static const double coolHoursC = 28;

  /// 발이 시린 기온.
  static const double coldC = 5;

  /// 소형견에게 옷을 입히는 기온 — 판정의 소형견 추위 기준과 같은 0°C 다.
  static const double coatC = 0;

  /// 땀을 못 흘리는 아이에게 체온이 안 떨어지는 습도(%).
  static const int humidHigh = 80;

  /// 지금 값에서 나오는 조언. **해당하는 것만, 최대 [maxLines] 줄, 없으면 빈 목록**이다 —
  /// 자리를 채우려고 아무 말이나 넣지 않는다.
  ///
  /// [hour] 는 판정과 같은 기기 시각(0~23)이다. 같은 27°C 라도 낮과 밤이 다르다.
  /// [dog] 가 `null` 이면 아이 얘기(단두종·나이·몸집)는 아예 안 나온다 — 우리 아이가
  /// 단두종이 아닌데 단두종 얘기를 하면 그건 남 얘기다.
  static List<WalkAdviceLine> pick(
    WalkSafetyReading r, {
    required int hour,
    DogProfile? dog,
  }) {
    final t = r.tempC;
    final daytime = WalkSafety.isDaytime(hour);

    final pm25 = r.pm25;
    final pm10 = r.pm10;
    // 없는 값(`null`)은 나쁘지도 좋지도 않다 — 먼지 조언을 안 한다.
    final dustBad =
        (pm25 != null && pm25 > WalkSafety.pm25Bad) || (pm10 != null && pm10 > WalkSafety.pm10Bad);
    // 매우나쁨이면 "짧게" 가 아니라 "실내" 다. 두 줄이 같이 나오면 서로 어긋난다.
    final dustModerate = !dustBad &&
        ((pm25 != null && pm25 > WalkSafety.pm25Moderate) ||
            (pm10 != null && pm10 > WalkSafety.pm10Moderate));

    final small = dog != null && dog.size == DogSize.small;
    final brachy = dog != null && WalkSafety.isBrachycephalic(dog.breed);
    final senior = dog != null && dog.ageMonths >= WalkSafety.seniorMonths;
    // 습도는 안 올 수 있다. 모르면 안 말한다.
    final humid = (r.humidity ?? 0) >= humidHigh;

    final lines = <WalkAdviceLine>[
      if (dustBad)
        const WalkAdviceLine(WalkAdviceKind.indoorPlay, Icons.home_rounded,
            '미세먼지가 매우 나빠요 — 오늘은 실내 놀이로 대신해 주세요'),
      if (t >= hotGroundC && daytime)
        const WalkAdviceLine(WalkAdviceKind.hotGround, Icons.back_hand_outlined,
            '손등을 바닥에 7초 못 대면 발바닥도 못 견뎌요. 아스팔트는 기온보다 최대 33°C 뜨거워요'),
      if (t >= coolHoursC)
        const WalkAdviceLine(
            WalkAdviceKind.coolHours, Icons.schedule_rounded, '오전 10시 전 · 오후 7시 뒤가 안전해요'),
      if (t <= coldC)
        const WalkAdviceLine(WalkAdviceKind.cold, Icons.ac_unit_rounded,
            '짧게 다녀오세요. 발이 시릴 수 있으니 돌아와서 발을 닦아 주세요'),
      if (t <= coatC && small)
        const WalkAdviceLine(
            // 종류를 안 부른다 — 고양이·기타에도 같은 말이 맞아야 한다(#719).
            WalkAdviceKind.coat, Icons.checkroom_rounded, '몸집이 작으면 체온이 더 빨리 떨어져요 — 옷을 입혀 주세요'),
      if (dustModerate)
        const WalkAdviceLine(
            WalkAdviceKind.dust, Icons.masks_outlined, '짧게 다녀오고, 돌아와서 발과 털을 닦아 주세요'),
      if (r.raining)
        const WalkAdviceLine(
            WalkAdviceKind.rain, Icons.umbrella_rounded, '길이 미끄러워요. 돌아와서 발을 잘 말려 주세요'),
      if (humid && t >= hotGroundC)
        const WalkAdviceLine(WalkAdviceKind.humid, Icons.water_drop_outlined,
            '습해서 체온이 잘 안 떨어져요 — 헐떡임이 잦아지면 바로 그늘로 가 주세요'),
      if (brachy && t >= hotGroundC)
        const WalkAdviceLine(WalkAdviceKind.brachy, Icons.pets_rounded,
            '우리 아이는 단두종이라 더위에 특히 약해요 — 한 단계 보수적으로 봐 주세요'),
      if (senior && (t >= hotGroundC || t <= coldC))
        const WalkAdviceLine(
            WalkAdviceKind.senior, Icons.favorite_outline_rounded, '나이 든 아이는 더위도 추위도 더 힘들어요 — 천천히, 자주 쉬어 가요'),
    ];

    return lines.length <= maxLines ? lines : lines.sublist(0, maxLines);
  }
}
