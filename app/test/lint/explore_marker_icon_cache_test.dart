// 지도 핀 그림은 반드시 `MarkerIcons` 를 거친다 — 이슈 #533.
//
// ## 왜 소스를 훑나
//
// `MarkerIcons` 자체는 `marker_icons_test` 가 잰다 — "80곳을 줘도 카테고리 수만큼만 굽는다".
// 그런데 그 자리를 **안 거치고** 장소마다 직접 구워도 그 테스트는 초록이다. 고친 것이 캐시가
// 아니라 **부르는 자리**이기 때문이다.
//
// `NOverlayImage.fromWidget` 은 플러그인이라 순수 테스트에서 못 부르고, 지도 화면은 위젯
// 테스트에서 안 뜬다. 그래서 여기서는 소스로 잠근다 — 되돌아갔을 때 **무엇도 안 잡는** 상태를
// 만들지 않으려는 것이다(#531 에서 같은 자리를 겪었다: 산책 화면의 말풍선을 지키는 것이 소스
// 검사 하나뿐이었다).
//
// 재 본 값: 장소마다 구울 때 80곳에서 **전체 31730ms 중 아이콘 31471ms**. 거쳐서 구우니
// **4494ms 중 4382ms** 였다. 화면에서도 핀이 20~24초 → 10~12초로 당겨졌다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../v2/support/dart_source.dart';

/// 검사하는 파일. 이 경로가 바뀌면 테스트가 먼저 말한다.
const _screen = 'lib/v2/screens/explore_screen.dart';

void main() {
  late String source;

  setUpAll(() {
    final file = File(_screen);
    if (!file.existsSync()) {
      fail('$_screen 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
    }
    source = stripCommentsKeepingLines(file.readAsStringSync());
  });

  test('캐시가 실제로 물려 있다', () {
    expect(source, contains('MarkerIcons(_drawMarkerIcon)'),
        reason: '이 줄이 없으면 장소마다 핀 그림을 새로 굽는다(#533)');
  });

  test('굽는 일을 직접 부르는 자리가 없다 — 캐시를 거치지 않으면 뜻이 없다', () {
    // 선언 한 번 + `MarkerIcons(...)` 에 넘기는 한 번. 세 번째는 누군가 직접 부른 것이다.
    expect(occurrencesOf('_drawMarkerIcon', source), 2,
        reason: '_drawMarkerIcon 은 MarkerIcons 에 넘기는 것 말고 아무도 안 부릅니다.\n'
            '핀이 필요하면 _markerIcon(cat) 을 부르세요 — 그 자리가 기억합니다.');
  });

  test('그림을 굽는 자리는 둘뿐이다 — 클러스터 핀과 카테고리 핀', () {
    expect(occurrencesOf('NOverlayImage.fromWidget', source), 2,
        reason: '위젯을 그림으로 굽는 일은 한 개에 약 393ms 입니다. 새 자리가 생겼다면 '
            '그것도 한 번만 굽는지 보세요 — _prepareClusterIcon 과 MarkerIcons 가 그 본보기입니다.');
  });

  group('세는 장치가 실제로 가르는가', () {
    test('주석과 문자열 속 이름은 안 센다', () {
      const planted = '''
// _drawMarkerIcon 을 여기 적어도 부른 것이 아니다
/* NOverlayImage.fromWidget 도 마찬가지다 */
final hint = 'NOverlayImage.fromWidget 을 쓰세요';
_drawMarkerIcon(cat);
''';
      final stripped = stripCommentsKeepingLines(planted);
      expect(occurrencesOf('_drawMarkerIcon', stripped), 1);
      expect(occurrencesOf('NOverlayImage.fromWidget', stripped), 0);
    });

    test('세 번째 호출을 심으면 개수가 올라간다', () {
      final planted = '$source\nvoid extra() { _drawMarkerIcon(cat); }';
      expect(occurrencesOf('_drawMarkerIcon', planted), 3,
          reason: '이 단언이 안 움직이면 위의 `2` 는 아무것도 안 재고 있는 것이다');
    });
  });
}

/// [needle] 이 [source] 에 몇 번 나오는가.
int occurrencesOf(String needle, String source) => needle.allMatches(source).length;
