// 코스 기능이 A안 빌드에서 화면에 없는가 — 이슈 #339 (#235 A안).
//
// ## 왜 이 테스트가 생겼나
//
// 에뮬레이터에서 0.63km 를 걷고 "이 길을 코스로 남기기" 를 눌렀더니
// **"경로가 없는 기록이라 코스로 남길 수 없어요"** 가 떴다. 스크래치 DB 를 열어 보니
// `walk` 다섯 줄이 전부 `path IS NULL` 이었다.
//
// 당연한 결과였다. 코스의 선은 앱이 보내지 않는다 — 서버가 `walk.path` 를 베껴 와 자른다.
// 그런데 이 빌드는 `LocationUploadPolicy.pathForUpload` 가 `null` 을 주므로 **서버에 벨 선이
// 애초에 없다.** `legal-lbs-compliance.md` §1.3 의 A 행이 그것을 미리 적어 뒀다 —
// *"좌표를 전제한 서버 기능(경로 공유·경로 통계) 불가"*.
//
// 기능이 안 되는 것 자체는 결정된 사실이다. 잘못은 **그것을 화면에 남겨 둔 것**이다.
// 6분을 걸어 온 사람에게 "경로가 없는 기록" 은 거짓이다 — 경로는 있었고 이 빌드가 안 보냈다.
//
// ## 여기서 재는 것
//
// 세 자리가 정책을 따라 **함께** 사라지고 **함께** 돌아오는가. 한쪽만 재면 신고를 마치고
// 정의를 켜는 날 하나가 안 돌아와도 아무도 모른다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/course_repository.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';
import 'package:heat_trip_flutter/v2/screens/walk_detail_screen.dart';

class _Walks implements WalkRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Courses implements CourseRepository {
  int calls = 0;

  @override
  Future<List<Course>> mine() async {
    calls++;
    return const [];
  }

  @override
  Future<List<Course>> publicCourses() async {
    calls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Community implements CommunityRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Places extends PetPlacesRepository {
  _Places()
      : super(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://unused',
        );

  @override
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async =>
      const [];
}

Future<void> _pumpWalkDetail(WidgetTester t, _Courses courses) async {
  await t.pumpWidget(MaterialApp(
    home: WalkDetailScreen(
      walkId: 7,
      startedAt: DateTime(2026, 9, 7, 19, 18),
      km: 0.63,
      durationS: 60,
      initialMemo: '',
      repository: _Walks(),
      courses: courses,
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _pumpExplore(WidgetTester t, _Courses courses) async {
  t.view.physicalSize = const Size(1600, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: ExploreScreen(repository: _Places(), courses: courses)));
  await t.pumpAndSettle();
  await t.tap(find.text('산책로').first);
  await t.pumpAndSettle();
}

Future<void> _pumpPostWrite(WidgetTester t, _Courses courses) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: PostWriteScreen(
      repository: _Community(),
      courses: courses,
      initialBoard: CommunityBoard.walkReview,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 3, nickname: '보리아빠'));
  });
  tearDown(() {
    AuthState.resetForTest();
    LocationUploadPolicy.resetForTest();
  });

  group('좌표를 안 보내는 빌드 — 세 자리가 없다', () {
    setUp(() => LocationUploadPolicy.setForTest(false));

    test('정책이 코스 기능을 함께 끈다', () {
      expect(LocationUploadPolicy.sharesRoutes, isFalse,
          reason: '선이 안 올라가면 서버에 벨 선이 없다 — 코스는 만들 수도 볼 수도 없다');
    });

    testWidgets('산책 회고에 "이 길을 코스로 남기기" 가 없다', (t) async {
      await _pumpWalkDetail(t, _Courses());

      expect(find.text('이 길을 코스로 남기기'), findsNothing,
          reason: '눌러 봐야 "경로가 없는 기록" 이 뜬다 — 그 말은 걸어 온 사람에게 거짓이다');
      expect(find.text('오늘의 산책'), findsOneWidget, reason: '회고 자체는 그대로 산다');
    });

    testWidgets('지도의 산책로 칩에 "이웃 코스" 토글이 없다', (t) async {
      final courses = _Courses();
      await _pumpExplore(t, courses);

      expect(find.text('이웃 코스'), findsNothing);
      expect(courses.calls, 0, reason: '없는 기능이 서버를 부르지도 않는다');
    });

    testWidgets('글쓰기에 "내 코스 붙이기" 줄이 없다', (t) async {
      await _pumpPostWrite(t, _Courses());

      expect(find.textContaining('내 코스 붙이기'), findsNothing);
      expect(find.text('제목'), findsOneWidget, reason: '글쓰기 자체는 그대로 산다');
    });
  });

  group('신고를 마치고 켠 빌드 — 세 자리가 함께 돌아온다', () {
    setUp(() => LocationUploadPolicy.setForTest(true));

    test('정책이 함께 켜진다', () {
      expect(LocationUploadPolicy.sharesRoutes, isTrue);
    });

    testWidgets('산책 회고에 코스 자리가 있다', (t) async {
      await _pumpWalkDetail(t, _Courses());

      expect(find.text('이 길을 코스로 남기기'), findsOneWidget);
    });

    testWidgets('지도에 "이웃 코스" 토글이 있다', (t) async {
      await _pumpExplore(t, _Courses());

      expect(find.text('이웃 코스'), findsOneWidget);
    });

    testWidgets('글쓰기에 코스 줄이 있다', (t) async {
      await _pumpPostWrite(t, _Courses());

      expect(find.textContaining('내 코스 붙이기'), findsOneWidget);
    });
  });
}
