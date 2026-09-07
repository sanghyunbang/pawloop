// 우리 가족 화면 — **구성원이 서버에서 오는가**와 **주의사항 왕복의 모양**을 잠근다 (이슈 #76).
//
// 이 파일이 생기기 전에는 `family_screen` 전체가 어느 앱 테스트에도 잡히지 않았다.
// `FamilyMemberSummary.fromJson`(userId/nickname/role)·`FamilyGroupSummary.roomId`·
// `isOwner`('OWNER' 문자열 비교)가 전부 단언 없이 남아 있었다 — 서버가 role 을 소문자
// 'owner' 로 바꾸거나 nickname 키 이름이 바뀌면 **모든 사람이 조용히 "가족" 으로 보이고**
// 초대 발급이 잘못된 roomId 로 가는데, 앱 테스트 중 어느 것도 빨간불이 되지 않았다.
//
// `today_care_card_test.dart` 와 같은 방식이다 — 저장소를 목으로 갈아끼우지 않고
// **진짜 FamilyRepository 에 MockClient 를 꽂는다.** 그래야 JSON 파싱·경로·실패 분류까지
// 한 번에 지난다.

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

/// 아빠(방장)와 엄마가 있는 가족 하나. `walkNoteBody` 가 서버에 이미 있는 메모다.
({FamilyRepository repo, List<http.Request> writes}) fixture({
  String walkNoteBody = '계단 피하기',
  int walkNotePutStatus = 200,
}) {
  final writes = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        return _json({
          'id': 3,
          'name': '보리네 가족',
          'roomId': 9,
          'members': [
            {'userId': 11, 'nickname': '아빠', 'role': 'OWNER'},
            {'userId': 12, 'nickname': '엄마', 'role': 'MEMBER'},
          ],
        });
      }
      if (request.url.path == '/api/groups/3/walk-notes') {
        if (request.method == 'PUT') {
          writes.add(request);
          if (walkNotePutStatus != 200) {
            return _json({'error': {}}, status: walkNotePutStatus);
          }
          return _json({
            'groupId': 3,
            'body': jsonDecode(request.body)['body'],
            'updatedBy': {'userId': 11, 'nickname': '아빠'},
            'updatedAt': '2026-08-30T14:20:00',
          });
        }
        return _json({
          'groupId': 3,
          'body': walkNoteBody,
          'updatedBy': {'userId': 11, 'nickname': '아빠'},
          'updatedAt': '2026-08-30T14:20:00',
        });
      }
      // 오늘의 케어는 이 파일의 관심사가 아니다 — today_care_card_test 가 본다.
      return _json(const []);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: FamilyRepository(baseUrl: _base, client: client), writes: writes);
}

/// 화면 전체가 한 번에 빌드되도록 키 큰 뷰포트를 준다.
///
/// 기본 800×600 에서는 `ListView` 의 아래쪽 카드(주의사항)가 아예 만들어지지 않아
/// "없다" 와 "화면 밖이다" 가 구별되지 않는다.
Future<void> pumpScreen(WidgetTester tester, FamilyRepository repo) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: FamilyScreen(repository: repo)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('구성원이 서버 응답 그대로 그려진다 — OWNER 는 방장, MEMBER 는 가족',
      (tester) async {
    await pumpScreen(tester, fixture().repo);

    // 이름은 구성원 카드와 거리 카드 두 곳에 나온다 — 개수가 아니라 '서버에서 왔는가' 를 본다.
    expect(find.text('아빠'), findsWidgets);
    expect(find.text('엄마'), findsWidgets);
    expect(
      find.text('방장'),
      findsOneWidget,
      reason: "isOwner 는 대문자 'OWNER' 비교다 — 서버가 소문자로 바뀌면 "
          '모두가 조용히 "가족" 으로 보인다',
    );
    expect(
      find.text('가족'),
      findsOneWidget,
      reason: '역할 이름표는 구성원 수만큼 나온다 — 둘 중 하나만 방장이다',
    );
  });

  testWidgets('서버의 주의사항이 줄 단위로 그려진다 — 한 장을 목록으로 보는 것은 화면의 표현이다',
      (tester) async {
    await pumpScreen(tester, fixture(walkNoteBody: '계단 피하기\n리드줄 짧게').repo);

    expect(find.text('계단 피하기'), findsOneWidget);
    expect(find.text('리드줄 짧게'), findsOneWidget);
  });

  testWidgets('주의사항 추가는 {body:"..."} 한 장으로 PUT 된다 — {notes:[...]} 가 아니다',
      (tester) async {
    final f = fixture();
    await pumpScreen(tester, f.repo);

    await tester.tap(find.text('주의사항 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '더운 날은 저녁 8시 이후에');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(f.writes.single.method, 'PUT');
    expect(
      jsonDecode(f.writes.single.body),
      {'body': '계단 피하기\n더운 날은 저녁 8시 이후에'},
      reason: '서버가 아는 것은 메모 한 장이라 추가도 전체 교체다',
    );
  });

  testWidgets('합계 500자를 넘으면 왕복 전에 막고 이유를 말한다 — "연결이 불안정해요" 가 아니다',
      (tester) async {
    final f = fixture(walkNoteBody: '가' * FamilyRepository.maxTextLength);
    await pumpScreen(tester, f.repo);

    await tester.tap(find.text('주의사항 추가'));
    await tester.pumpAndSettle();

    expect(
      find.text(FamilyFailure.messageFor(FamilyFailureKind.invalid)),
      findsOneWidget,
      reason: "가족이 줄을 쌓아 합계가 한도를 넘는 순간부터 '추가하기' 는 매번 실패한다. "
          '그때 사용자가 보던 문구는 "연결이 불안정해요 · 다시 시도" 였다 — 네트워크는 '
          '멀쩡하고 다시 눌러도 영원히 같은 결과다. 원인(글자 수)이 화면 어디에도 없으면 '
          '사용자가 할 수 있는 일이 없다.',
    );
    expect(
      f.writes,
      isEmpty,
      reason: '실패할 것을 알면서 보내지 않는다 — 서버의 400 은 마지막 방어선이지 첫 안내가 아니다',
    );
  });

  testWidgets('합계가 정확히 500자가 되는 줄은 그대로 저장된다 — 가드가 정당한 입력을 막지 않는다',
      (tester) async {
    // 이미 498자를 썼다. 줄바꿈 한 칸을 빼면 이번 줄의 예산은 1자다.
    final f = fixture(walkNoteBody: '가' * 498);
    await pumpScreen(tester, f.repo);

    await tester.tap(find.text('주의사항 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '나');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(f.writes, hasLength(1), reason: '한도 안이면 보낸다 — 가드가 과하면 쓸 수 있는 글도 못 쓴다');
    expect(
      (jsonDecode(f.writes.single.body)['body'] as String).length,
      FamilyRepository.maxTextLength,
      reason: '화면이 허락한 길이가 그대로 저장돼야 한다 — 예산 계산에서 줄바꿈을 빼먹으면 501자가 나간다',
    );
  });

  testWidgets('서버가 400 을 주면 그 이유가 뜬다 — 클라이언트 가드가 뚫려도 network 로 뭉치지 않는다',
      (tester) async {
    // 앱과 서버의 한도가 어긋난 상태를 흉내 낸다(둘 중 하나만 늘어나는 날이 온다).
    final f = fixture(walkNotePutStatus: 400);
    await pumpScreen(tester, f.repo);

    await tester.tap(find.text('주의사항 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '리드줄 짧게');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(f.writes, hasLength(1));
    expect(
      find.text(FamilyFailure.messageFor(FamilyFailureKind.invalid)),
      findsOneWidget,
    );
  });

  // ── "연동 전" 카드 없음 · 주의사항 "…" 메뉴 (#329) ──────────────────

  testWidgets('"오늘 걸은 거리" 카드가 없다 — 미완성을 사용자에게 보이지 않는다', (tester) async {
    await pumpScreen(tester, fixture().repo);

    expect(find.text('오늘 걸은 거리'), findsNothing);
    expect(find.textContaining('연동 전'), findsNothing);
    expect(find.text('길게 눌러 삭제'), findsNothing, reason: '지우는 문은 줄마다 붙은 "…" 메뉴다');
  });

  testWidgets('주의사항 줄의 "…" → 지우기 → 확인이면 그 줄이 빠진 한 장이 PUT 된다', (tester) async {
    final f = fixture(walkNoteBody: '계단 피하기\n리드줄 짧게');
    await pumpScreen(tester, f.repo);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(find.text('삭제할까요?'), findsOneWidget, reason: '가족 모두에게서 사라지는 일이라 한 번 더 묻는다');
    expect(f.writes, isEmpty);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(f.writes.single.method, 'PUT');
    expect(jsonDecode(f.writes.single.body), {'body': '리드줄 짧게'});
  });
}
