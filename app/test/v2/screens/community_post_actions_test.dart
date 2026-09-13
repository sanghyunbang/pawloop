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
        {int authorId = _meId,
        int commentCount = 0,
        String? updatedAt,
        bool hidden = false,
        // 화면은 reactions.mine 이 null 인 것으로 게스트를 판정한다
        // (post_detail_screen.dart 의 _isGuest).
        bool guest = false,
        String? loc}) =>
    {
      'id': 12,
      'author': {'userId': authorId, 'nickname': authorId == _meId ? '나' : '남'},
      'board': 'free',
      'loc': loc,
      'contentId': null,
      'title': '지울 수 있는 글',
      'body': '본문',
      'commentCount': commentCount,
      'reactions': {
        'help': 0,
        'cute': 0,
        'empathy': 0,
        'mine': guest ? null : <String>[],
      },
      'createdAt': '2026-09-01T07:30:00Z',
      'updatedAt': updatedAt,
      'hiddenByBlock': hidden,
    };

Map<String, Object?> _comment(int id, int authorId) => {
      'id': id,
      'author': {'userId': authorId, 'nickname': authorId == _meId ? '나' : '남'},
      // 본문을 '댓글 N' 으로 두면 섹션 헤더 `댓글 ${commentCount}` 와 글자가 겹쳐서
      // findsNothing 이 헤더를 잡는다. 본문임이 드러나는 말로 둔다.
      'body': '$id 번 줄',
      'createdAt': '2026-09-01T08:00:00Z',
    };

({CommunityRepository repo, List<String> calls, List<Map<String, Object?>> bodies})
    fixture({
  int postAuthor = _meId,
  List<Map<String, Object?>> comments = const [],
  int deleteStatus = 204,
  String? updatedAt,
  bool hiddenByBlock = false,
  bool guest = false,
  String? loc,
  int patchStatus = 200,
}) {
  final calls = <String>[];
  final bodies = <Map<String, Object?>>[];
  // 고쳐진 글을 그대로 돌려준다 — 서버는 값이 실제로 달라졌을 때만 updatedAt 을 만든다.
  Map<String, Object?> current = _post(
      authorId: postAuthor,
      commentCount: comments.length,
      updatedAt: updatedAt,
      hidden: hiddenByBlock,
      guest: guest,
      loc: loc);
  final client = AuthedClient(
    inner: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'PATCH') {
        calls.add('PATCH $path');
        bodies.add(
            (jsonDecode(request.body) as Map).cast<String, Object?>());
        if (patchStatus != 200) return _json({'error': {}}, status: patchStatus);
        current = Map<String, Object?>.from(current)
          ..addAll(bodies.last)
          ..['updatedAt'] = '2026-09-03T02:00:00Z';
        return _json(current);
      }
      if (request.method == 'POST' && path.endsWith('/reports')) {
        calls.add('POST $path');
        return _json({'reportId': 5, 'createdAt': '2026-09-03T01:00:00Z'},
            status: 201);
      }
      if (request.method == 'POST' && path == '/api/blocks') {
        calls.add('POST $path');
        return _json(const <String, Object?>{}, status: 201);
      }
      if (request.method == 'DELETE') {
        calls.add('DELETE $path');
        if (deleteStatus == 204) return http.Response('', 204);
        return _json({'error': {}}, status: deleteStatus);
      }
      if (path.endsWith('/comments')) {
        return _json({'items': comments, 'nextCursor': null, 'hasMore': false});
      }
      return _json(current);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    repo: CommunityRepository(baseUrl: _base, client: client),
    calls: calls,
    bodies: bodies
  );
}

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    AuthState.signInForTest(const AuthUser(id: _meId, nickname: '나'));
    // 편집 화면에 사진 칸(#429)이 더해져 폼이 기본 표면(800×600)보다 길다. ListView 는 보이는
    // 것만 만들어 '고치기' 가 finder 에 안 잡힌다 — `post_write_test.dart` 와 같은 전제.
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.single;
    view.physicalSize = const Size(800, 1400);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    AuthState.resetForTest();
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.single.reset();
  });

  // ─────────────────── 공개 범위 고지 (이슈 #253) ───────────────────

  testWidgets('댓글 입력칸도 공개 범위를 말한다 — 커뮤니티 UGC 의 대부분이 댓글이다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(
      find.text('로그인하지 않은 사람에게도 보여요'),
      findsOneWidget,
      reason: 'SecurityConfig 가 /api/community/posts/*/comments 의 GET 을 permitAll 로 엽니다. '
          '글쓰기 화면에만 적으면 댓글만 쓰는 사람은 그 사실을 한 번도 못 봅니다.',
    );
  });

  testWidgets('게스트에게는 입력칸 대신 로그인 안내만 보인다 — 고지가 안내를 밀어내지 않는다',
      (tester) async {
    // 게스트는 애초에 댓글을 못 씁니다. 그 자리에 공개 범위 고지를 겹쳐 놓으면
    // "로그인하면 쓸 수 있어요" 가 묻힙니다.
    final f = fixture(guest: true);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('로그인하면 댓글과 반응을 남길 수 있어요'), findsOneWidget);
    expect(find.text('로그인하지 않은 사람에게도 보여요'), findsNothing);
  });

  testWidgets('글 상세에도 동의 창을 띄우지 않는다 — 결정을 잠근다 (#253)', (tester) async {
    // post_write_test 의 같은 이름 단언과 짝이다. 커뮤니티는 동의를 다시 받지 않고,
    // 비어 있던 "무엇에 동의했나" 는 약관 제7조4·제7조의2·제9조2 로 갚았다.
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });


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

  testWidgets('사유를 고르고 신고하면 서버로 간다 — 가리기를 안 켜면 신고만 간다', (tester) async {
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();

    expect(find.text('이 사람의 메시지를 가리기'), findsOneWidget,
        reason: '가리기는 사람 단위라 커뮤니티에서도 같은 경로를 쓴다');

    await tester.tap(find.text('광고 · 도배'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(f.calls, ['POST /api/community/posts/12/reports'],
        reason: '가리기를 안 켰으면 /api/blocks 는 안 부른다');
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


  // ─────────────────── 가리기 (#166) ───────────────────

  testWidgets('가린 사람의 글은 접힌다 — 목록에서 빠지지는 않는다', (tester) async {
    final f = fixture(postAuthor: 99, hiddenByBlock: true);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99, hidden: true))!,
        repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('본문'), findsNothing);
    expect(find.textContaining('가린 사람의 글입니다'), findsOneWidget);
    expect(find.text('지울 수 있는 글'), findsOneWidget,
        reason: '제목과 카드는 남는다 — 빼면 커서가 그 글을 건너뛰어 페이지 경계가 어긋난다');
  });

  testWidgets('접힌 본문을 누르면 펴진다', (tester) async {
    final f = fixture(postAuthor: 99, hiddenByBlock: true);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99, hidden: true))!,
        repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('가린 사람의 글입니다'));
    await tester.pumpAndSettle();

    expect(find.text('본문'), findsOneWidget,
        reason: '본문은 이미 와 있다 — 누를 때 요청이 한 번 더 필요하면 그 경로에 인가가 또 하나 생긴다');
  });

  testWidgets('안 가린 글은 그대로 보인다', (tester) async {
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('본문'), findsOneWidget);
    expect(find.textContaining('가린 사람의 글입니다'), findsNothing);
  });

  testWidgets('신고하며 가리기를 켜면 신고 뒤에 가린다 — 순서가 반대면 접수 안 된 채 가려진다',
      (tester) async {
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('광고 · 도배'));
    await tester.tap(find.text('이 사람의 메시지를 가리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(f.calls, [
      'POST /api/community/posts/12/reports',
      'POST /api/blocks',
    ], reason: '신고가 먼저다 — 실패하면 가리지 않는다');
    expect(find.textContaining('가렸어요'), findsOneWidget);
  });


  // ─────────────────── 수정 (#243) ───────────────────

  testWidgets('내 글에는 수정이 보인다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('수정'), findsOneWidget);
  });

  testWidgets('남의 글에는 수정이 없다 — 그 자리에 신고가 뜬다', (tester) async {
    // 한 테스트에서 pumpWidget 을 두 번 하지 않는다. 같은 위치의 같은 타입이면
    // Flutter 가 State 를 재사용해서 앞 글이 그대로 남는다 — 실제로 그렇게 헛초록이 났다.
    final f = fixture(postAuthor: 99);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99))!, repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('수정'), findsNothing);
    expect(find.text('신고'), findsOneWidget);
  });

  testWidgets('댓글에는 수정이 없다 — 계약에 댓글 수정 경로가 없다', (tester) async {
    final f = fixture(postAuthor: 99, comments: [_comment(1, _meId)]);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(authorId: 99, commentCount: 1))!,
        repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('수정'), findsNothing,
        reason: '내 댓글이 있어도 수정은 안 뜬다 — 삭제만 있다');
    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('제목만 고치면 요청 본문에 body 키가 없다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '고친 제목');
    await tester.tap(find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.calls, ['PATCH /api/community/posts/12']);
    expect(f.bodies.single, {'title': '고친 제목'},
        reason: '다 실으면 그 사이 다른 기기에서 고친 본문을 조용히 되돌린다 '
            '(ADR-0017 규약 4)');
  });

  testWidgets('아무것도 안 고치고 저장하면 요청을 안 보낸다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.calls, isEmpty,
        reason: '서버가 400 을 주는데 그건 사용자가 볼 이유가 없는 실패다 — '
            '아무것도 안 고친 것은 잘못이 아니다');
  });

  testWidgets('장소는 편집에서 못 바꾼다 — 계약이 PostPatch 에서 뺐다', (tester) async {
    final f = fixture(loc: '서울숲');

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post(loc: '서울숲'))!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.text('서울숲'), findsOneWidget,
        reason: '어느 장소의 글인지는 맥락이라 보여 준다');
    await tester.enterText(find.byType(TextField).first, '고친 제목');
    await tester.tap(find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.bodies.single.containsKey('loc'), isFalse);
    expect(f.bodies.single.containsKey('contentId'), isFalse);
  });

  testWidgets('403 이면 수정 문구로 뜬다 — 삭제 문구가 아니다', (tester) async {
    final f = fixture(patchStatus: 403);

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '고친 제목');
    await tester.tap(find.text('고치기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('고치거나'), findsOneWidget,
        reason: "'지울 수 있어요' 는 수정을 시도한 사람에게 거짓이다");
  });

  testWidgets('고치고 나오면 새 값과 수정됨이 뜬다', (tester) async {
    final f = fixture();

    await tester.pumpWidget(_host(PostDetailScreen(
        post: CommunityPost.tryParse(_post())!, repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '고친 제목');
    await tester.tap(find.text('고치기'));
    await tester.pumpAndSettle();

    expect(find.text('고친 제목'), findsOneWidget);
    expect(find.text('수정됨'), findsOneWidget,
        reason: '서버가 값이 실제로 달라진 경우에만 updatedAt 을 만든다');
  });

}
