// 홈의 "오늘의 코스" 카드 (#485) — 후보 · 안전 지수 · 목표를 받아 한 장을 그린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/course_candidates.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/course_recommender.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/today_course_card.dart';

class _Source implements CourseCandidateSource {
  _Source(this.candidates);
  final List<CourseCandidate> candidates;
  int calls = 0;
  @override
  Future<List<CourseCandidate>> around({required double lat, required double lng}) async {
    calls++;
    return candidates;
  }
}

const _trail = CourseCandidate(
    id: 'trail:1', title: '서울숲 둘레길', kind: CourseKind.trail, distanceM: 500, lengthM: 3000, source: 'trail', contentId: 'trail:1');
const _park = CourseCandidate(
    id: '2733847', title: '서울숲 호수', kind: CourseKind.park, distanceM: 800, lengthM: 1200, source: 'kto', contentId: '2733847');
const _mine = CourseCandidate(id: 'course:7', title: '아침 한 바퀴', kind: CourseKind.myCourse, distanceM: 1500, lengthM: 2000);

const _dog = DogProfile(
  serverId: 9,
  name: '보리',
  breed: '푸들',
  species: PetSpecies.dog,
  size: DogSize.small,
  ageMonths: 24,
);

WalkFeedData _feed({List<ServerWalk> walks = const [], List<WalkDraft> pending = const [], bool guest = false}) => WalkFeedData(
      walks: walks,
      pending: pending,
      rejected: const [],
      stats: WalkFeedData.empty.stats,
      offline: false,
      nextCursor: null,
      hasMore: false,
      guest: guest,
    );

ServerWalk _walk({required DateTime at, String? contentId, int distanceM = 1200, int durationS = 1200}) => ServerWalk(
      id: 1,
      dogId: 9,
      dogIds: const [9],
      clientWalkId: 'x',
      startedAt: at,
      endedAt: at.add(Duration(seconds: durationS)),
      distanceM: distanceM,
      durationS: durationS,
      place: contentId == null ? null : WalkPlaceRef(title: '장소', source: 'kto', contentId: contentId),
    );

final _now = DateTime(2026, 9, 14, 8);

Future<void> _pump(WidgetTester tester, TodayCourseCard card) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))));
  await tester.pumpAndSettle();
}

TodayCourseCard _card({
  required CourseCandidateSource source,
  WalkFeedData? data,
  DogProfile? dog,
  bool located = true,
  StartCourseWalk? onStart,
}) =>
    TodayCourseCard(
      dog: dog ?? _dog,
      data: data ?? _feed(),
      source: source,
      locate: () async => located ? (lat: 37.5445, lng: 127.0374) : null,
      now: () => _now,
      onStart: onStart ?? (_, __) async {},
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyStore.resetForTest();
  });

  testWidgets('후보가 있으면 1등 하나를 카드로 — 이름 · 거리 · 코스 길이 · 이유', (tester) async {
    await _pump(tester, _card(source: _Source(const [_trail, _park, _mine])));

    expect(find.byKey(const Key('today-course')), findsOneWidget);
    expect(find.text('아침 한 바퀴'), findsOneWidget, reason: '소형견 하루 30분 → 2km 목표, 내 코스 2.0km 가 1등');
    expect(find.textContaining('1.5km 거리'), findsOneWidget);
    expect(find.textContaining('코스 2.0km'), findsOneWidget);
    expect(find.textContaining('목표 2.0km'), findsOneWidget);
    expect(find.textContaining('내가 만든 코스'), findsOneWidget);
    expect(find.text('여기서 산책 시작'), findsOneWidget);
  });

  testWidgets('"다른 코스" 는 다음 점수의 후보 — 한 바퀴 돌면 처음으로', (tester) async {
    await _pump(tester, _card(source: _Source(const [_trail, _park])));

    expect(find.text('서울숲 호수'), findsOneWidget, reason: '2km 목표에 1.2km 공원(0.8 차이)이 3km 산책로(1.0 차이)보다 가깝다');
    await tester.tap(find.byKey(const Key('today-course-next')));
    await tester.pumpAndSettle();
    expect(find.text('서울숲 둘레길'), findsOneWidget);
    await tester.tap(find.byKey(const Key('today-course-next')));
    await tester.pumpAndSettle();
    expect(find.text('서울숲 호수'), findsOneWidget);
  });

  testWidgets('후보가 하나면 "다른 코스" 가 없다', (tester) async {
    await _pump(tester, _card(source: _Source(const [_park])));
    expect(find.byKey(const Key('today-course-next')), findsNothing);
  });

  testWidgets('안전 지수가 "피하세요" 면 코스 대신 "오늘의 코스는 쉬어요"', (tester) async {
    await _pump(tester, _card(source: _Source(const [_trail, _park])));
    WalkSafetyStore.latest.value =
        const WalkSafetyVerdict(WalkSafetyLevel.avoid, '지금은 피하고 저녁 7시 뒤에', ['33°C']);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-course-rest')), findsOneWidget);
    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
    expect(find.byKey(const Key('today-course')), findsNothing);
  });

  testWidgets('"짧게" 면 목표가 반이 되어 짧은 코스가 앞서고 이유에 온도와 "오늘은 짧게" 가 붙는다', (tester) async {
    WalkSafetyStore.latest.value =
        const WalkSafetyVerdict(WalkSafetyLevel.short, '짧게 다녀오세요', ['29°C', '미세먼지 보통']);
    await _pump(tester, _card(source: _Source(const [_trail, _park, _mine])));

    expect(find.text('서울숲 호수'), findsOneWidget, reason: '1km 목표엔 1.2km 공원');
    expect(find.textContaining('29°C · 오늘은 짧게 · 목표 1.0km'), findsOneWidget);
  });

  testWidgets('최근 7일에 간 곳은 뒤로 밀리고 이유에 "최근에 간 곳" 이 붙는다', (tester) async {
    final data = _feed(walks: [_walk(at: _now.subtract(const Duration(days: 2)), contentId: '2733847')]);
    await _pump(tester, _card(source: _Source(const [_trail, _park]), data: data));

    expect(find.text('서울숲 둘레길'), findsOneWidget, reason: '공원은 이틀 전에 갔다');
    await tester.tap(find.byKey(const Key('today-course-next')));
    await tester.pumpAndSettle();
    expect(find.text('서울숲 호수'), findsOneWidget);
    expect(find.textContaining('최근에 간 곳'), findsOneWidget);
  });

  testWidgets('"여기서 산책 시작" 은 그 장소를 들고 산책을 시작한다', (tester) async {
    WalkPlaceRef? started;
    await _pump(tester, _card(source: _Source(const [_park]), onStart: (_, place) async => started = place));

    await tester.tap(find.byKey(const Key('today-course-start')));
    await tester.pumpAndSettle();

    expect(started?.title, '서울숲 호수');
    expect(started?.source, 'kto');
    expect(started?.contentId, '2733847');
  });

  // 셋을 한 테스트에서 pumpWidget 으로 이어 그리면 같은 자리의 State 가 재사용돼 initState 가 다시
  // 안 돌고, 앞 카드의 후보가 그대로 남아 "없다" 가 공짜로 통과한다(되돌리기에서 잡혔다). 따로 잰다.
  testWidgets('위치가 없으면 카드가 없고 후보를 묻지도 않는다', (tester) async {
    final source = _Source(const [_park]);
    await _pump(tester, _card(source: source, located: false));
    expect(find.byKey(const Key('today-course')), findsNothing);
    expect(source.calls, 0, reason: '위치가 없으면 후보를 묻지 않는다');
  });

  testWidgets('처음엔 위치가 없다가 동의가 읽히면 다시 시도해 카드가 뜬다 — 앱을 껐다 켤 때까지 없는 카드가 아니다', (tester) async {
    var located = false;
    final source = _Source(const [_park]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TodayCourseCard(
          dog: _dog,
          data: _feed(),
          source: source,
          locate: () async => located ? (lat: 37.5445, lng: 127.0374) : null,
          now: () => _now,
          onStart: (_, __) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-course')), findsNothing);
    expect(source.calls, 0);

    located = true;
    LocationService.consented.value = !LocationService.consented.value; // 동의 값이 바뀌었다
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-course')), findsOneWidget);
    expect(source.calls, 1);
    LocationService.consented.value = false;
  });

  testWidgets('후보가 없으면 카드가 없다 — 가짜를 놓지 않는다', (tester) async {
    await _pump(tester, _card(source: _Source(const [])));
    expect(find.byKey(const Key('today-course')), findsNothing);
  });

  testWidgets('게스트면 후보가 있어도 카드가 없다 — 산책을 시작할 수 없는 사람에게 권하지 않는다', (tester) async {
    await _pump(tester, _card(source: _Source(const [_park]), data: _feed(guest: true)));
    expect(find.byKey(const Key('today-course')), findsNothing);
    expect(find.byKey(const Key('today-course-rest')), findsNothing);
  });

  testWidgets('이번 주 목표를 거의 채웠으면 남은 몫만큼만 — 20분이면 1.3km 목표', (tester) async {
    // 소형견 목표 150분/주. 이번 주 분은 서버 통계 + 전송 대기 초안이라(`weekMinutesWithPending`)
    // 10분짜리 초안 열셋을 오늘 날짜로 둔다 → 130분 → 오늘 20분 → 기록이 없으니 4km/h → 1.3km.
    final today = DateTime.now();
    final drafts = [
      for (var i = 0; i < 13; i++)
        WalkDraft.fresh(
            startedAt: today, endedAt: today.add(const Duration(minutes: 10)), distanceM: 667, durationS: 600, path: const []),
    ];
    await _pump(tester, _card(source: _Source(const [_trail, _park]), data: _feed(pending: drafts)));
    expect(find.textContaining('목표 1.3km'), findsOneWidget);
  });
}
