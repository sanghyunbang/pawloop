// 커뮤니티 안의 크루 갈래가 **서버에서 온 것을 그리는가** (이슈 #417).
//
// `community_feed_test.dart` 와 같은 방식이다 — 리포지토리를 목으로 갈아끼우지 않고
// **진짜 CrewRepository 에 MockClient 를 꽂는다.** 그래야 JSON 파싱·경로·실패 분류까지
// 한 번에 지난다.
//
// ## 여기서 가장 중요한 것
//
// **안 든 사람에게 멤버가 안 보이는 것**과 **동네를 안 골랐을 때 "다시 시도" 가 아니라
// "동네 고르기" 로 보내는 것**이다. 뒤엣것은 다시 눌러도 같은 400 이라, 그 버튼을 그리면
// 사용자를 무한히 같은 자리에 두는 셈이다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/crew_repository.dart';
import 'package:heat_trip_flutter/v2/data/neighborhood_store.dart';
import 'package:heat_trip_flutter/v2/data/region_catalog.dart';
import 'package:heat_trip_flutter/v2/screens/crew_section.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'RT-1';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _error(int status, String code, String message) =>
    _json({'error': {'code': code, 'message': message}}, status: status);

Map<String, Object?> _crew({
  int id = 4,
  int roomId = 9,
  String name = '성수동 아침 산책',
  Object? intro = '천천히 걷습니다',
  String visibility = 'public',
  int capacity = 20,
  int memberCount = 3,
  bool mine = false,
  bool owner = false,
  List<Object?> members = const [],
}) =>
    {
      'id': id,
      'roomId': roomId,
      'name': name,
      'intro': intro,
      'neighborhoodCode': '1120052000',
      'visibility': visibility,
      'capacity': capacity,
      'memberCount': memberCount,
      'mine': mine,
      'owner': owner,
      'members': members,
      'createdAt': '2026-09-10T02:20:00Z',
    };

/// 동네 이름표만 확인하면 되니 한 줄짜리 자산이면 충분하다 — 3,516줄을 테스트가 읽을
/// 이유가 없다.
final RegionCatalog _catalog = RegionCatalog.parse(jsonEncode({
  'source': 'test',
  'sido': [
    {'c': '11', 'n': '서울특별시'}
  ],
  'sigungu': [
    {'c': '11200', 's': '11', 'n': '성동구'}
  ],
  'dong': [
    {'c': '1120052000', 'g': '11200', 'n': '왕십리2동', 'lat': 37.56, 'lng': 127.03}
  ],
}));

({CrewRepository repo, List<http.Request> sent}) fixture(
    Future<http.Response> Function(http.Request request) handler) {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      return handler(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CrewRepository(baseUrl: _base, client: client), sent: sent);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 글 목록은 이 파일의 관심이 아니다 — 빈 피드를 주는 최소한의 서버만 세운다.
/// (안 세우고 `FeedScreen(repository: null)` 로 두면 진짜 네트워크로 12초를 기다린다.)
CommunityRepository communityFixture() {
  final client = AuthedClient(
    inner: MockClient((_) async =>
        _json({'items': const [], 'nextCursor': null, 'hasMore': false})),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return CommunityRepository(baseUrl: _base, client: client);
}

Widget _section(CrewRepository repo) => _host(CrewSection(
      repository: repo,
      neighborhoods: NeighborhoodStore(baseUrl: _base),
      catalog: _catalog,
    ));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('목록이 서버에서 온다 — 이름·동네·인원을 그린다', (tester) async {
    final f = fixture((_) async => _json([_crew(mine: true)]));

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();

    expect(find.text('성수동 아침 산책'), findsOneWidget);
    expect(find.text('성동구 왕십리2동 · 3 / 20명'), findsOneWidget,
        reason: '열 자리 코드는 사용자에게 아무 뜻이 없다 — 이름으로 되돌려 그린다');
    expect(find.text('천천히 걷습니다'), findsOneWidget);
  });

  testWidgets('갈래를 바꾸면 scope 가 바뀌어 나간다 — 좌표는 안 나간다', (tester) async {
    final f = fixture((_) async => _json(const []));

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crew-scope-neighborhood')));
    await tester.pumpAndSettle();

    expect(f.sent.map((r) => r.url.queryParameters['scope']),
        containsAllInOrder(['mine', 'neighborhood']));
    expect(f.sent.every((r) => !r.url.query.contains('lat')), isTrue);
  });

  testWidgets('동네를 안 골랐으면 "다시 시도" 가 아니라 "동네 고르기" 다', (tester) async {
    final f = fixture(
        (_) async => _error(400, 'VALIDATION', '동네를 먼저 골라 주세요.'));

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crew-scope-neighborhood')));
    await tester.pumpAndSettle();

    expect(find.text('동네를 먼저 골라 주세요'), findsOneWidget);
    expect(find.text('동네 고르기'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing,
        reason: '다시 눌러도 같은 400 이다 — 그 버튼은 사용자를 같은 자리에 가둔다');
  });

  testWidgets('못 불러오면 빈 목록이 아니라 이유와 다시 시도가 뜬다', (tester) async {
    final f = fixture((_) async => throw http.ClientException('연결 실패'));

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crew-failure')), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byKey(const Key('crew-empty')), findsNothing,
        reason: '빈 목록은 "크루가 없다" 로 읽힌다 — 서버가 죽은 것을 아무도 모른다');
  });

  testWidgets('빈 상태가 갈래마다 다른 말을 한다', (tester) async {
    final f = fixture((_) async => _json(const []));

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();
    expect(find.text('아직 든 크루가 없어요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('crew-scope-neighborhood')));
    await tester.pumpAndSettle();
    expect(find.text('우리 동네에 아직 크루가 없어요'), findsOneWidget,
        reason: '내 크루가 빈 것과 동네가 빈 것은 사용자가 할 일이 다르다');
  });

  testWidgets('안 든 크루는 "참여", 정원이 차면 "정원 참" 이다', (tester) async {
    final f = fixture((_) async => _json([
          _crew(id: 1, name: '자리 있는 모임', capacity: 20, memberCount: 3),
          _crew(id: 2, name: '꽉 찬 모임', capacity: 3, memberCount: 3),
        ]));

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();

    expect(find.text('참여'), findsOneWidget);
    expect(find.text('정원 참'), findsOneWidget);
  });

  testWidgets('카드를 누르면 크루 홈이 열리고, 안 든 공개 크루는 멤버를 안 보여 준다',
      (tester) async {
    final f = fixture((request) async {
      if (request.url.path == '/api/crews/4') {
        // 서버는 안 든 사람에게 members 를 **빈 배열**로 준다 — 인원 수까지가 공개다.
        return _json(_crew(mine: false, members: const []));
      }
      return _json([_crew()]);
    });

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crew-card-4')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crew-join-headline')), findsOneWidget);
    expect(find.text('멤버'), findsNothing,
        reason: '누가 있는지는 안에서만이다 — 빈 배열을 "아직 아무도 없다" 로 그려도 안 된다');
    expect(find.text('참여하기'), findsOneWidget);
  });

  testWidgets('든 크루의 홈은 멤버와 대화방 버튼을 보여 준다', (tester) async {
    final f = fixture((request) async {
      if (request.url.path == '/api/crews/4') {
        return _json(_crew(mine: true, owner: false, members: [
          {'userId': 1, 'nickname': '성수아빠', 'role': 'OWNER'},
          {'userId': 2, 'nickname': '나', 'role': 'MEMBER'},
        ]));
      }
      return _json([_crew(mine: true)]);
    });

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crew-card-4')));
    await tester.pumpAndSettle();

    expect(find.text('멤버'), findsOneWidget);
    expect(find.text('성수아빠'), findsOneWidget);
    expect(find.text('방장'), findsOneWidget);
    expect(find.text('대화방으로 가기'), findsOneWidget);
    expect(find.text('크루 나가기'), findsOneWidget);
    expect(find.byKey(const Key('crew-edit')), findsNothing,
        reason: '방장이 아니면 고치기 버튼이 아예 없다');
  });

  testWidgets('방장에게는 고치기·초대가 보이고 나가기는 안 보인다', (tester) async {
    final f = fixture((request) async {
      if (request.url.path == '/api/crews/4') {
        return _json(_crew(mine: true, owner: true, members: [
          {'userId': 1, 'nickname': '나', 'role': 'OWNER'},
          {'userId': 2, 'nickname': '이웃', 'role': 'MEMBER'},
        ]));
      }
      return _json([_crew(mine: true, owner: true)]);
    });

    await tester.pumpWidget(_section(f.repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crew-card-4')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crew-edit')), findsOneWidget);
    expect(find.text('초대 코드 보내기'), findsOneWidget);
    expect(find.text('크루 나가기'), findsNothing,
        reason: '방장이 나가면 초대코드도 못 내는 방이 남는다 — 서버도 400 이다');
    expect(find.byKey(const Key('crew-owner-cannot-leave')), findsOneWidget,
        reason: '버튼만 빼면 왜 없는지 아무도 모른다');
    expect(find.byKey(const Key('crew-kick-2')), findsOneWidget);
    expect(find.byKey(const Key('crew-kick-1')), findsNothing,
        reason: '방장은 자기를 못 내보낸다');
  });

  testWidgets('커뮤니티 탭 안에 크루 갈래가 있다 — 탭을 안 늘리고 갈래로 넣었다',
      (tester) async {
    final crews = fixture((_) async => _json([_crew(mine: true)]));
    final posts = communityFixture();

    await tester.pumpWidget(MaterialApp(
      home: FeedScreen(
        repository: posts,
        neighborhoods: NeighborhoodStore(baseUrl: _base),
        crews: crews.repo,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community-section-posts')), findsOneWidget);
    expect(find.byKey(const Key('community-section-crews')), findsOneWidget);

    await tester.tap(find.byKey(const Key('community-section-crews')));
    await tester.pumpAndSettle();

    expect(find.text('성수동 아침 산책'), findsOneWidget,
        reason: '크루가 커뮤니티 탭 안에서 그려져야 한다 — 여섯째 탭을 안 만든 것이 이 이슈의 결정이다');
    expect(find.text('동네 반려인 모임'), findsOneWidget,
        reason: '부제도 갈래를 따라간다 — "우리 아이들 이야기" 가 남으면 여기가 글 목록으로 읽힌다');
  });
}
