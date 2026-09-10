// 크루 만들기 시트 (이슈 #417).
//
// ## 여기서 가장 중요한 것
//
// **동네를 안 고른 사람에게 공개를 못 고르게 하는 것**이다. 고르게 두면 서버가 400 을
// 주는데, 그 사람이 받는 것은 "만들지 못했어요" 한 줄이고 무엇을 고쳐야 하는지 모른다.
// 동네 없는 공개 크루는 **아무도 못 찾는 공개**라 서버가 막는 것이 맞고, 화면은 그것을
// 누르기 **전에** 말해야 한다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/crew_repository.dart';
import 'package:heat_trip_flutter/v2/domain/crew.dart';
import 'package:heat_trip_flutter/v2/domain/neighborhood.dart';
import 'package:heat_trip_flutter/v2/widgets/crew_create_sheet.dart';

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

const _seongdong = Neighborhood(
  code: '1120052000',
  sigunguCode: '11200',
  sido: '서울특별시',
  sigungu: '성동구',
  dong: '왕십리2동',
  lat: 37.56,
  lng: 127.03,
);

({CrewRepository repo, List<http.Request> sent}) fixture() {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode({
          'id': 4,
          'roomId': 9,
          'name': '성수동 아침 산책',
          'intro': null,
          'neighborhoodCode': '1120052000',
          'visibility': 'invite',
          'capacity': 20,
          'memberCount': 1,
          'mine': true,
          'owner': true,
          'members': const [],
          'createdAt': '2026-09-10T02:20:00Z',
        }),
        201,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CrewRepository(baseUrl: _base, client: client), sent: sent);
}

/// 시트를 바로 띄우는 껍데기. 버튼을 한 번 눌러 여는 것과 결과가 같고 단계가 적다.
Widget _host({
  required CrewRepository repo,
  Neighborhood? mine,
  required void Function(Crew?) onDone,
}) {
  return MaterialApp(
    home: Builder(builder: (context) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final crew = await showCrewCreateSheet(context,
                  repository: repo, myNeighborhood: mine);
              onDone(crew);
            },
            child: const Text('열기'),
          ),
        ),
      );
    }),
  );
}

void main() {
  testWidgets('기기가 동네를 모르면 공개를 골랐을 때 알려 주되, 버튼은 안 잠근다',
      (tester) async {
    final f = fixture();
    await tester.pumpWidget(_host(repo: f.repo, mine: null, onDone: (_) {}));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('내가 고른 동네로 만들어져요'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '성수동 아침 산책');
    await tester.pump();
    await tester.tap(find.byKey(const Key('crew-visibility-public')));
    await tester.pump();

    expect(find.text('공개 크루는 동네가 있어야 해요 — 아직 안 골랐다면 먼저 골라 주세요'),
        findsOneWidget);

    final button =
        tester.widget<FilledButton>(find.byKey(const Key('crew-create-submit')));
    expect(button.onPressed, isNotNull,
        reason: '동네는 계정에도 있다 — 기기가 비었다고 잠그면 만들 수 있는 사람이 못 만든다. '
            '판정은 계정을 아는 서버가 한다');
  });

  testWidgets('서버가 거절하면 그 문구를 그대로 보여 준다 — 무엇을 고쳐야 하는지 말한다',
      (tester) async {
    final sent = <http.Request>[];
    final client = AuthedClient(
      inner: MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'VALIDATION',
              'message': '공개 크루는 동네를 골라야 합니다. 동네 목록이 찾는 유일한 길입니다.',
            }
          }),
          400,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      baseUrl: _base,
      store: _FakeTokenStore(),
    );
    final repo = CrewRepository(baseUrl: _base, client: client);

    await tester.pumpWidget(_host(repo: repo, mine: null, onDone: (_) {}));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '어디에도 없는 모임');
    await tester.pump();
    await tester.tap(find.byKey(const Key('crew-visibility-public')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crew-create-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crew-create-error')), findsOneWidget);
    expect(find.text('공개 크루는 동네를 골라야 합니다. 동네 목록이 찾는 유일한 길입니다.'),
        findsOneWidget);
    expect(sent, hasLength(1));
  });

  testWidgets('동네를 고른 사람은 공개로 만들 수 있고, 그 동네가 한 줄로 보인다',
      (tester) async {
    final f = fixture();
    await tester.pumpWidget(_host(repo: f.repo, mine: _seongdong, onDone: (_) {}));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('성동구 왕십리2동 크루로 만들어져요'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '성수동 아침 산책');
    await tester.pump();
    await tester.tap(find.byKey(const Key('crew-visibility-public')));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byKey(const Key('crew-create-submit')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('이름이 비면 못 누른다 — 서버까지 가서 400 을 받지 않는다', (tester) async {
    final f = fixture();
    await tester.pumpWidget(_host(repo: f.repo, mine: _seongdong, onDone: (_) {}));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byKey(const Key('crew-create-submit')));
    expect(button.onPressed, isNull);
  });

  testWidgets('만들면 이름·공개 범위·정원이 서버로 나가고 그 크루가 돌아온다',
      (tester) async {
    final f = fixture();
    Crew? made;
    await tester.pumpWidget(
        _host(repo: f.repo, mine: _seongdong, onDone: (crew) => made = crew));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '성수동 아침 산책');
    await tester.pump();
    // 기본 20 에서 한 번 줄여 19 로.
    await tester.tap(find.byKey(const Key('crew-capacity-minus')));
    await tester.pump();
    expect(find.text('19명'), findsOneWidget);

    await tester.tap(find.byKey(const Key('crew-create-submit')));
    await tester.pumpAndSettle();

    final body = jsonDecode(f.sent.single.body) as Map;
    expect(body['name'], '성수동 아침 산책');
    expect(body['visibility'], 'invite', reason: '기본은 초대다');
    expect(body['capacity'], 19);
    expect(body.containsKey('neighborhoodCode'), isFalse,
        reason: '동네는 서버가 내 것을 쓴다 — 같은 값을 정하는 자리를 둘로 만들지 않는다');
    expect(made?.id, 4);
  });

  testWidgets('정원은 2 아래로 안 내려간다', (tester) async {
    final f = fixture();
    await tester.pumpWidget(_host(repo: f.repo, mine: _seongdong, onDone: (_) {}));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 25; i++) {
      final minus = find.byKey(const Key('crew-capacity-minus'));
      if (tester.widget<IconButton>(minus).onPressed == null) break;
      await tester.tap(minus);
      await tester.pump();
    }

    expect(find.text('2명'), findsOneWidget,
        reason: '1명짜리 모임은 모임이 아니다 — DB 의 CHECK 도 같은 말을 한다');
  });
}
