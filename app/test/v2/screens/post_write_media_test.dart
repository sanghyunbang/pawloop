// 글쓰기 화면의 사진 첨부 — 올리고, 글에는 id 만 싣고, 올리는 중이면 저장을 잠근다 (#429).
//
// `post_write_test.dart` 와 같은 방식이다 — 진짜 `CommunityRepository`·`PostMediaRepository`
// 에 `MockClient` 하나를 꽂는다. 업로드 응답의 id 가 글 본문의 `mediaIds` 로 나가는지까지
// 한 배선으로 지난다. 사진 칸 자체의 규칙(재인코딩·순서·재시도)은 `post_media_field_test`.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/media_picker.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

import '../support/fake_media_picker.dart';
import '../support/gps_jpeg.dart';

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

Map<String, Object?> _mediaJson(int id) => {
      'id': id,
      'kind': 'image',
      'url': 'https://cdn.example.test/posts/7/$id.jpg',
      'posterUrl': null,
      'width': 1600,
      'height': 1200,
      'durationMs': null,
    };

Map<String, Object?> _post({List<int> mediaIds = const []}) => {
      'id': 9,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'pet_place',
      'loc': null,
      'contentId': null,
      'title': '제목',
      'body': '본문',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-03T10:00:00Z',
      'media': [for (final id in mediaIds) _mediaJson(id)],
    };

/// 업로드와 글 저장을 한 곳에서 받는 가짜 서버.
class _Server {
  final uploads = <http.Request>[];
  final posts = <Map<String, Object?>>[];
  final patches = <Map<String, Object?>>[];
  final deleted = <String>[];

  /// 업로드 응답 전에 기다릴 문. 올리는 중인 상태를 잡는 데 쓴다.
  Completer<void>? gate;
  int failFirst = 0;
  int _nextId = 501;

  Future<http.Response> call(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path == '/media') {
      uploads.add(request);
      if (gate != null) await gate!.future;
      if (failFirst > 0) {
        failFirst--;
        return _json({'error': {'code': 'INTERNAL', 'message': '서버 오류'}}, status: 500);
      }
      final id = _nextId++;
      return _json([
        {'id': id, 'url': 'https://cdn.example.test/posts/7/$id.jpg', 'width': 24, 'height': 40}
      ]);
    }
    if (request.method == 'DELETE' && path.startsWith('/media/')) {
      deleted.add(request.url.pathSegments.last);
      return http.Response('', 204);
    }
    if (request.method == 'POST' && path == '/api/community/posts') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      posts.add(body);
      return _json(_post(mediaIds: _ids(body['mediaIds'])), status: 201);
    }
    if (request.method == 'PATCH' && path == '/api/community/posts/9') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      patches.add(body);
      return _json(_post(mediaIds: _ids(body['mediaIds'])));
    }
    return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
  }

  static List<int> _ids(Object? raw) => raw is List ? [for (final v in raw) (v as num).toInt()] : const [];
}

typedef _Fixture = ({CommunityRepository repo, PostMediaRepository media, _Server server});

_Fixture _fixture() {
  final server = _Server();
  final client = AuthedClient(inner: MockClient(server.call), baseUrl: _base, store: _FakeTokenStore());
  return (
    repo: CommunityRepository(baseUrl: _base, client: client),
    media: PostMediaRepository(baseUrl: _base, client: client),
    server: server,
  );
}

FakeMediaPicker _onePhoto() => FakeMediaPicker((_) => [PickedImage(name: 'IMG_1.HEIC', bytes: gpsJpeg())]);

Widget _screen(_Fixture f, {CommunityPost? editing, FakeMediaPicker? picker}) => PostWriteScreen(
      repository: f.repo,
      media: f.media,
      picker: picker ?? _onePhoto(),
      // 격리 스레드는 FakeAsync 안에서 결과를 못 돌려준다 — 같은 일을 하는 동기 버전.
      prepare: (bytes) async => ImagePrep.prepareSync(bytes),
      editing: editing,
    );

/// 화면을 밀어 열고 돌려받는 값을 잡는다 — 저장하면 `Navigator.pop(post)` 로 닫히기 때문이다.
Future<CommunityPost? Function()> _open(WidgetTester tester, Widget screen) async {
  CommunityPost? returned;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          returned = await Navigator.of(context).push<CommunityPost>(
            MaterialPageRoute(builder: (_) => screen),
          );
        },
        child: const Text('열기'),
      );
    }),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return () => returned;
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '제목');
  await tester.enterText(find.byType(TextField).last, '본문');
}

/// 스크롤해 보이게 한 뒤 누른다. `pumpAndSettle` 은 쓰지 않는다 — 가짜 시계가 30초를 넘겨
/// 업로드 타임아웃을 울리면 "올리는 중" 이 "못 올림" 으로 바뀌어 잠금 테스트가 헛돈다.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  setUp(() {
    LocationUploadPolicy.setForTest(true);
    // 폼이 기본 표면(800×600)보다 길다 — `post_write_test.dart` 와 같은 전제.
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.single;
    view.physicalSize = const Size(800, 1400);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    LocationUploadPolicy.resetForTest();
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.single.reset();
  });

  testWidgets('사진을 고르면 올라가고, 글에는 파일이 아니라 mediaIds 만 실린다', (tester) async {
    final f = _fixture();
    final returned = await _open(tester, _screen(f));

    await _fill(tester);
    await _tapVisible(tester, find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();
    expect(f.server.uploads.length, 1, reason: '고르는 순간 올린다 — 저장 버튼을 기다리지 않는다');

    await _tapVisible(tester, find.text('올리기'));
    await tester.pumpAndSettle();

    final body = f.server.posts.single;
    expect(body['mediaIds'], [501]);
    expect(body.keys, isNot(contains('files')), reason: '글 요청에 바이트가 실리지 않는다');
    expect(returned()?.media.single.id, 501, reason: '돌려받은 글에 사진이 붙어 있다 — 목록이 바로 그린다');
  });

  testWidgets('사진이 없으면 mediaIds 키가 나가지 않는다 — 빈 배열은 "전부 뗀다" 라서', (tester) async {
    final f = _fixture();
    await _open(tester, _screen(f));

    await _fill(tester);
    await _tapVisible(tester, find.text('올리기'));
    await tester.pumpAndSettle();

    expect(f.server.posts.single.keys, isNot(contains('mediaIds')));
  });

  testWidgets('올리는 중에는 저장이 잠긴다 — 사진 없는 글이 조용히 올라가지 않는다', (tester) async {
    final f = _fixture();
    f.server.gate = Completer<void>();
    await _open(tester, _screen(f));

    await _fill(tester);
    await _tapVisible(tester, find.byKey(const Key('post-media-add')));
    await tester.pump();
    await tester.pump();

    await _tapVisible(tester, find.text('올리기'));
    await tester.pump();
    expect(find.text('사진·영상을 올리는 중이에요 · 잠시만요'), findsOneWidget);
    expect(f.server.posts, isEmpty);

    f.server.gate!.complete();
    f.server.gate = null;
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('올리기'));
    await tester.pumpAndSettle();
    expect(f.server.posts.single['mediaIds'], [501]);
  });

  testWidgets('못 올린 사진이 있으면 저장이 막히고, 떼면 사진 없이 나간다', (tester) async {
    final f = _fixture();
    f.server.failFirst = 1;
    await _open(tester, _screen(f));

    await _fill(tester);
    await _tapVisible(tester, find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('올리기'));
    await tester.pump();
    expect(find.text('못 올린 사진·영상이 있어요 · 다시 올리거나 떼 주세요'), findsOneWidget);
    expect(f.server.posts, isEmpty);

    await _tapVisible(tester, find.byKey(const Key('post-media-remove-0')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('올리기'));
    await tester.pumpAndSettle();

    expect(f.server.posts.single.keys, isNot(contains('mediaIds')));
    expect(f.server.deleted, isEmpty, reason: '올라간 적이 없으니 지울 것도 없다');
  });

  testWidgets('고치기 — 사진을 떼면 남은 목록을 통째로 보내고, 글자는 안 바뀌었으니 안 보낸다', (tester) async {
    final f = _fixture();
    final editing = CommunityPost.tryParse(_post(mediaIds: [1, 2]))!;
    await _open(tester, _screen(f, editing: editing));

    expect(find.text('2 / 10장 · 위치 정보는 지우고 올려요'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('post-media-remove-0')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.server.patches.single, {'mediaIds': [2]},
        reason: 'PostPatch.mediaIds 는 갈아 끼우기다 — 남은 것 전부를 싣고 다른 키는 안 싣는다');
    expect(f.server.deleted, isEmpty, reason: '글에 붙은 사진은 서버가 글 고치기에서 떼어 낸다');
  });

  testWidgets('고치기 — 사진을 안 건드리면 mediaIds 키가 없다', (tester) async {
    final f = _fixture();
    final editing = CommunityPost.tryParse(_post(mediaIds: [1, 2]))!;
    await _open(tester, _screen(f, editing: editing));

    await tester.enterText(find.byType(TextField).first, '제목을 고침');
    await _tapVisible(tester, find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.server.patches.single, {'title': '제목을 고침'});
  });

  testWidgets('고치기 — 사진을 더하면 기존 id 뒤에 새 id 가 붙는다', (tester) async {
    final f = _fixture();
    final editing = CommunityPost.tryParse(_post(mediaIds: [1]))!;
    await _open(tester, _screen(f, editing: editing));

    await _tapVisible(tester, find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.server.patches.single, {'mediaIds': [1, 501]});
  });

  testWidgets('고치기 — 사진을 다 떼면 빈 배열이 나간다 (전부 뗀다)', (tester) async {
    final f = _fixture();
    final editing = CommunityPost.tryParse(_post(mediaIds: [1]))!;
    await _open(tester, _screen(f, editing: editing));

    await _tapVisible(tester, find.byKey(const Key('post-media-remove-0')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('고치기'));
    await tester.pumpAndSettle();

    expect(f.server.patches.single, {'mediaIds': <int>[]});
  });
}
