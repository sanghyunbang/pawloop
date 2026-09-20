// 커뮤니티의 "우리 동네" — 이슈 #342.
//
// ## 여기서 재는 것
//
//  1. **동네를 고른 사람에게만 칩이 보인다.** 안 고른 채로 켜면 서버가 400 이고, 그건
//     사용자 잘못이 아니다.
//  2. **켜면 `neighborhood=mine` 이 나간다.** 구 코드를 보내지 않는다 — 보내면 아무 구나
//     골라 훑을 수 있고 그건 "우리 동네" 가 아니다.
//  3. **글 카드의 동네가 구까지다.** 동이 보이면 사는 곳이 그만큼 좁혀진다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/neighborhood_store.dart';
import 'package:heat_trip_flutter/v2/domain/neighborhood.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';

const _seongsu = Neighborhood(
  code: '1120068000',
  sigunguCode: '11200',
  sido: '서울특별시',
  sigungu: '성동구',
  dong: '성수1가1동',
  lat: 37.54554,
  lng: 127.04425,
);

class _Feed implements CommunityRepository {
  final List<bool> asked = [];

  @override
  Future<CommunityPage<CommunityPost>> feed({
    CommunityBoard? board,
    String? cursor,
    int? limit,
    bool myNeighborhood = false,
    int? dogId,
    String? contentId,
  }) async {
    asked.add(myNeighborhood);
    return CommunityPage(
      items: [
        CommunityPost(
          id: 1,
          author: const PersonRef(userId: 9, nickname: '성동사람'),
          board: CommunityBoard.free,
          title: '오늘 산책',
          body: '좋았어요',
          commentCount: 0,
          reactions: ReactionSummary.empty,
          createdAt: DateTime(2026, 9, 7),
          authorDistrict: myNeighborhood ? '성동구' : '성동구',
        ),
      ],
      nextCursor: null,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<_Feed> _pump(WidgetTester tester, {Neighborhood? mine}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final store = NeighborhoodStore();
  if (mine != null) {
    SharedPreferences.setMockInitialValues({
      'v2.neighborhood':
          '{"code":"${mine.code}","sigunguCode":"${mine.sigunguCode}",'
          '"sido":"${mine.sido}","sigungu":"${mine.sigungu}","dong":"${mine.dong}",'
          '"lat":${mine.lat},"lng":${mine.lng}}',
    });
  }

  final repo = _Feed();
  await tester.pumpWidget(MaterialApp(
    home: FeedScreen(repository: repo, neighborhoods: store),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('동네를 안 고르면 칩이 없다 — 켜면 서버가 400 이다', (tester) async {
    final repo = await _pump(tester);

    // 글 카드의 구 표시(성동구)와 섞이지 않게 **칩의 아이콘**으로 잰다.
    expect(find.byIcon(Icons.home_work_outlined), findsNothing);
    expect(repo.asked, [false]);
  });

  testWidgets('동네를 고르면 구 이름의 칩이 보인다', (tester) async {
    await _pump(tester, mine: _seongsu);

    expect(find.byIcon(Icons.home_work_outlined), findsOneWidget);
    expect(find.text('성동구'), findsWidgets);
  });

  testWidgets('칩을 켜면 우리 동네만 다시 받는다 — 구 코드는 안 보낸다', (tester) async {
    final repo = await _pump(tester, mine: _seongsu);

    await tester.tap(find.byIcon(Icons.home_work_outlined));
    await tester.pumpAndSettle();

    expect(repo.asked, [false, true],
        reason: '켜는 순간 다시 받는다 — 목록이 그대로면 토글이 안 먹은 것으로 보인다');
  });

  testWidgets('글 카드에 글쓴이의 구가 붙는다 — 동은 없다', (tester) async {
    await _pump(tester, mine: _seongsu);

    expect(find.text('성동사람'), findsOneWidget);
    expect(find.textContaining('성수1가'), findsNothing,
        reason: '남의 사는 곳을 구보다 좁히면 그것만으로 사람을 찾아갈 수 있다');
  });
}
