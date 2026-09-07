// 코스로 남기기 시트 — 잘려 나갈 부분을 먼저 보여 준다 (#339).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/course_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/course_save_sheet.dart';

/// 동쪽으로 [stepM]m 씩 [count] 개.
List<List<double>> _line(int count, double stepM) {
  final stepLng = stepM / 88000.0;
  return [for (var i = 0; i < count; i++) [127.0400 + stepLng * i, 37.5445]];
}

class _Walks implements WalkRepository {
  _Walks(this.path);
  final List<List<double>>? path;

  @override
  Future<ServerWalk> walk(int walkId) async => ServerWalk(
        id: walkId,
        dogId: 1,
        clientWalkId: 'abc12345',
        startedAt: DateTime(2026, 9, 7, 13),
        distanceM: 600,
        durationS: 900,
        path: path,
      );

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Courses implements CourseRepository {
  final List<Map<String, Object?>> created = [];

  @override
  Future<Course> create({
    required int walkId,
    required String name,
    String? note,
    List<String> tags = const [],
    bool isPublic = false,
  }) async {
    created.add({'walkId': walkId, 'name': name, 'note': note, 'tags': tags, 'public': isPublic});
    return Course(
      id: 5,
      walkId: walkId,
      name: name,
      note: note,
      tags: tags,
      path: _line(41, 10),
      distanceM: 400,
      durationS: 900,
      visibility: isPublic ? 'public' : 'private',
      mine: true,
      createdAt: DateTime(2026, 9, 7, 13),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<Course?> _open(
  WidgetTester tester, {
  required List<List<double>>? path,
  required _Courses courses,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Course? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await CourseSaveSheet.open(
              context,
              walkId: 12,
              km: 0.6,
              minutes: 15,
              walks: _Walks(path),
              courses: courses,
            );
          },
          child: const Text('열기'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('잘려 나갈 부분을 먼저 말한다 — 0.60km 중 0.40km', (tester) async {
    await _open(tester, path: _line(61, 10), courses: _Courses());

    expect(find.text('코스로 남기기'), findsOneWidget);
    expect(find.textContaining('시작·끝 100m 는 저장하지 않아요'), findsOneWidget);
    expect(find.textContaining('0.60km 중'), findsOneWidget);
  });

  testWidgets('300m 가 안 되면 이름 칸을 열지 않고 이유를 말한다', (tester) async {
    await _open(tester, path: _line(21, 10), courses: _Courses());

    expect(find.textContaining('300m'), findsOneWidget);
    expect(find.text('코스로 저장'), findsNothing);
  });

  testWidgets('경로가 없는 기록이면 그 말을 한다 — 손입력 기록이다', (tester) async {
    await _open(tester, path: null, courses: _Courses());

    expect(find.textContaining('경로가 없는 기록'), findsOneWidget);
    expect(find.text('코스로 저장'), findsNothing);
  });

  testWidgets('이름 없이 저장하면 이름을 달라고 한다', (tester) async {
    final courses = _Courses();
    await _open(tester, path: _line(61, 10), courses: courses);

    await tester.tap(find.text('코스로 저장'));
    await tester.pumpAndSettle();

    expect(find.text('코스 이름을 적어 주세요'), findsOneWidget);
    expect(courses.created, isEmpty);
  });

  testWidgets('이름·태그·공개를 담아 저장한다 — 기본은 비공개', (tester) async {
    final courses = _Courses();
    await _open(tester, path: _line(61, 10), courses: courses);

    await tester.enterText(find.byType(TextField).first, '서울숲 한 바퀴');
    await tester.tap(find.text('그늘·물 있음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('코스로 저장'));
    await tester.pumpAndSettle();

    expect(courses.created, hasLength(1));
    expect(courses.created.single['name'], '서울숲 한 바퀴');
    expect(courses.created.single['tags'], ['shade']);
    expect(courses.created.single['public'], isFalse);
  });

  testWidgets('이웃에게 보이기를 켜면 공개로 저장한다', (tester) async {
    final courses = _Courses();
    await _open(tester, path: _line(61, 10), courses: courses);

    await tester.enterText(find.byType(TextField).first, '동네 한 바퀴');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('코스로 저장'));
    await tester.pumpAndSettle();

    expect(courses.created.single['public'], isTrue);
  });
}
