// 산책 안전 지수 — "지금 우리 아이랑 나가도 되나" 한 줄 (#336).
//
// 규칙·격자 변환·응답 파싱은 전부 순수 함수다. 네트워크는 `walk_safety_repository.dart` 가 한다.
//
// 수치는 **참고**다 — 수의사 자문 전까지 화면에도 그렇게 적는다. 근거(°F 를 °C 로 옮긴 것):
// - 아스팔트는 기온보다 최대 33°C 높다. 기온 30°C 면 바닥 57°C (AKC)
// - 바닥 52°C 에서 60초면 발바닥 화상. 기온 25°C 부터 가능 (Blue Dog Pet Care · Four Paws)
// - 손등 7초 룰. 오전 10시 전 · 오후 7시 후가 안전 (The Farmer's Dog · Animal Keeper)
// - 미세먼지 등급은 환경부 예보 기준(PM2.5 좋음 ≤15 · 보통 ≤35 · 나쁨 ≤75 · 매우나쁨 >75)
import 'dart:math' as math;

import '../domain/pet.dart';

enum WalkSafetyLevel {
  /// "지금 나가기 좋아요"
  good,

  /// "짧게 다녀오세요"
  short,

  /// "지금은 피하고 저녁에"
  avoid,

  /// "옷 입히고 짧게"
  cold,
}

/// 판정 한 장. [headline] 이 카드의 한 줄, [reasons] 가 근거 조각들("28°C", "미세먼지 나쁨").
class WalkSafetyVerdict {
  final WalkSafetyLevel level;
  final String headline;
  final List<String> reasons;

  const WalkSafetyVerdict(this.level, this.headline, this.reasons);

  bool get shouldAskBeforeWalk => level == WalkSafetyLevel.avoid;
}

/// 기상·대기 관측값 한 묶음. 못 받은 값은 `null` — 서버가 에어코리아를 못 부르면 PM 이 비어 온다.
/// 비었다는 것은 "미세먼지가 없다" 가 아니라 "이번엔 못 쟀다" 는 뜻이다(#668).
class WalkSafetyReading {
  final double tempC;
  final int? humidity;

  /// 1시간 강수량(mm). 0 이면 비 없음.
  final double? rain1hMm;

  /// 기상청 PTY — 0 없음 · 1 비 · 2 비/눈 · 3 눈 · 5 빗방울 · 6 빗방울눈날림 · 7 눈날림.
  final int? precipType;
  final int? pm10;
  final int? pm25;

  /// 미세먼지 측정소 이름. 근거 조각에 "(성수)" 로 붙는다.
  final String? station;
  final DateTime observedAt;

  const WalkSafetyReading({
    required this.tempC,
    this.humidity,
    this.rain1hMm,
    this.precipType,
    this.pm10,
    this.pm25,
    this.station,
    required this.observedAt,
  });

  bool get raining => (precipType ?? 0) != 0 || (rain1hMm ?? 0) > 0;
}

class WalkSafety {
  WalkSafety._();

  /// 단두종 — 더위에 특히 약하다. 품종 문자열에 이 조각이 있으면 한 단계 보수적으로.
  static const List<String> brachycephalic = [
    '퍼그', '불독', '불도그', '시추', '페키니즈', '보스턴', '복서', '샤페이', '그리펀', '친',
    'pug', 'bulldog', 'shih', 'peking', 'boston', 'boxer', 'shar',
  ];

  /// 노령견 기준(개월). 84개월 = 7살.
  static const int seniorMonths = 84;

  /// 미세먼지를 **못 받았을 때** 근거에 적는 한 줄. 값이 없는 것이 아니라 못 잰 것이다(#668).
  static const String pmUnavailable = '미세먼지는 못 받았어요';

  /// PM2.5 등급 경계(환경부). 35 초과면 나쁨.
  static const int pm25Moderate = 35;
  static const int pm25Bad = 75;
  static const int pm10Moderate = 80;
  static const int pm10Bad = 150;

  /// 낮 — 아스팔트가 달아 있는 시간대. 조언(`walk_advice.dart`)도 같은 창을 본다 (#669).
  /// 두 군데에 따로 적으면 한쪽만 고쳐져 카드와 조언이 다른 말을 한다.
  static bool isDaytime(int hour) => hour >= 10 && hour < 19;

  /// 판정. [hour] 는 기기 시각(0~23)이다 — 같은 30°C 라도 낮과 저녁이 다르다.
  static WalkSafetyVerdict judge(WalkSafetyReading r, {required int hour, DogProfile? dog}) {
    final reasons = <String>['${r.tempC.round()}°C'];
    if (r.raining) reasons.add('비');
    if (r.pm25 != null) {
      reasons.add('미세먼지 ${pmLabel(r.pm25!, r.pm10)}${r.station == null ? '' : '(${r.station})'}');
    } else if (r.pm10 != null) {
      reasons.add('미세먼지 ${pmLabel(null, r.pm10)}${r.station == null ? '' : '(${r.station})'}');
    } else {
      // **못 받은 것과 없는 것은 다르다**(#515 가 급할 때 병원 목록에서 세운 구분).
      // 게다가 미세먼지는 "없다" 가 아예 성립하지 않는다 — 공기는 늘 있고 우리가 못 잰 것뿐이다.
      // 서버가 에어코리아를 한 번 못 부른 날 "정보 없음" 이 떴고, 그건 거짓말이었다(#668).
      reasons.add(pmUnavailable);
    }

    // 더위·미세먼지에서 나온 단계(0 좋음 · 1 짧게 · 2 피하세요)
    var heat = 0;
    final daytime = isDaytime(hour);
    if (r.tempC >= 30 && daytime) {
      heat = 2;
    } else if (r.tempC >= 30) {
      heat = 1;
    } else if (r.tempC >= 25 && daytime) {
      heat = 1;
    }
    var dust = 0;
    final pm25 = r.pm25;
    final pm10 = r.pm10;
    if ((pm25 != null && pm25 > pm25Bad) || (pm10 != null && pm10 > pm10Bad)) {
      dust = 2;
    } else if ((pm25 != null && pm25 > pm25Moderate) || (pm10 != null && pm10 > pm10Moderate)) {
      dust = 1;
    }
    var stage = math.max(heat, dust);

    // 보정 — 단두종·노령견은 더위에 한 단계 보수적으로, 대형견도 더위에 약하다.
    final vulnerable = dog != null && (isBrachycephalic(dog.breed) || dog.ageMonths >= seniorMonths);
    if (vulnerable && heat >= 1 && stage < 2) {
      stage += 1;
      reasons.add(isBrachycephalic(dog.breed) ? '단두종' : '노령견');
    } else if (dog != null && dog.size == DogSize.large && heat == 1 && stage < 2 && r.tempC >= 28) {
      stage = 2;
      reasons.add('대형견');
    }

    // 추위 — 더위 판정과 겹치지 않는다.
    final small = dog != null && dog.size == DogSize.small;
    if (r.tempC <= -5 || (r.tempC <= 0 && small)) {
      return WalkSafetyVerdict(WalkSafetyLevel.cold, '옷 입히고 짧게 다녀오세요', reasons);
    }

    if (r.raining && stage < 1) stage = 1;

    switch (stage) {
      case 0:
        return WalkSafetyVerdict(WalkSafetyLevel.good, '지금 나가기 좋아요', reasons);
      case 1:
        return WalkSafetyVerdict(
          WalkSafetyLevel.short,
          r.raining && heat == 0 && dust == 0 ? '짧게 다녀오세요 · 비가 와요' : '짧게 다녀오세요 · 바닥 7초 룰 확인',
          reasons,
        );
      default:
        return WalkSafetyVerdict(
          WalkSafetyLevel.avoid,
          dust == 2 && heat < 2 ? '지금은 피하세요 · 미세먼지가 나빠요' : '지금은 피하고 저녁 7시 뒤에',
          reasons,
        );
    }
  }

  static bool isBrachycephalic(String breed) {
    final b = breed.toLowerCase();
    return brachycephalic.any((k) => b.contains(k.toLowerCase()));
  }

  /// "좋음 · 보통 · 나쁨 · 매우나쁨". PM2.5 가 있으면 그것으로, 없으면 PM10 으로.
  ///
  /// 둘 다 없으면 등급이 아니라 **못 받았다**고 말한다 — "정보 없음" 은 값이 0 이거나 공기가
  /// 깨끗하다는 뜻으로도 읽힌다(#668).
  static String pmLabel(int? pm25, int? pm10) {
    if (pm25 != null) {
      if (pm25 <= 15) return '좋음';
      if (pm25 <= pm25Moderate) return '보통';
      if (pm25 <= pm25Bad) return '나쁨';
      return '매우나쁨';
    }
    if (pm10 != null) {
      if (pm10 <= 30) return '좋음';
      if (pm10 <= pm10Moderate) return '보통';
      if (pm10 <= pm10Bad) return '나쁨';
      return '매우나쁨';
    }
    return '못 받음';
  }
}

/// 기상청 격자(nx, ny). 위경도 → Lambert Conformal Conic. 기상청이 배포한 상수 그대로다.
/// 서울시청(37.5665, 126.9780) → (60, 127). 5km 격자라 **좌표가 아니라 5km 칸 번호**가 나간다.
({int nx, int ny}) kmaGrid(double lat, double lng) {
  const re = 6371.00877; // 지구 반경(km)
  const grid = 5.0; // 격자 간격(km)
  const slat1 = 30.0;
  const slat2 = 60.0;
  const olon = 126.0;
  const olat = 38.0;
  const xo = 43.0; // 기준점 X 좌표(격자)
  const yo = 136.0; // 기준점 Y 좌표(격자)

  const degrad = math.pi / 180.0;
  final r = re / grid;
  final s1 = slat1 * degrad;
  final s2 = slat2 * degrad;
  final ol = olon * degrad;
  final oa = olat * degrad;

  var sn = math.tan(math.pi * 0.25 + s2 * 0.5) / math.tan(math.pi * 0.25 + s1 * 0.5);
  sn = math.log(math.cos(s1) / math.cos(s2)) / math.log(sn);
  var sf = math.tan(math.pi * 0.25 + s1 * 0.5);
  sf = math.pow(sf, sn) * math.cos(s1) / sn;
  var ro = math.tan(math.pi * 0.25 + oa * 0.5);
  ro = r * sf / math.pow(ro, sn);

  var ra = math.tan(math.pi * 0.25 + lat * degrad * 0.5);
  ra = r * sf / math.pow(ra, sn);
  var theta = lng * degrad - ol;
  if (theta > math.pi) theta -= 2.0 * math.pi;
  if (theta < -math.pi) theta += 2.0 * math.pi;
  theta *= sn;
  final x = (ra * math.sin(theta) + xo + 0.5).floor();
  final y = (ro - ra * math.cos(theta) + yo + 0.5).floor();
  return (nx: x, ny: y);
}
