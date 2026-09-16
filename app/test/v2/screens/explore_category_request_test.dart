// 지도 탭에 "이 갈래로 열어 달라" 를 넘기는 한 번짜리 부탁 — 이슈 #560.
//
// 오늘의 케어 카드의 "주변" 줄이 갈래를 놓고 탭을 바꾸면, 지도가 그것을 읽고 **비운다.**
// 안 비우면 그 뒤로 지도를 그냥 열어도 **영영 그 갈래로만** 열린다 — 커뮤니티 탭의
// `communityView` 가 같은 이유로 같은 규약을 쓴다(#451).
//
// 지도 화면을 띄우지 않는다. 띄우려면 위치·지도 키·네트워크가 필요하고, 여기서 재려는 것은
// 화면이 아니라 **규약**이다.

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/screens/main_shell.dart' show RootTab;

void main() {
  setUp(() => RootTab.exploreCategory.value = null);
  tearDown(() => RootTab.exploreCategory.value = null);

  test('부탁한 갈래가 그대로 온다', () {
    RootTab.exploreCategory.value = 'trail';

    expect(RootTab.takeExploreCategory(), 'trail');
  });

  test('읽으면 비워진다 — 다음에 그냥 열면 전체다', () {
    RootTab.exploreCategory.value = 'vet';

    RootTab.takeExploreCategory();

    expect(RootTab.exploreCategory.value, isNull);
    expect(RootTab.takeExploreCategory(), isNull,
        reason: '두 번째 열기까지 그 갈래면, 사용자는 지도가 고장 났다고 읽는다');
  });

  test('부탁이 없으면 null 이다', () {
    expect(RootTab.takeExploreCategory(), isNull);
  });
}
