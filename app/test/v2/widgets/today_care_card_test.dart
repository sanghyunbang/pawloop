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

Map<String, Object?> _log({
  required int id,
  required String type,
  required String who,
  required String at,
}) =>
    {
      'id': id,
      'dogId': null,
      'groupId': 3,
      'type': type,
      'doneBy': {'userId': 11, 'nickname': who},
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

    await tester.tap(find.text('밥'));
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

    await tester.tap(find.text('밥'));
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

    await tester.tap(find.text('밥'));
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

    await tester.tap(find.text('밥'));
    await tester.pumpAndSettle();

    expect(
      find.text('오늘 이미 기록이 있어요'),
      findsNothing,
      reason: '아무 때나 확인을 물으면 사람은 곧 읽지 않고 누른다 — 그러면 진짜 경고도 안 읽는다',
    );
    expect(f.posts, hasLength(1));
  });

  testWidgets('누가·언제가 칸에 함께 보인다 — 체크 표시만으로는 이중 급여를 못 막는다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 1, type: 'walk', who: '엄마', at: '2026-08-30T07:05:00'),
    ]);
    await pumpCard(tester, f.repo);

    // 이름과 시각은 두 줄이다 — 한 줄 "엄마 · 07:05" 는 다섯 칸 폭에서 잘렸다(#326).
    expect(find.text('엄마'), findsOneWidget);
    expect(find.text('07:05'), findsOneWidget);
    expect(find.text('아직'), findsNWidgets(4), reason: '다섯 칸 중 넷은 아직이다');
  });

  // ── 잘못 찍은 내 기록 지우기 (#209 Groups-medium-1) ──────────────────────

  testWidgets('내 기록이 있는 칸을 길게 누르면 지울지 묻고, "지우기" 를 누르면 DELETE 를 보낸다',
      (tester) async {
    final f = fixture(logs: [
      _log(id: 7, type: 'meal', who: '나', at: '2026-08-30T14:20:00'),
    ]);
    await pumpCard(tester, f.repo, myUserId: 11); // _log 의 doneBy.userId 가 11 이다

    await tester.longPress(find.text('밥'));
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

    await tester.longPress(find.text('밥'));
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

    await tester.longPress(find.text('산책'));
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

    await tester.tap(find.text('물'));
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

    await tester.tap(find.text('밥'));
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

    await tester.tap(find.text('밥'));
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

    await tester.tap(find.text('산책'));
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
}
