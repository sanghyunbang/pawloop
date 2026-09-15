// "오늘의 케어" 카드 — **확인 문구가 실제로 뜨는 것**을 잠근다 (이슈 #76 완료 조건 2).
//
// 서버는 같은 종류를 하루에 두 번 찍어도 막지 않는다(백엔드
// `CareSharingIntegrationTest.feedingTwiceInOneDay_keepsBothRows` 가 그것을 잠근다).
// 그래서 "그래도 기록할까요?" 를 띄우는 책임이 **앱에만** 있고, 그 문구가 사라지면
// 어느 백엔드 테스트도 빨간불이 되지 않는다 — 이 파일이 그 자리다.
//
// 가짜 저장소를 만들지 않고 **진짜 FamilyRepository 에 MockClient 를 꽂는다.**
// 그래야 JSON 파싱·경로·실패 분류까지 한 번에 지난다. 저장소를 목으로 갈아끼우면
// "응답을 잘못 읽는" 회귀가 이 테스트를 그대로 통과한다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/theme/app_tokens.dart';
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

/// [userId] 를 안 주면 **나(11)** 다 — 이 파일의 테스트 대부분이 "내 기록" 을 재기 때문이다.
///
/// 이름만 바꾸고 id 를 그대로 두면 **한 계정이 이름 둘을 가진 셈**이 된다. 계약은 한
/// `userId` 에 닉네임 하나라, 두 사람이 필요한 테스트는 id 도 나눠야 한다(#570).
Map<String, Object?> _log({
  required int id,
  required String type,
  required String who,
  required String at,
  int userId = 11,
}) =>
    {
      'id': id,
      'dogId': null,
      'groupId': 3,
      'type': type,
      'doneBy': {'userId': userId, 'nickname': who},
      'occurredAt': at,
      'memo': null,
    };

/// 오늘 14:20 에 아빠가 밥을 준 가족 하나.
({FamilyRepository repo, List<http.Request> posts, List<http.Request> deletes}) fixture({
  List<Map<String, Object?>>? logs,
  int careLogsStatus = 200,
}) {
  final posts = <http.Request>[];
  final deletes = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
      }
      if (request.method == 'DELETE') {
        deletes.add(request);
        return http.Response('', 204);
      }
      if (request.method == 'POST') {
        posts.add(request);
        return _json(
          _log(id: 99, type: 'meal', who: '나', at: '2026-08-30T20:00:00'),
          status: 201,
        );
      }
      if (careLogsStatus != 200) {
        return _json({'error': {}}, status: careLogsStatus);
      }
      return _json(logs ?? const []);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    repo: FamilyRepository(baseUrl: _base, client: client),
    posts: posts,
    deletes: deletes,
  );
}

Future<void> pumpCard(WidgetTester tester, FamilyRepository repo, {int? myUserId}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: TodayCareCard(repository: repo, myUserId: myUserId)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('오늘 이미 기록이 있으면 확인 문구가 뜬다 — "오늘 14:20 아빠가 밥을 줬습니다"',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'meal', who: '아빠', at: '2026-08-30T14:20:00'),
    ]);
    await pumpCard(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();

    expect(
      find.text('오늘 14:20 아빠가 밥을 줬습니다. 그래도 기록할까요?'),
      findsOneWidget,
      reason: '이 문구가 완료 조건 2 그 자체다. 서버는 두 번째를 막지 않으므로 '
          '여기가 사라지면 아무 데서도 안 막힌다',
    );
    expect(f.posts, isEmpty, reason: '확인을 받기 전에 보내면 그게 곧 "막지도 알리지도 않는" 것이다');
  });

  testWidgets('취소하면 기록하지 않는다', (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'meal', who: '아빠', at: '2026-08-30T14:20:00'),
    ]);
    await pumpCard(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(f.posts, isEmpty);
  });

  testWidgets('"그래도 기록" 을 누르면 서버로 보낸다 — 막는 것이 아니라 알리는 것이다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'meal', who: '아빠', at: '2026-08-30T14:20:00'),
    ]);
    await pumpCard(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그래도 기록'));
    await tester.pumpAndSettle();

    expect(f.posts, hasLength(1));
    expect(f.posts.single.url.path, '/api/groups/3/care-logs');
    expect(jsonDecode(f.posts.single.body), {'type': 'meal'});
  });

  testWidgets('오늘 기록이 없으면 확인 문구 없이 바로 기록한다', (tester) async {
    final f = fixture(logs: const []);
    await pumpCard(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();

    expect(
      find.text('오늘 이미 기록이 있어요'),
      findsNothing,
      reason: '아무 때나 확인을 물으면 사람은 곧 읽지 않고 누른다 — 그러면 진짜 경고도 안 읽는다',
    );
    expect(f.posts, hasLength(1));
  });

  testWidgets('누가·언제가 칸에 함께 보인다 — 체크 표시만으로는 이중 급여를 못 막는다',
      (t) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'walk', who: '엄마', at: '2026-08-30T07:05:00'),
    ]);
    await pumpCard(t, f.repo);

    // 이름과 시각은 두 줄이다 — 한 줄 "엄마 · 07:05" 는 다섯 칸 폭에서 잘렸다(#326).
    //
    // **칸 안에서 찾는다**(#570). 아래 "오늘 한 일" 줄에도 같은 이름과 시각이 있어서
    // `find.text` 로는 둘이 안 갈린다.
    expect(t.widget<Text>(find.byKey(const Key('care-line1-walk'))).data, '엄마');
    expect(t.widget<Text>(find.byKey(const Key('care-line2-walk'))).data, '07:05');
    expect(find.text('아직'), findsNWidgets(6), reason: '일곱 칸 중 여섯은 아직이다');
  });

  // ── 잘못 찍은 내 기록 지우기 (#209 Groups-medium-1) ──────────────────────

  testWidgets('내 기록이 있는 칸을 길게 누르면 지울지 묻고, "지우기" 를 누르면 DELETE 를 보낸다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'meal', who: '나', at: '2026-08-30T14:20:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 11); // _log 의 doneBy.userId 가 11 이다

    await tester.longPress(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();

    expect(find.text('기록을 지울까요?'), findsOneWidget);
    expect(find.text('14:20 에 남긴 밥 기록을 지웁니다. 가족 화면에서도 사라져요.'), findsOneWidget,
        reason: '칸에는 최근 하나만 보이므로 무엇을 지우는지 문구가 말해야 한다');
    expect(f.deletes, isEmpty, reason: '확인 전에는 보내지 않는다');

    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(f.deletes, hasLength(1));
    expect(f.deletes.single.url.path, '/api/groups/3/care-logs/7');
    expect(f.posts, isEmpty, reason: '길게 누르는 것은 기록이 아니다');
  });

  testWidgets('취소하면 지우지 않는다', (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'meal', who: '나', at: '2026-08-30T14:20:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 11);

    await tester.longPress(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(f.deletes, isEmpty);
  });

  testWidgets('남의 기록은 길게 눌러도 묻지 않고 안내만 한다 — 지울 수 있으면 산책 누락이 그 자리에서 생긴다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'walk', who: '엄마', at: '2026-08-30T07:05:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 22); // 엄마(11)가 아니다

    await tester.longPress(find.byKey(const Key('care-cell-walk')));
    await tester.pumpAndSettle();

    expect(find.text('기록을 지울까요?'), findsNothing);
    expect(find.text('내가 남긴 기록만 지울 수 있어요'), findsOneWidget);
    expect(f.deletes, isEmpty, reason: '서버도 403 이지만 보내기 전에 여기서 멈춘다');
  });

  // ── 다시 누르면 무른다 (#329) ──────────────────────────────────────

  testWidgets('내 기록이 있는 칸을 다시 누르면 지울지 묻고, "지우기" 면 DELETE 가 나간다 — POST 는 없다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'water', who: '나', at: '2026-08-30T15:40:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 11);

    await tester.tap(find.byKey(const Key('care-cell-water')));
    await tester.pumpAndSettle();

    expect(find.text('이미 기록한 칸이에요'), findsOneWidget);
    expect(
      find.text('오늘 15:40 에 내가 남긴 물 기록이에요. 잘못 눌렀다면 지우고, 한 번 더 한 거면 다시 기록해요.'),
      findsOneWidget,
    );
    expect(find.text('그래도 기록'), findsNothing, reason: '내 기록에는 "이미 있음" 경고가 아니라 무르기다');
    expect(f.deletes, isEmpty, reason: '고르기 전에는 보내지 않는다');

    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(f.deletes, hasLength(1));
    expect(f.deletes.single.url.path, '/api/groups/3/care-logs/7');
    expect(f.posts, isEmpty);
  });

  testWidgets('"한 번 더 기록" 이면 POST 가 나간다 — 두 끼는 실제로 있다', (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'meal', who: '나', at: '2026-08-30T08:10:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 11);

    await tester.tap(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한 번 더 기록'));
    await tester.pumpAndSettle();

    expect(f.posts, hasLength(1));
    expect(jsonDecode(f.posts.single.body), {'type': 'meal'});
    expect(f.deletes, isEmpty);
  });

  testWidgets('"취소" 면 아무것도 보내지 않는다', (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'meal', who: '나', at: '2026-08-30T08:10:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 11);

    await tester.tap(find.byKey(const Key('care-cell-meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(f.posts, isEmpty);
    expect(f.deletes, isEmpty);
  });

  testWidgets('남의 기록이 있는 칸은 다시 눌러도 지우기가 없다 — "그래도 기록" 만 묻는다', (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'walk', who: '엄마', at: '2026-08-30T07:05:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 22); // 엄마(11)가 아니다

    await tester.tap(find.byKey(const Key('care-cell-walk')));
    await tester.pumpAndSettle();

    expect(find.text('그래도 기록'), findsOneWidget);
    expect(find.text('지우기'), findsNothing, reason: '지울 수 있으면 산책 누락이 그 자리에서 생긴다');
  });

  testWidgets('네트워크가 없으면 빈 카드가 아니라 실패 문구와 다시 시도를 그린다',
      (tester) async {
    final f = fixture(careLogsStatus: 500);
    await pumpCard(tester, f.repo);

    expect(
      find.text('연결이 불안정해요 · 다시 시도'),
      findsOneWidget,
      reason: '빈 카드로 그리면 "아무도 아무것도 안 했다" 로 읽히고, 그걸 보고 밥을 한 번 더 준다',
    );
    expect(find.text('아직'), findsNothing);
  });

  testWidgets('아직 가족이 없으면 오류가 아니라 안내다', (tester) async {
    final client = AuthedClient(
      inner: MockClient((_) async => _json({'error': {}}, status: 404)),
      baseUrl: _base,
      store: _FakeTokenStore(),
    );
    await pumpCard(tester, FamilyRepository(baseUrl: _base, client: client));

    expect(find.text('아직 가족 그룹이 없어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing,
        reason: '다시 시도해도 가족이 생기지 않는다 — 할 일이 다르면 문구도 달라야 한다');
  });

  group('문구 조립', () {
    test('종류마다 서술어가 다르다', () {
      String warn(ServerCareType type) => duplicateWarning(CareLogEntry(
            id: 1,
            type: type,
            doneByUserId: 1,
            doneByName: '아빠',
            occurredAt: DateTime(2026, 8, 30, 9, 5),
          ));

      expect(warn(ServerCareType.walk), '오늘 09:05 아빠가 산책을 다녀왔습니다. 그래도 기록할까요?');
      expect(warn(ServerCareType.vet), '오늘 09:05 아빠가 병원에 다녀왔습니다. 그래도 기록할까요?');
    });

    test('주격 조사는 받침으로 고른다 — "지훈가" 가 되면 안 된다', () {
      expect(subjectParticle('아빠'), '가');
      expect(subjectParticle('지훈'), '이');
      expect(subjectParticle('Dad'), '가', reason: '한글이 아니면 기본값이다');
      expect(subjectParticle(''), '가');
    });
  });

  // ── 색 (#546) ───────────────────────────────────────────────────────

  testWidgets('완료한 칸은 종류와 상관없이 코랄 하나다 (#546)', (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'water', who: '아빠', at: '2026-08-30T09:10:00'),
      _log(id: 2, type: 'med', who: '엄마', at: '2026-08-30T09:20:00'),
    ]);
    await pumpCard(tester, f.repo);

    Color checkOf(String wire) => tester
        .widget<Icon>(find.descendant(
            of: find.byKey(Key('care-cell-$wire')), matching: find.byType(Icon)))
        .color!;

    expect(checkOf('water'), T.accent, reason: '물은 파랑(#5B8DEF)이었다');
    expect(checkOf('med'), T.accent,
        reason: '''
투약은 라일락(#9B7BFF)이었다 — 사장님이 내리신 색이다. 토큰 머리말이 정한 색 예외는
지도 카테고리색과 상태색뿐이고 케어는 거기 없다 (#546).''');
    expect(checkOf('water'), checkOf('med'),
        reason: '종류마다 색을 다시 나누면 한 줄에 파랑·라일락·초록이 다시 선다');
  });

  testWidgets('완료한 칸의 바탕과 테두리도 토큰에서 온다 (#546)', (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'water', who: '아빠', at: '2026-08-30T09:10:00'),
    ]);
    await pumpCard(tester, f.repo);

    final box = tester
        .widget<Container>(find.byKey(const Key('care-cell-water')))
        .decoration! as BoxDecoration;

    expect(box.color, T.accentSoft);
    expect((box.border as Border).top.color, T.accentLine);
  });

  testWidgets('안 한 칸은 회색 그대로다 — 색이 말하는 것은 "했다" 다', (tester) async {
    final f = fixture(logs: const []);
    await pumpCard(tester, f.repo);

    final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('care-cell-water')), matching: find.byType(Icon)));

    expect(icon.color, T.textMuted);
  });

  // ── 배변·마킹 (#549) ────────────────────────────────────────────────

  testWidgets('배변 칸은 이름 대신 "몇 번" 을 말한다 — 하루에 여러 번이 정상이다 (#549)',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'poop', who: '엄마', at: '2026-08-30T07:05:00'),
      _log(id: 2, type: 'poop', who: '아빠', at: '2026-08-30T18:40:00'),
    ]);
    await pumpCard(tester, f.repo);

    expect(find.byKey(const Key('care-line1-poop')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('care-line1-poop'))).data, '2회',
        reason: '배변은 건강 신호라 "오늘 몇 번" 이 실제로 세는 값이다 — 누가 봤는지가 아니다');
    expect(find.text('18:40'), findsOneWidget, reason: '가장 최근 시각은 그대로 둔다');
  });

  testWidgets('물 칸은 한 번이면 누가 했는지를 말한다 — 두 번 주지 않으려고 보는 자리다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'water', who: '아빠', at: '2026-08-30T09:10:00'),
    ]);
    await pumpCard(tester, f.repo);

    expect(tester.widget<Text>(find.byKey(const Key('care-line1-water'))).data, '아빠');
  });

  // ── 횟수는 배변·마킹만의 것이 아니다 (#561) ─────────────────────────

  testWidgets('밥을 두 번 줬으면 칸이 "2회" 라고 말한다 — 예전에는 마지막 사람 이름뿐이었다 (#561)',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'meal', who: '엄마', at: '2026-08-30T08:00:00', userId: 22),
      _log(id: 2, type: 'meal', who: '아빠', at: '2026-08-30T19:00:00'),
    ]);
    await pumpCard(tester, f.repo);

    expect(tester.widget<Text>(find.byKey(const Key('care-line1-meal'))).data, '2회',
        reason: '두 번째를 막으려고 보는 자리인데, 두 번 줬다는 사실이 화면에 없었다');
    // **#570 이 바꿨다.** 두 번 이상이면 시각이 아니라 사람이다 — `2회 · 19:00` 만으로는
    // 둘이 한 번씩인지 한 사람이 두 번인지 알 수 없어서 분담이 안 보였다.
    expect(tester.widget<Text>(find.byKey(const Key('care-line2-meal'))).data, '아빠·엄마',
        reason: '분담을 보이게 하려던 칸이 분담을 가리면 안 된다');
  });

  testWidgets('물도 세 번이면 "3회" 다 — 종류마다 다른 규칙을 두지 않는다 (#561)',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'water', who: '엄마', at: '2026-08-30T08:00:00'),
      _log(id: 2, type: 'water', who: '엄마', at: '2026-08-30T13:00:00'),
      _log(id: 3, type: 'water', who: '아빠', at: '2026-08-30T19:00:00'),
    ]);
    await pumpCard(tester, f.repo);

    expect(tester.widget<Text>(find.byKey(const Key('care-line1-water'))).data, '3회');
  });

  testWidgets('한 번이면 횟수를 안 적는다 — "1회" 는 체크 표시가 이미 말한 것이다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'poop', who: '엄마', at: '2026-08-30T07:05:00'),
    ]);
    await pumpCard(tester, f.repo);

    expect(tester.widget<Text>(find.byKey(const Key('care-line1-poop'))).data, '엄마');
  });

  testWidgets('아직 안 한 칸도 둘째 줄 자리를 지킨다 — 누를 때마다 칸이 자라면 안 된다 (#561)',
      (tester) async {
    final f = fixture(logs: const []);
    await pumpCard(tester, f.repo);

    expect(tester.widget<Text>(find.byKey(const Key('care-line1-meal'))).data, '아직');
    expect(tester.widget<Text>(find.byKey(const Key('care-line2-meal'))).data, '',
        reason: '빈 줄이 자리를 지킨다 — 없애면 누르는 순간 그 줄의 이웃이 통째로 밀린다');
  });

  testWidgets('배변·마킹 칸이 카드에 있다 — 예전에는 care_log 에 쌓이기만 했다 (#549)',
      (tester) async {
    final f = fixture(logs: const []);
    await pumpCard(tester, f.repo);

    expect(find.text('배변'), findsOneWidget);
    expect(find.text('마킹'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '두 줄로 접어 390dp 에서 안 넘친다');
  });

    test('카드의 칸은 손으로 적은 일곱이다 — 서버 종류가 늘어도 저절로 늘지 않는다 (#340 · #549)', () {
    expect(
      kCareCardColumns,
      const [
        ServerCareType.water,
        ServerCareType.meal,
        ServerCareType.walk,
        ServerCareType.med,
        ServerCareType.vet,
        ServerCareType.poop,
        ServerCareType.pee,
      ],
      reason: """
예전에는 ServerCareType.values 를 그대로 돌려서, 배변·마킹이 계약에 생기자 칸이 저절로
늘었다. 화면에 무엇을 보일지는 계약이 아니라 이 화면이 정할 일이라 목록을 손으로 적는다.
배변·마킹은 2026-09-15 에 다시 넣었다(#549) — 빼 두는 동안 care_log 에 쌓이기만 하고 앱
어디에서도 볼 수 없었다. 순서는 그대로 두고 뒤에 붙인다.""",
    );
  });

  testWidgets('390dp 에서 칸 하나가 70px 아래로 좁아지지 않는다 (#326 · #549)', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = fixture(logs: const []);
    await pumpCard(tester, f.repo);

    final width = tester.getSize(find.byKey(const Key('care-cell-poop'))).width;

    expect(width, greaterThanOrEqualTo(70),
        reason: '''
칸이 좁아지면 라벨이 먼저 잘린다 — 다섯 칸일 때 "walker · 15:40" 이 그래서 두 줄이 됐다(#326).
일곱을 한 줄에 넣으면 46px 이라 이름도 시각도 못 읽는다. 넘침 경고는 안 뜨므로(칸 안에서
잘린다) 이 단언이 그 자리를 지킨다.''');
    expect((kCareCardColumns.length / kCareCardColumnsPerRow).ceil(), 2,
        reason: '세 줄이 되면 카드가 화면의 절반을 먹는다 — 그때는 배치를 다시 본다');
  });
}
