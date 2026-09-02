// 가족 그룹을 앱에서 만들 수 있는가 — 이슈 #196.
//
// 로드맵이 M2.5 를 "앱 그룹 생성 경로만 남음" 이라고 적어 뒀는데 그 "남음" 이 이슈로도
// 코드로도 없었다. 서버는 `POST /api/groups` 를 진작 갖고 있었고, 앱에는 그 호출이
// **0건**이었다. 그룹이 없는 사람에게는 만들 길도 참여할 길도 화면에 없었다.
//
// `family_screen_test.dart` 와 같은 방식이다 — 저장소를 목으로 갈아끼우지 않고
// **진짜 FamilyRepository 에 MockClient 를 꽂는다.** 그래야 JSON·경로·실패 분류까지 지난다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/screens/family_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'refresh-token';

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

Map<String, Object?> _group({String name = '보리네 가족'}) => {
      'id': 3,
      'name': name,
      'roomId': 9,
      'members': [
        {'userId': 1, 'nickname': '아빠', 'role': 'OWNER', 'joinedAt': '2026-09-01T00:00:00Z'},
      ],
    };

/// 처음에는 그룹이 없고, 만들고 나면 생긴다 — 실제 서버가 그렇게 움직인다.
({FamilyRepository repo, List<http.Request> writes, int Function() creates}) fixture({
  int createStatus = 201,
}) {
  final writes = <http.Request>[];
  var created = false;
  var creates = 0;

  final client = AuthedClient(
    inner: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/groups') {
        writes.add(request);
        creates++;
        if (createStatus != 201) return _json({'error': {}}, status: createStatus);
        created = true;
        return _json(_group(), status: 201);
      }
      if (path == '/api/groups/me') {
        return created ? _json(_group()) : _json({'error': {}}, status: 404);
      }
      if (path.endsWith('/walk-notes')) {
        return _json({'body': '', 'updatedBy': null, 'updatedAt': null});
      }
      if (path.endsWith('/care-logs')) return _json(const []);
      if (path.endsWith('/invites')) return _json({'code': 'PAW-1234'});
      return _json({'error': {}}, status: 404);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );

  return (
    repo: FamilyRepository(baseUrl: _base, client: client),
    writes: writes,
    creates: () => creates,
  );
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('그룹이 없으면 만들기와 참여가 둘 다 보인다 — 예전에는 아무 버튼도 없었다',
      (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(FamilyScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('아직 가족 그룹이 없어요'), findsOneWidget);
    expect(find.text('가족 그룹 만들기'), findsOneWidget);
    expect(find.text('초대 코드로 참여하기'), findsOneWidget,
        reason: '만드는 쪽만 있으면 혼자 쓰는 그룹이 된다(#196 의 3번)');
    expect(find.text('다시 시도'), findsNothing,
        reason: '가족이 없는 것은 오류가 아니다 — 다시 눌러도 영원히 같다');
  });

  testWidgets('이름을 넣고 만들면 POST /api/groups 가 나가고 목록이 다시 온다',
      (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(FamilyScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('가족 그룹 만들기'));
    await tester.pumpAndSettle();

    // 기본값이 들어 있어 그대로 눌러도 된다.
    expect(find.widgetWithText(TextField, '우리 가족'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '보리네 가족');
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(f.creates(), 1);
    expect(jsonDecode(f.writes.single.body)['name'], '보리네 가족');
    expect(find.text('아직 가족 그룹이 없어요'), findsNothing,
        reason: '만든 뒤에는 그룹 화면이 떠야 한다');
  });

  testWidgets('만들면 초대 코드가 바로 뜬다 — 혼자 있는 그룹은 아무 일도 안 한다',
      (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(FamilyScreen(repository: f.repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가족 그룹 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(find.text('PAW-1234'), findsOneWidget,
        reason: '초대는 POST /api/chat/rooms/{roomId}/invites 다 — 만들기 응답에는 없다(ADR-0011)');
  });

  testWidgets('이름이 비면 시트 안에서 막힌다 — 스낵바가 아니다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(FamilyScreen(repository: f.repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가족 그룹 만들기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(find.text('가족 이름을 적어 주세요'), findsOneWidget);
    expect(f.creates(), 0, reason: '보내면 400 을 받고 온다');
    expect(find.byType(SnackBar), findsNothing,
        reason: '폼에서 스낵바는 입력칸을 가린다');
  });

  testWidgets('이미 가족이 있으면 409 를 그 뜻대로 말한다 — 연결 문제가 아니다',
      (tester) async {
    final f = fixture(createStatus: 409);

    await tester.pumpWidget(_host(FamilyScreen(repository: f.repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가족 그룹 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(find.text(FamilyFailure.messageFor(FamilyFailureKind.alreadyInGroup)),
        findsOneWidget);
    expect(find.textContaining('연결이 불안정해요'), findsNothing,
        reason: '409 를 network 로 뭉치면 "다시 시도" 를 권하는데 다시 눌러도 영원히 같다');
  });

  testWidgets('홈의 오늘의 케어 카드가 가족이 없을 때 만들기로 보낸다', (tester) async {
    final f = fixture();
    var opened = 0;

    await tester.pumpWidget(_host(
      TodayCareCard(repository: f.repo, onOpenFamily: () => opened++),
    ));
    await tester.pumpAndSettle();

    expect(find.text('아직 가족 그룹이 없어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);

    await tester.tap(find.text('만들기'));
    await tester.pump();

    expect(opened, 1, reason: '여기서 길이 끊겨 있었다 — 문구만 있고 누를 곳이 없었다');
  });
}
