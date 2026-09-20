// 가족 구성원 색 — 이슈 #736. 넷이 서로 다르고, 브랜드 코랄과 안 겹치고, 파스텔이 아니다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/theme/app_tokens.dart';
import 'package:heat_trip_flutter/v2/theme/member_colors.dart';

void main() {
  test('넷은 서로 다르고, 다섯째는 처음으로 돈다', () {
    final four = [for (var i = 0; i < 4; i++) memberColor(i)];
    expect(four.toSet().length, 4);
    expect(memberColor(4), memberColor(0));
    expect(memberColor(5), memberColor(1));
  });

  test('브랜드 코랄과 겹치지 않는다 — 그 색은 "골랐다 · 끝냈다" 의 색이다', () {
    for (var i = 0; i < 4; i++) {
      expect(memberColor(i), isNot(T.accent), reason: '$i 번째');
    }
  });

  test('파스텔이 아니다 — 흰 바탕에 글자로 읽혀야 한다', () {
    for (var i = 0; i < 4; i++) {
      expect(memberColor(i).computeLuminance(), lessThan(0.35), reason: '$i 번째');
    }
  });
}
