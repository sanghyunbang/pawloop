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
import 'package:heat_trip_flutter/v2/domain/walk_destination.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/today_course_card.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';

class _Source implements CourseCandidateSource {
  _Source(this.candidates);
  final List<CourseCandidate> candidates;
  int calls = 0;
  @override
  Future<List<CourseCandidate>> around({required double lat, required double lng}) async {
    calls++;
    return candidates;
  }

  @override
  PetPlace? placeOf(CourseCandidate course) => course.id == _park.id ? _parkPlace : null;
}

const _trail = CourseCandidate(
    id: 'trail:1', title: '서울숲 둘레길', kind: CourseKind.trail, distanceM: 500, lengthM: 3000, source: 'trail', contentId: 'trail:1');
const _parkPlace = PetPlace(
    contentId: '2733847', title: '서울숲 호수', contentTypeId: '12', addr: '서울 성동구', image: '', tel: '',
    lat: 37.5445, lng: 127.0374, distM: 800);
const _park = CourseCandidate(
    id: '2733847', title: '서울숲 호수', kind: CourseKind.park, distanceM: 800, lengthM: 1200, source: 'kto', contentId: '2733847',
    lat: 37.5445, lng: 127.0374);
const _mine = CourseCandidate(id: 'course:7', title: '아침 한 바퀴', kind: CourseKind.myCourse, distanceM: 1500, lengthM: 2000);
/// 2km 안에 걷는 곳이 없어 넓힌 후보 — 2.6km 밖 공원.
const _parkFar = CourseCandidate(
    id: '99', title: '양재시민의숲', kind: CourseKind.park, distanceM: 2600, lengthM: 1500, source: 'kto', contentId: '99',
    lat: 37.47, lng: 127.04);
/// 시작 지점을 아는 내 코스 — 칩이 좌표를 들고 가는지 재는 데 쓴다.
const _mineAt = CourseCandidate(
    id: 'course:7', title: '아침 한 바퀴', kind: CourseKind.myCourse, distanceM: 1500, lengthM: 2000,
    lat: 37.5445, lng: 127.0374);

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
  OpenCourse? onOpen,
}) =>
    TodayCourseCard(
      dog: dog ?? _dog,
      data: data ?? _feed(),
      source: source,
      locate: () async => located ? (lat: 37.5445, lng: 127.0374) : null,
      now: () => _now,
      onStart: onStart ?? (_, __, ___) async {},
      onOpen: onOpen,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyStore.clear();
  });

  testWidgets('후보가 있으면 1등 하나를 카드로 — 이름 · 거리 · 코스 길이 · 이유', (tester) async {
    await _pump(tester, _card(source: _Source(const [_trail, _park, _mine])));

    expect(find.byKey(const Key('today-course')), findsOneWidget);
    expect(find.text('아침 한 바퀴'), findsOneWidget, reason: '소형견 하루 30분 → 2km 목표, 내 코스 2.0km 가 1등');
    expect(find.textContaining('1.5km 거리'), findsOneWidget);
    expect(find.textContaining('코스 2.0km'), findsOneWidget);
    expect(find.textContaining('목표 2.0km'), findsOneWidget);
    expect(find.textContaining('내가 만든 코스'), findsOneWidget);
    expect(find.text('이 코스 걷기'), findsOneWidget);
    expect(find.text('여기서 산책 시작'), findsNothing, reason: '#724 — 멀리서도 "여기서" 로 읽히던 말');
    expect(find.textContaining('조금 멀어요'), findsNothing, reason: '2km 안의 후보에는 안 붙는다');
  });

  testWidgets('2km 안에 걷는 곳이 없어 넓힌 후보면 "2.6km 거리" 와 함께 왜 먼지 말한다 (2026-09-21)', (tester) async {
    await _pump(tester, _card(source: _Source(const [_parkFar])));

    expect(find.byKey(const Key('today-course')), findsOneWidget, reason: '넓힌 후보를 추천기가 버리면 카드가 없다');
    expect(find.text('양재시민의숲'), findsOneWidget);
    expect(find.textContaining('2.6km 거리'), findsOneWidget);
    expect(find.textContaining('2km 안엔 걸을 곳이 없어 조금 멀어요'), findsOneWidget);
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

  testWidgets('카탈로그 장소면 본문도 칩("코스 보기")도 장소 시트를 연다 — 추천 코스가 거기 있다 (#723 · #725)',
      (tester) async {
    CourseCandidate? opened;
    PetPlace? openedPlace;
    var started = 0;
    await _pump(
        tester,
        _card(
          source: _Source(const [_park]),
          onOpen: (_, c, p) async {
            opened = c;
            openedPlace = p;
          },
          onStart: (_, __, ___) async => started++,
        ));

    expect(find.text('코스 보기'), findsOneWidget);
    expect(find.text('이 코스 걷기'), findsNothing,
        reason: '그 이름의 버튼은 시트 안에 있다 — 여기서 같은 이름으로 다른 일을 하면 안 된다');

    await tester.tap(find.byKey(const Key('today-course-title')));
    await tester.pumpAndSettle();
    expect(opened?.id, '2733847');
    expect(openedPlace?.title, '서울숲 호수', reason: '시트를 열 재료(카탈로그 장소)를 후보를 준 곳에서 받아 함께 보낸다');
    expect(started, 0);

    opened = null;
    await tester.tap(find.byKey(const Key('today-course-start')));
    await tester.pumpAndSettle();
    expect(opened?.id, '2733847',
        reason: '2026-09-21 — 칩이 시트를 건너뛰어 바로 "떨어져 있어요" 로 갔고, 추천 코스는 한 번도 안 보였다');
    expect(started, 0, reason: '걷기는 시트의 "이 코스 걷기" 가 한다 — 받은 코스 선을 들고');
  });

  testWidgets('내 코스는 열 시트가 아직 없다 — 칩이 "이 코스 걷기" 이고 **좌표**를 들고 바로 산책을 시작한다 (#623 · #723)',
      (tester) async {
    WalkPlaceRef? started;
    WalkDestination? startedTo;
    var opened = 0;
    await _pump(
        tester,
        _card(
          source: _Source(const [_mineAt]),
          onOpen: (_, __, ___) async => opened++,
          onStart: (_, place, dest) async {
            started = place;
            startedTo = dest;
          },
        ));

    expect(find.text('이 코스 걷기'), findsOneWidget);
    expect(find.text('코스 보기'), findsNothing, reason: '열 시트가 없는데 "보기" 라고 적으면 거짓이다');

    await tester.tap(find.byKey(const Key('today-course-start')));
    await tester.pumpAndSettle();

    expect(opened, 0);
    expect(started?.title, '아침 한 바퀴');

    // 좌표가 없으면 `startWalk` 이 거리를 못 가르고, 카드가 `1.5km 거리` 를 보여 주면서 그 거리를
    // 없는 것처럼 다루던 옛 화면으로 돌아간다.
    expect(startedTo, isNotNull, reason: '카드가 좌표를 안 넘기면 가를 수가 없다');
    expect(startedTo!.lat, 37.5445);
    expect(startedTo!.lng, 127.0374);
    expect(startedTo!.distanceM, 1500);
  });

  // 셋을 한 테스트에서 pumpWidget 으로 이어 그리면 같은 자리의 State 가 재사용돼 initState 가 다시
  // 안 돌고, 앞 카드의 후보가 그대로 남아 "없다" 가 공짜로 통과한다(되돌리기에서 잡혔다). 따로 잰다.
  testWidgets('처음에 위치를 못 잡으면 8초 뒤 한 번 더 본다 — 실내에서 막 켠 참에 카드가 영영 안 뜨던 자리 (2026-09-21)',
      (tester) async {
    var calls = 0;
    final source = _Source(const [_park]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TodayCourseCard(
            dog: _dog,
            data: _feed(),
            source: source,
            // 첫 번째는 실패, 두 번째부터 자리.
            locate: () async => ++calls == 1 ? null : (lat: 37.5445, lng: 127.0374),
            now: () => _now,
            onStart: (_, __, ___) async {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('today-course')), findsNothing, reason: '첫 시도는 실패다');

    await tester.pump(TodayCourseCard.retryDelay);
    await tester.pumpAndSettle();
    expect(calls, 2, reason: '한 번 더 물어야 한다');
    expect(find.byKey(const Key('today-course')), findsOneWidget, reason: '두 번째에 잡히면 카드가 선다');
  });

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
          onStart: (_, __, ___) async {},
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
