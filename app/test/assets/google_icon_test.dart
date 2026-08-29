// 구글 "G" 로고 에셋이 브랜드 가이드의 공식 4색을 갖고 있는지 검증한다.
//
// 예전 assets/icons/google.svg 는 fill 속성이 없는 단색 1-path 자리표시자였다.
// 그 상태로 되돌리면 이 테스트가 빨간불이 된다. (이슈 #3 완료 조건 10)
//
// 파일을 dart:io 로 직접 읽는다 — `flutter test` 의 작업 디렉터리는 app/ 이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assets/icons/google.svg', () {
    late String svg;

    setUpAll(() {
      final file = File('assets/icons/google.svg');
      expect(file.existsSync(), isTrue,
          reason: 'assets/icons/google.svg 파일이 없다');
      svg = file.readAsStringSync();
    });

    test('구글 공식 4색이 모두 들어 있다', () {
      const brandColors = ['#4285F4', '#34A853', '#FBBC05', '#EA4335'];

      for (final color in brandColors) {
        expect(
          svg.toUpperCase(),
          contains(color),
          reason: '구글 브랜드 색 $color 가 SVG에 없다 — 임의 색상 변경 금지',
        );
      }
    });

    test('색을 칠한 path가 4개 이상이다 — 단색 1-path 자리표시자가 아니다', () {
      final filledPaths = RegExp('fill="#').allMatches(svg).length;

      expect(filledPaths, greaterThanOrEqualTo(4));
    });
  });
}
