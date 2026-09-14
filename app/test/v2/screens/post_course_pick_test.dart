// 글쓰기에서 코스 고르기 — 산책로 후기에만, 비공개는 공개하고 붙인다 (#339).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/course_repository.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

Course _course(int id, String name, {bool isPublic = true}) => Course(
      id: id,
      name: name,
      distanceM: 400,
      durationS: 900,
      visibility: isPublic ? 'public' : 'private',
      mine: true,
      createdAt: DateTime(2026, 9, 7),
      path: const [
        [127.041, 37.5445],
        [127.045, 37.5449],
      ],
    );

class _Courses implements CourseRepository {
  _Courses(this.list);
  final List<Course> list;
  final List<int> published = [];

  @override
  Future<List<Course>> mine() async => list;

  @override
  Future<Course> setVisibility(int courseId, {required bool isPublic}) async {
    published.add(courseId);
    final found = list.firstWhere((c) => c.id == courseId);
    return _course(found.id, found.name, isPublic: isPublic);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Community implements CommunityRepository {
  final List<int?> createdWith = [];

  @override
  Future<CommunityPost> createPost({
    required CommunityBoard board,
    required String title,
    required String body,
    String? loc,
    String? contentId,
    int? courseId,
    List<int>? mediaIds,
    int? dogId,
  }) async {
    createdWith.add(courseId);
    return CommunityPost(
      id: 1,
      author: const PersonRef(userId: 3, nickname: '보리아빠'),
      board: board,
      title: title,
      body: body,
      commentCount: 0,
      reactions: ReactionSummary.empty,
      createdAt: DateTime(2026, 9, 7),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<void> _pump(WidgetTester t, _Community community, _Courses courses) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    // 기본 게시판은 자유다 — 코스 줄은 산책로 후기에서만 나오므로 그 칩을 먼저 누른다.
    home: PostWriteScreen(
      repository: community,
      courses: courses,
      initialBoard: CommunityBoard.walkReview,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  // 코스 줄은 **켜진 빌드**에만 있다(`route_sharing_gate_test.dart`).
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 3, nickname: '보리아빠'));
    LocationUploadPolicy.setForTest(true);
  });
  tearDown(() {
    AuthState.resetForTest();
    LocationUploadPolicy.resetForTest();
  });

  testWidgets('산책로 후기에서만 코스 줄이 보인다', (t) async {
    await _pump(t, _Community(), _Courses([_course(5, '서울숲 한 바퀴')]));

    expect(find.textContaining('내 코스 붙이기'), findsOneWidget);

    await t.tap(find.text('자유'));
    await t.pumpAndSettle();

    expect(find.textContaining('내 코스 붙이기'), findsNothing,
        reason: '다른 게시판에 경로를 붙이는 것은 뜻이 흐리다');
  });

  testWidgets('공개 코스를 고르면 그 이름이 줄에 남는다', (t) async {
    await _pump(t, _Community(), _Courses([_course(5, '서울숲 한 바퀴')]));

    await t.tap(find.textContaining('내 코스 붙이기'));
    await t.pumpAndSettle();
    await t.tap(find.text('서울숲 한 바퀴'));
    await t.pumpAndSettle();

    expect(find.text('서울숲 한 바퀴'), findsOneWidget);
    expect(find.text('빼기'), findsOneWidget);
  });

  testWidgets('비공개 코스는 "공개하고 붙이기" 로 바꾼 뒤에 붙는다', (t) async {
    final courses = _Courses([_course(7, '나만의 길', isPublic: false)]);
    await _pump(t, _Community(), courses);

    await t.tap(find.textContaining('내 코스 붙이기'));
    await t.pumpAndSettle();
    expect(find.text('공개하고 붙이기'), findsOneWidget);

    await t.tap(find.text('나만의 길'));
    await t.pumpAndSettle();

    expect(courses.published, [7], reason: '서버가 몰래 공개로 바꾸지 않는다 — 앱이 물어보고 바꾼다');
    expect(find.text('나만의 길'), findsOneWidget);
  });

  testWidgets('고른 코스가 글과 함께 나간다 · 빼면 안 나간다', (t) async {
    final community = _Community();
    await _pump(t, community, _Courses([_course(5, '서울숲 한 바퀴')]));

    await t.tap(find.textContaining('내 코스 붙이기'));
    await t.pumpAndSettle();
    await t.tap(find.text('서울숲 한 바퀴'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).at(0), '이 길 좋아요');
    await t.enterText(find.byType(TextField).at(1), '그늘이 많아요');
    await t.tap(find.text('올리기'));
    await t.pumpAndSettle();

    expect(community.createdWith, [5]);
  });
}
