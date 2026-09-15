// 산책 하나의 시간과 페이스 — 이슈 #537.
//
// ## 무엇이 있었나
//
// 같은 산책이 화면마다 다른 말을 했다.
//
// | 화면 | 시간 | 페이스 |
// |:---|:---|:---|
// | 산책 중 · 끝내기 시트 | `00:44` | `1'02"` |
// | 기록 목록 · 상세 | **`0분`** | **`-`** |
//
// 기록 쪽이 `durationS ~/ 60` 으로 분만 봤다. 1분이 안 되는 산책이 통째로 사라지고, 페이스도
// 분으로 나누느라(`minutes / km`) 분이 0 이면 잴 수가 없었다.
//
// 거리는 `0.7km` 인데 시간이 `0분` 이면 사용자는 기록이 잘못됐다고 읽는다. 짧은 산책은 실제로
// 있다 — 비 오는 날 배변만, 아픈 아이와 5분, 아파트 한 바퀴.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/walk_labels.dart';

void main() {
  group('걸린 시간', () {
    test('1분이 안 되면 초로 적는다 — 예전에는 0분이었다 (#537)', () {
      expect(walkTimeLabel(44), '44초');
      expect(walkTimeLabel(59), '59초');
      expect(walkTimeLabel(1), '1초');
    });

    test('1분부터는 분이다 — 기록 카드는 훑는 자리라 초를 안 적는다', () {
      expect(walkTimeLabel(60), '1분');
      expect(walkTimeLabel(119), '1분');
      expect(walkTimeLabel(720), '12분');
      expect(walkTimeLabel(3600), '60분');
    });

    test('0이어도 0분이 아니라 0초다', () {
      expect(walkTimeLabel(0), '0초');
    });

    test('음수는 0초로 — 계약에 없는 값이지만 화면이 "-1초" 를 그리면 안 된다', () {
      expect(walkTimeLabel(-5), '0초');
    });
  });

  group('페이스', () {
    test('초로 나눈다 — 0.70km 를 44초에 걸으면 1\'03"다 (#537)', () {
      expect(walkPaceLabel(durationS: 44, km: 0.70), "1'03\"");
    });

    test('분이 0 이어도 잰다 — 예전에는 여기서 "-" 였다', () {
      expect(walkPaceLabel(durationS: 30, km: 0.5), "1'00\"");
    });

    test('보통 산책', () {
      expect(walkPaceLabel(durationS: 1800, km: 2.4), "12'30\"");
    });

    test('초가 60으로 반올림되면 분을 올린다 — 3\'60" 이 되면 안 된다', () {
      expect(walkPaceLabel(durationS: 598, km: 5.0), "2'00\"");
    });

    test('시간이 0이면 못 잰다', () {
      expect(walkPaceLabel(durationS: 0, km: 1.2), isNull);
    });

    test('10m 아래면 못 잰다 — GPS 오차가 페이스를 몇 배로 부풀린다', () {
      expect(walkPaceLabel(durationS: 60, km: 0.005), isNull);
      expect(walkPaceLabel(durationS: 60, km: 0), isNull);
    });
  });
}
