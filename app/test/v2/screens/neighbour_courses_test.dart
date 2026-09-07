// 지도의 "이웃 코스" — 사람들이 올린 길, 가까운 순은 기기가 고른다 (#339).
//
// 서버는 공개 코스 한 벌을 그냥 준다(좌표 파라미터가 없다). 어디가 가까운지 고르는 일이
// **기기에서** 도는지가 여기서 재는 것이다 — 좌표를 서버로 안 보내는 A안(#235)이 그것으로 산다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/course_repository.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/domain/course_path.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

Course _course(int id, String name, {required double lng, required double lat, String? note}) => Course(
      id: id,
      name: name,
      note: note,
      distanceM: 400,
      durationS: 900,
      visibility: 'public',
      mine: false,
      createdAt: DateTime(2026, 9, 7),
      path: [
        [lng, lat],
        [lng + 0.002, lat],
      ],
    );

class _Courses implements CourseRepository {
  _Courses(this.list);
  final List<Course> list;
  int publicCalls = 0;

  @override
  Future<List<Course>> publicCourses() async {
    publicCalls++;
    return list;
  }

  @override
  Future<Course> one(int courseId) async => list.firstWhere((c) => c.id == courseId);

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

Future<void> _pump(WidgetTester tester, _Courses courses) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ExploreScreen(repository: _Places(), courses: courses),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('가까운 순 고르기 — 기기에서', () {
    test('시작점이 가까운 것부터, limit 만큼', () {
      final courses = [
        _course(1, '먼 코스', lng: 127.2000, lat: 37.5445),
        _course(2, '가까운 코스', lng: 127.0405, lat: 37.5445),
        _course(3, '중간 코스', lng: 127.0600, lat: 37.5445),
      ];

      final picked = nearestByStart<Course>(
        courses,
        37.5445,
        127.0400,
        startOf: (c) => c.start,
        limit: 2,
      );

      expect(picked.map((c) => c.name).toList(), ['가까운 코스', '중간 코스']);
    });

    test('시작점이 없는 코스는 빠진다 — 지도에 찍을 데가 없다', () {
      final noPath = Course(
        id: 9,
        name: '선 없는 코스',
        distanceM: 0,
        durationS: 0,
        visibility: 'public',
        mine: false,
        createdAt: DateTime(2026, 9, 7),
      );

      final picked = nearestByStart<Course>(
        [noPath],
        37.5,
        127.0,
        startOf: (c) => c.start,
      );

      expect(picked, isEmpty);
    });
  });

  group('지도 화면', () {
    testWidgets('산책로 칩에서만 "이웃 코스" 토글이 보인다', (tester) async {
      await _pump(tester, _Courses([_course(1, '동네 한 바퀴', lng: 127.04, lat: 37.54)]));

      expect(find.text('이웃 코스'), findsNothing);

      await tester.tap(find.text('산책로').first);
      await tester.pumpAndSettle();

      expect(find.text('이웃 코스'), findsOneWidget);
    });

    testWidgets('토글을 켜면 공개 코스를 한 번 받아 가까운 순으로 그린다', (tester) async {
      final courses = _Courses([
        _course(1, '먼 코스', lng: 127.30, lat: 37.5445),
        _course(2, '가까운 코스', lng: 126.9785, lat: 37.5665, note: '그늘이 많아요'),
      ]);
      await _pump(tester, courses);

      await tester.tap(find.text('산책로').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('이웃 코스'));
      await tester.pumpAndSettle();

      expect(courses.publicCalls, 1, reason: '한 벌만 받는다 — 좌표를 보내며 매번 묻지 않는다');
      expect(find.textContaining('이웃 코스 · 2개'), findsOneWidget);
      expect(find.text('가까운 코스'), findsOneWidget);
      expect(find.text('그늘이 많아요'), findsOneWidget);
    });

    testWidgets('올라온 코스가 없으면 무엇을 하면 쌓이는지 말한다', (tester) async {
      await _pump(tester, _Courses(const []));

      await tester.tap(find.text('산책로').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('이웃 코스'));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 이웃이 올린 코스가 없어요'), findsOneWidget);
    });

    testWidgets('코스를 누르면 상세를 받아 "다시 걷기" 를 준다', (tester) async {
      final courses = _Courses([_course(1, '동네 한 바퀴', lng: 126.9785, lat: 37.5665)]);
      await _pump(tester, courses);

      await tester.tap(find.text('산책로').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('이웃 코스'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동네 한 바퀴'));
      await tester.pumpAndSettle();

      expect(find.text('이 코스 다시 걷기'), findsOneWidget);
      expect(find.textContaining('시작·끝 100m 는 빠져 있어요'), findsOneWidget);
    });
  });
}
