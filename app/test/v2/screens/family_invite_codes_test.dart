// 초대코드를 다시 볼 수 있는가, 회수할 수 있는가 — 이슈 #625.
//
// 2026-09-17 에 물음이 나왔다.
//
//   > 맨 처음에 WCME3-86ZE9 이런 값을 주는데 이걸 처음에만 보고 나중에 다시 보고 싶으면
//   > 어떻게 보라는거야? 그대로 소실되어 버리는거야?
//
// 발급·회수·참여만 있고 **조회가 없었다.** 시트를 닫으면 코드가 앱 어디에도 안 남았고,
// 확인하려면 새로 발급하는 수밖에 없었다 — 그런데 발급은 이전 코드를 안 죽인다(#75).
// 누를 때마다 살아 있는 코드가 하나씩 늘고, 회수는 코드를 알아야 부르므로 **쌓인 것을
// 되돌릴 길도 없었다.**
//
// `family_screen_test.dart` 와 같은 방식이다 — 저장소를 목으로 갈지 않고 **진짜
// FamilyRepository 에 MockClient 를 꽂는다.** 그래야 경로·파싱·실패 분류까지 지난다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/screens/family_screen.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT';
  @override
  Future<String?> readRefreshToken() async => 'RT';
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

Map<String, Object?> _invite(String code, {String? expiresAt, int? maxUses}) => {
      'code': code,
      'roomId': 9,
      'expiresAt': expiresAt ?? '2026-09-24T12:00:00Z',
      'maxUses': maxUses,
      'usedCount': 0,
      'createdAt': '2026-09-17T12:00:00Z',
    };

/// 방장 하나짜리 가족. [invitesStatus] 를 403 으로 두면 **방장이 아닌 사람**이 된다.
({FamilyRepository repo, List<String> revoked, int Function() listCalls}) fixture({
  List<Map<String, Object?>>? invites,
  int invitesStatus = 200,
}) {
  final revoked = <String>[];
  var listCalls = 0;
  var live = [...?invites];

  final client = AuthedClient(
    inner: MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/groups/me') {
        return _json({
          'id': 3,
          'name': '보리네 가족',
          'roomId': 9,
          'members': [
            {'userId': 11, 'nickname': '아빠', 'role': 'OWNER'},
          ],
        });
      }
      if (path == '/api/groups/3/walk-notes') {
        return _json({'groupId': 3, 'body': '', 'updatedBy': null, 'updatedAt': null});
      }
      if (path == '/api/chat/rooms/9/invites' && request.method == 'GET') {
        listCalls++;
        if (invitesStatus != 200) return _json({'error': {}}, status: invitesStatus);
        return _json(live);
      }
      if (path.startsWith('/api/chat/rooms/9/invites/') && request.method == 'DELETE') {
        final code = Uri.decodeComponent(path.split('/').last);
        revoked.add(code);
        // 서버가 정본이다 — 회수한 것은 다음 조회에서 빠진다.
        live = [for (final i in live) if (i['code'] != code) i];
        return http.Response('', 204);
      }
      return _json(const []);
    }),
    baseUrl: _base,
    store: _Tokens(),
  );
  return (
    repo: FamilyRepository(baseUrl: _base, client: client),
    revoked: revoked,
    listCalls: () => listCalls,
  );
}

Future<void> _pump(WidgetTester tester, FamilyRepository repo) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: FamilyScreen(repository: repo)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('살아 있는 코드를 화면에서 다시 볼 수 있다', (tester) async {
    final f = fixture(invites: [_invite('WCME3-86ZE9'), _invite('A2C4E-F6H8K')]);
    await _pump(tester, f.repo);

    expect(f.listCalls(), greaterThan(0), reason: '화면을 열면 조회한다');
    expect(find.byKey(const Key('family-invite-codes')), findsOneWidget);
    expect(find.text('WCME3-86ZE9'), findsOneWidget);
    expect(find.text('A2C4E-F6H8K'), findsOneWidget);
    expect(find.text('2개'), findsOneWidget);
    // 사실만 쓴다 — 만료·횟수는 서버가 준 값이다(#329).
    expect(find.textContaining('9월 24일까지 써요'), findsWidgets);
  });

  testWidgets('코드가 없으면 만들라고 말한다 — 빈 카드를 남기지 않는다', (tester) async {
    await _pump(tester, fixture(invites: const []).repo);

    expect(find.byKey(const Key('family-invite-codes')), findsOneWidget);
    expect(find.byKey(const Key('family-invite-codes-empty')), findsOneWidget);
  });

  testWidgets('방장이 아니면 카드가 아예 없다 — 코드는 그 자체가 열쇠다', (tester) async {
    await _pump(tester, fixture(invitesStatus: 403).repo);

    expect(find.byKey(const Key('family-invite-codes')), findsNothing);
    // 화면의 나머지는 그대로다 — 403 하나로 가족 화면이 죽으면 안 된다.
    expect(find.text('아빠'), findsWidgets);
  });

  testWidgets('회수는 먼저 묻고, 확인하면 목록에서 빠진다', (tester) async {
    final f = fixture(invites: [_invite('WCME3-86ZE9'), _invite('A2C4E-F6H8K')]);
    await _pump(tester, f.repo);

    await tester.tap(find.byKey(const Key('invite-action-회수')).first);
    await tester.pumpAndSettle();

    // 되돌릴 수 없는 일이다. 누르기 전에 그 말을 한다.
    expect(find.byKey(const Key('invite-revoke-confirm')), findsOneWidget);
    expect(find.textContaining('이미 들어온 가족은 그대로 있어요'), findsOneWidget);
    expect(f.revoked, isEmpty, reason: '아직 안 눌렀다');

    await tester.tap(find.text('막기'));
    await tester.pumpAndSettle();

    expect(f.revoked, ['WCME3-86ZE9']);
    expect(find.text('WCME3-86ZE9'), findsNothing, reason: '서버를 다시 읽어 목록을 세운다');
    expect(find.text('A2C4E-F6H8K'), findsOneWidget);
  });

  testWidgets('"그대로 두기" 면 아무 일도 안 한다', (tester) async {
    final f = fixture(invites: [_invite('WCME3-86ZE9')]);
    await _pump(tester, f.repo);

    await tester.tap(find.byKey(const Key('invite-action-회수')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('그대로 두기'));
    await tester.pumpAndSettle();

    expect(f.revoked, isEmpty);
    expect(find.text('WCME3-86ZE9'), findsOneWidget);
  });
}
