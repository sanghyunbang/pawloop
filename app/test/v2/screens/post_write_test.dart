// 커뮤니티 글쓰기 화면 — 이슈 #172, 그리고 빈 상태 문구 #173.
//
// `community_feed_test.dart` 와 같은 방식이다 — 리포지토리를 목으로 갈아끼우지 않고
// **진짜 CommunityRepository 에 MockClient 를 꽂는다.** 그래야 폼이 만든 본문이 계약의
// 키로 나가는지까지 한 번에 지난다.
//
// 로그인 게이트(`writePost`)는 여기서 안 지난다 — 그 함수는 `AuthState` 전역을 읽고
// `LoginScreen` 을 밀기 때문이다. 화면 자체를 직접 띄워 폼의 규칙만 본다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';

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

Map<String, Object?> _createdPost() => {
      'id': 9,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'pet_place',
      'loc': '서울숲',
      'contentId': '126508',
      'title': '제목',
      'body': '본문',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-03T10:00:00Z',
    };

({CommunityRepository repo, List<Map<String, Object?>> sent}) fixture({
  int status = 201,
}) {
  final sent = <Map<String, Object?>>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/api/community/posts') {
        sent.add(jsonDecode(request.body) as Map<String, Object?>);
        if (status != 201) return _json({}, status: status);
        return _json(_createdPost(), status: 201);
      }
      return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CommunityRepository(baseUrl: _base, client: client), sent: sent);
}

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  // 이 파일의 단언들은 **서버 전송이 켜진 빌드**를 잰다 — 좌표 순서·키 이름·charset 같은
  // 것들은 정책과 무관한 계약이고, 정책이 꺼져 있으면 요청 자체가 안 나가서 잴 수 없다.
  // 꺼진 쪽은 location_upload_policy_test.dart 가 잰다. (#235)
  setUp(() => LocationUploadPolicy.setForTest(true));
  tearDown(LocationUploadPolicy.resetForTest);

  testWidgets('게시판 선택지가 다섯이고 전체가 없다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    for (final board in CommunityBoard.values) {
      expect(find.text(board.label), findsOneWidget);
    }
    expect(CommunityBoard.values, hasLength(5));
    expect(find.text('전체'), findsNothing,
        reason: "'전체' 는 목록의 필터이지 글이 올라갈 곳이 아니다");
  });

  testWidgets('제목이 비면 제출이 막히고 이유가 화면에 뜬다 — 스낵바가 아니다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '본문만 적었다');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(find.text('제목을 적어 주세요'), findsOneWidget);
    expect(f.sent, isEmpty, reason: '서버로 안 보낸다 — 보내면 400 을 받고 온다');
    expect(find.byType(SnackBar), findsNothing,
        reason: '폼에서 스낵바는 입력칸을 가린다. v2 의 폼은 빨간 한 줄로 말한다');
  });

  testWidgets('본문이 비어도 막힌다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '제목만 적었다');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(find.text('본문을 적어 주세요'), findsOneWidget);
    expect(f.sent, isEmpty);
  });

  testWidgets('공백만 적은 것은 빈 것과 같다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.enterText(find.byType(TextField).last, '본문');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(find.text('제목을 적어 주세요'), findsOneWidget);
    expect(f.sent, isEmpty);
  });

  testWidgets('제출하면 계약의 키로 나가고 화면이 새 글을 돌려준다', (tester) async {
    final f = fixture();
    CommunityPost? returned;

    await tester.pumpWidget(_host(
      Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            returned = await Navigator.of(context).push<CommunityPost>(
              MaterialPageRoute(
                builder: (_) => PostWriteScreen(repository: f.repo),
              ),
            );
          },
          child: const Text('열기'),
        );
      }),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('동반장소'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '성수동 카페');
    await tester.enterText(find.byType(TextField).last, '동반 가능해요');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(f.sent.single['board'], 'pet_place',
        reason: 'ADR-0016 이 정한 ASCII 키다. 한글 라벨이 나가면 서버가 400 을 낸다');
    expect(f.sent.single['title'], '성수동 카페');
    expect(f.sent.single['body'], '동반 가능해요');
    expect(returned?.id, 9, reason: '부른 쪽이 목록을 새로 부를 근거다');
  });

  testWidgets('장소에서 왔으면 loc·contentId 가 실려 나가고 화면에 뜬다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(
      repository: f.repo,
      loc: '서울숲',
      contentId: '126508',
    )));
    await tester.pumpAndSettle();

    expect(find.text('서울숲'), findsOneWidget);
    expect(find.text('장소 연결됨'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '제목');
    await tester.enterText(find.byType(TextField).last, '본문');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(f.sent.single['loc'], '서울숲');
    expect(f.sent.single['contentId'], '126508',
        reason: '장소 단위 UGC 가 차별화 논리다 — 나중에 붙이면 이미 쌓인 글에는 영영 없다');
    expect(f.sent.single['board'], 'pet_place',
        reason: '장소에서 왔으면 동반장소가 자연스러운 첫 값이다');
  });

  testWidgets('장소 이름만 있고 contentId 가 없으면 연결 표시가 없고 키도 안 나간다',
      (tester) async {
    // 지도의 병원·펫샵은 아직 하드코딩 더미다(contentId 가 'v1'·'s1'). 서버가 본 적 없는
    // 값을 실으면 진짜 데이터가 들어왔을 때 아무 장소와도 안 이어지는 글이 남는다.
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(
      repository: f.repo,
      loc: '서울숲동물병원',
    )));
    await tester.pumpAndSettle();

    expect(find.text('서울숲동물병원'), findsOneWidget);
    expect(find.text('장소 연결됨'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '제목');
    await tester.enterText(find.byType(TextField).last, '본문');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(f.sent.single['loc'], '서울숲동물병원');
    expect(f.sent.single.containsKey('contentId'), isFalse);
  });

  testWidgets('서버가 거절하면 폼에 이유가 남고 화면이 안 닫힌다', (tester) async {
    final f = fixture(status: 400);

    await tester.pumpWidget(_host(PostWriteScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '제목');
    await tester.enterText(find.byType(TextField).last, '본문');
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(find.text(CommunityFailureKind.rejected.message), findsOneWidget);
    expect(find.text('올리기'), findsOneWidget,
        reason: '버튼이 돌아와야 다시 시도할 수 있다 — 올리는 중… 에 갇히지 않는다');
  });

  testWidgets('제목 상한이 저장소 상수와 같다 — 여기 숫자를 적지 않는다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostWriteScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(find.byType(TextField).first);
    final body = tester.widget<TextField>(find.byType(TextField).last);

    expect(title.maxLength, CommunityRepository.maxTitleLength);
    expect(body.maxLength, CommunityRepository.maxBodyLength);
  });

  // ─────────────────────────── #173 빈 상태 ───────────────────────────

  testWidgets('글이 0건이면 어느 게시판이 비었는지 말한다 — 로딩 실패로 안 읽힌다',
      (tester) async {
    final client = AuthedClient(
      inner: MockClient((_) async =>
          _json({'items': const [], 'nextCursor': null, 'hasMore': false})),
      baseUrl: _base,
      store: _FakeTokenStore(),
    );
    final repo = CommunityRepository(baseUrl: _base, client: client);

    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('아직 글이 없어요'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing,
        reason: '빈 것과 못 불러온 것은 사용자가 할 일이 다르다 — 쓰거나, 기다리거나');

    // 게시판을 고르면 그 이름이 문구에 든다.
    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자유').last);
    await tester.pumpAndSettle();

    expect(find.text('아직 자유 게시판에 글이 없어요'), findsOneWidget,
        reason: "'자유' 를 골랐는데 그냥 '글이 없어요' 면 앱 전체가 빈 것처럼 읽힌다");
  });
}
