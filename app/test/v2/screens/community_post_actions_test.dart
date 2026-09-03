// 커뮤니티 상세에서 내 글에 할 수 있는 것들 — 이슈 #211.
//
// 지금까지 로그인한 사람이 자기가 쓴 글을 **지울 방법도 고칠 방법도 없었다.** 계약에도
// 코드에도 오퍼레이션이 없었고, #172 가 "글 수정·삭제도 없습니다 — 계약에 그 오퍼레이션이
// 없습니다" 로 계약을 이유 삼아 화면을 빼 놓은 상태였다.
//
// 여기서 재는 것은 넷이다.
//
//  1. **내 것에만 보인다.** `PersonRef.userId` 와 내 id 를 견준다 — ADR-0017 규약 5 가
//     `author` 를 `PersonRef` 로 통일한 이유가 정확히 이것이다.
//  2. **글 삭제는 한 번 묻는다.** 되돌릴 수 없고 남의 댓글까지 함께 사라진다.
//  3. **403 이 그 뜻대로 뜬다.** network 로 뭉치면 "연결을 확인해 주세요" 가 되는데
//     연결은 멀쩡하고 다시 눌러도 영원히 같다.
//  4. **고친 글에 '수정됨' 이 붙는다.** 편집 화면은 아직 없지만 서버에 `PATCH` 가 있어서
//     글은 실제로 바뀔 수 있다 — 읽는 사람에게는 지금 필요한 표시다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';

const _base = 'https://api.example.test';
const _meId = 7;

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

Map<String, Object?> _post(
        {int authorId = _meId, int commentCount = 0, String? updatedAt}) =>
    {
      'id': 12,
      'author': {'userId': authorId, 'nickname': authorId == _meId ? '나' : '남'},
      'board': 'free',
      'loc': null,
      'contentId': null,
      'title': '지울 수 있는 글',
      'body': '본문',
      'commentCount': commentCount,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'updatedAt': updatedAt,
    };

Map<String, Object?> _comment(int id, int authorId) => {
      'id': id,
      'author': {'userId': authorId, 'nickname': authorId == _meId ? '나' : '남'},
      // 본문을 '댓글 N' 으로 두면 섹션 헤더 `댓글 ${commentCount}` 와 글자가 겹쳐서
      // findsNothing 이 헤더를 잡는다. 본문임이 드러나는 말로 둔다.
      'body': '$id 번 줄',
      'createdAt': '2026-09-01T08:00:00Z',
    };

({CommunityRepository repo, List<String> calls}) fixture({
  int postAuthor = _meId,
  List<Map<String, Object?>> comments = const [],
  int deleteStatus = 204,
  String? updatedAt,
}) {
  final calls = <String>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/reports')) {
        calls.add('POST $path');
        return _json({'reportId': 5, 'createdAt': '2026-09-03T01:00:00Z'},
            status: 201);
      }
      if (request.method == 'DELETE') {
        calls.add('DELETE $path');
        if (deleteStatus == 204) return http.Response('', 204);
        return _json({'error': {}}, status: deleteStatus);
      }
      if (path.endsWith('/comments')) {
        return _json({'items': comments, 'nextCursor': null, 'hasMore': false});
      }
      return _json(_post(
          authorId: postAuthor,
          commentCount: comments.length,
          updatedAt: updatedAt));
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CommunityRepository(baseUrl: _base, client: client), calls: calls);
}

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    AuthState.signInForTest(const AuthUser(id: _meId, nickname: '나'));
  });

  tearDown(AuthState.resetForTest);

  testWidgets('내 글에만 삭제가 보인다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('남의 글에는 삭제가 없다', (tester) async {
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('삭제'), findsNothing);
    expect(f.calls, isEmpty);
  });

  testWidgets('탈퇴한 사람의 글에도 삭제가 없다 — 주인 없는 글을 지우는 것은 관리다',
      (tester) async {
    final f = fixture(postAuthor: 0);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 0))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('글 삭제는 한 번 묻고, 댓글이 함께 사라진다고 말한다', (tester) async {
    final f = fixture(comments: [_comment(1, 99), _comment(2, 99)]);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(commentCount: 2))!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.textContaining('댓글 2개도 함께 사라져요'), findsOneWidget,
        reason: '되돌릴 수 없고 남의 댓글까지 사라진다 — 그것을 말하지 않고 지우면 안 된다');
    expect(f.calls, isEmpty, reason: '아직 아무것도 안 보냈다');

    await tester.tap(find.text('그대로 두기'));
    await tester.pumpAndSettle();

    expect(f.calls, isEmpty);
  });

  testWidgets('지우기를 누르면 서버로 가고 목록으로 돌아간다', (tester) async {
    final f = fixture();
    bool? changed;

    await tester.pumpWidget(_host(
      Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(
                    post: CommunityPost.tryParse(_post())!, repository: f.repo),
              ),
            );
          },
          child: const Text('열기'),
        );
      }),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(f.calls, ['DELETE /api/community/posts/12']);
    expect(changed, isTrue, reason: '목록이 이 값으로 새로고침 여부를 정한다');
  });

  testWidgets('남의 글을 지우려다 403 이 오면 그 뜻대로 말한다 — 연결 문제가 아니다',
      (tester) async {
    // 화면은 내 글로 보고 버튼을 그렸지만 서버가 아니라고 한다. AuthState 가 서버와
    // 어긋날 수 있으므로 이 갈래가 실제로 난다.
    final f = fixture(deleteStatus: 403);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(find.text(CommunityFailureKind.forbidden.message), findsOneWidget);
    expect(find.textContaining('연결을 확인해'), findsNothing,
        reason: '403 을 network 로 뭉치면 다시 시도를 권하는데 영원히 같은 결과다');
  });

  testWidgets('내 댓글만 지운다 — 남의 댓글에는 버튼이 없다', (tester) async {
    // 글 주인을 픽스처에도 맞춘다. 상세는 진입할 때 글을 **다시 읽으므로**(#231),
    // 위젯에 넘긴 값만 바꾸면 서버 응답이 그것을 덮는다.
    final f = fixture(
        postAuthor: 99, comments: [_comment(1, _meId), _comment(2, 99)]);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99, commentCount: 2))!,
        repository: f.repo)));
    await tester.pumpAndSettle();

    // 글은 남의 것이라 글 삭제는 없고, 내 댓글 하나만 삭제가 붙는다.
    expect(find.text('삭제'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(f.calls, ['DELETE /api/community/posts/12/comments/1'],
        reason: '경로가 글 아래에 있어야 어느 글의 댓글인지 URL 이 말한다');
    expect(find.text('1 번 줄'), findsNothing, reason: '지운 댓글이 스레드에서 사라진다');
    expect(find.text('2 번 줄'), findsOneWidget);
    expect(find.text('댓글 1'), findsOneWidget,
        reason: '헤더의 개수도 함께 줄어야 한다 — 목록과 숫자가 어긋나면 안 된다');
  });
  testWidgets('고친 글에는 수정됨이 붙는다 — 안 고친 글에는 없다', (tester) async {
    const at = '2026-09-02T02:00:00Z';
    final f = fixture(updatedAt: at);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(updatedAt: at))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('수정됨'), findsOneWidget,
        reason: '이미 달린 댓글이 무엇에 대한 말이었는지 되짚을 유일한 단서다');
  });

  testWidgets('안 고친 글에는 수정됨이 없다 — createdAt 을 복사해 채우면 전부 붙는다',
      (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('수정됨'), findsNothing);
  });

  testWidgets('반응을 눌러도 수정됨이 안 사라진다 — 손으로 베끼는 사본이 필드를 흘렸다',
      (tester) async {
    // _withReactions 가 updatedAt 을 안 베껴서 반응 한 번에 표시가 사라졌다.
    // copyWith 로 모은 뒤의 회귀 잠금이다.
    final edited = _post(updatedAt: '2026-09-02T02:00:00Z');
    final client = AuthedClient(
      inner: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.contains('/reactions/')) {
          return _json({'help': 1, 'cute': 0, 'empathy': 0, 'mine': ['help']});
        }
        if (request.url.path.endsWith('/comments')) {
          return _json({'items': [], 'nextCursor': null, 'hasMore': false});
        }
        return _json(edited);
      }),
      baseUrl: _base,
      store: _FakeTokenStore(),
    );

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(edited)!,
        repository: CommunityRepository(baseUrl: _base, client: client))));
    await tester.pumpAndSettle();

    expect(find.text('수정됨'), findsOneWidget);

    await tester.tap(find.textContaining('도움돼요'));
    await tester.pumpAndSettle();

    expect(find.text('수정됨'), findsOneWidget,
        reason: '반응은 글 내용을 안 바꾼다 — 표시가 사라질 이유가 없다');
  });

  // ─────────────────── 신고 (#166) ───────────────────

  testWidgets('남의 글에 신고가 보인다 — 삭제와 반대 조건이다', (tester) async {
    // 설계 초안이 "삭제 버튼 옆" 이라고만 적었는데, 그 자리는 `_isMine` 분기 **안**이라
    // 그대로 만들면 자기 글에만 신고가 뜨는 앱이 된다. 이 테스트가 그것을 잠근다.
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('신고'), findsOneWidget);
    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('내 글에는 신고가 없다 — 신고 수를 부풀리는 자리다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('신고'), findsNothing);
    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('탈퇴한 사람의 글에는 신고가 없다 — 조치할 대상이 없다', (tester) async {
    final f = fixture(postAuthor: 0);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 0))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('신고'), findsNothing);
  });

  testWidgets('사유를 고르고 신고하면 서버로 간다 — 가리기 칸은 없다', (tester) async {
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();

    expect(find.text('이 사람의 메시지를 가리기'), findsNothing,
        reason: '커뮤니티에 가리기 경로가 아직 없다 — 받는 척하는 칸이 있으면 사용자가 믿는다');

    await tester.tap(find.text('광고 · 도배'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(f.calls, ['POST /api/community/posts/12/reports']);
    expect(find.textContaining('신고를 접수했어요'), findsOneWidget);
  });

  testWidgets('사유를 안 고르면 신고하기가 안 눌린다', (tester) async {
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(f.calls, isEmpty,
        reason: '서버도 400 으로 막지만, 눌러 보고서야 아는 것은 실패를 겪게 하는 것이다');
  });

  testWidgets('남의 댓글에 신고가 붙는다', (tester) async {
    final f = fixture(
        postAuthor: 99, comments: [_comment(1, 99), _comment(2, _meId)]);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99, commentCount: 2))!,
        repository: f.repo)));
    await tester.pumpAndSettle();

    // 글(남) + 댓글 1(남) 둘에 신고, 댓글 2(내 것)에는 삭제.
    expect(find.text('신고'), findsNWidgets(2));
    expect(find.text('삭제'), findsOneWidget);
  });

}
