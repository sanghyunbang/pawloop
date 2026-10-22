// 홈의 "오늘의 코스" 카드 (#485) — 산책 시작 버튼 바로 아래.
//
// 고르는 것은 `CourseRecommender`(규칙)이고 여기는 재료를 모아 넘기고 결과를 그린다:
// 위치(기기) → 후보(`CourseCandidateSource`) · 안전 지수(`WalkSafetyStore`, 안전 카드가 채운다) ·
// 이번 주 목표에서 남은 몫(`WalkGoal` · `WalkFeedData`) · 최근 7일에 간 곳(내 기록의 장소).
//
// 카드는 하나다 — "다른 코스" 가 다음 점수를 보여 준다. 안전 지수가 "피하세요" 면 코스 대신
// "오늘은 쉬어요". 위치가 없거나 후보가 없으면 카드 자체가 없다(가짜를 놓지 않는다).
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

import '../data/course_candidates.dart';
import '../data/location_service.dart';
import '../data/walk_feed.dart';
import '../data/walk_goal_store.dart';
import '../data/walk_repository.dart' show WalkPlaceRef;
import '../data/walk_safety.dart';
import '../data/walk_safety_repository.dart';
import '../domain/course_recommender.dart';
import '../data/pet_places_repository.dart' show PetPlace;
import '../domain/walk_destination.dart';
import '../domain/pet.dart';
import '../domain/walk_goal.dart';
import '../theme/app_tokens.dart';
import 'aurora.dart';

/// "여기서 산책 시작" 을 홈이 받는 모양.
///
/// [destination] 은 그 코스가 **어디인가** (#623) — 있으면 `startWalk` 이 어디서
/// 시작할지 한 번 묻는다. 내 코스의 시작 지점을 모르는 경우처럼 없을 수도 있다.
typedef StartCourseWalk = Future<void> Function(
    BuildContext context, WalkPlaceRef place, WalkDestination? destination);

/// 카드 **본문**을 눌렀을 때 — 홈이 장소 시트를 연다(#723). 예전에는 칩 하나만 반응했다.
typedef OpenCourse = Future<void> Function(
    BuildContext context, CourseCandidate course, PetPlace? place);

class TodayCourseCard extends StatefulWidget {
  const TodayCourseCard({
    super.key,
    required this.dog,
    required this.data,
    this.source,
    this.locate,
    this.now,
    this.goals = const WalkGoalStore(),
    required this.onStart,
    this.onOpen,
  });

  final DogProfile? dog;
  final WalkFeedData data;

  /// 후보를 주는 자리 — 기본은 기기 안 카탈로그 + 내 코스. 테스트가 가짜를 꽂는다.
  final CourseCandidateSource? source;

  /// 위치 — 기본은 `LocationService.locate`(동의 전이면 null). 테스트가 가짜를 꽂는다.
  final Future<({double lat, double lng})?> Function()? locate;
  final DateTime Function()? now;
  final WalkGoalStore goals;

  /// "이 코스 걷기" — 홈이 `startWalk(place:)` 를 꽂는다(위젯은 화면을 import 하지 않는다,
  /// `legacy_shell_reachability_test`). 테스트가 가짜를 꽂는다.
  final StartCourseWalk onStart;

  /// 본문 탭 — 홈이 `openCourse` 를 꽂는다(#723). 없으면 본문은 예전처럼 아무 일도 안 한다.
  final OpenCourse? onOpen;

  /// 위치를 못 받았을 때 한 번 더 보기까지의 시간. 실내에서 앱을 막 켠 참이면 GPS 가 아직이다.
  static const Duration retryDelay = Duration(seconds: 8);

  @override
  State<TodayCourseCard> createState() => _TodayCourseCardState();
}

class _TodayCourseCardState extends State<TodayCourseCard> with WidgetsBindingObserver {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  List<CourseCandidate>? _candidates;
  WalkGoal? _goal;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // 첫 시도는 실패하기 쉽다 — 동의 값이 아직 안 읽혔거나 실내라 좌표가 안 잡힌 때다(안전 카드와 같다).
    LocationService.consented.addListener(_retry);
    // 안전 카드나 산책 시작에서 권한을 허용하면 그 신호로 다시 시도한다(#517).
    LocationService.permissionRev.addListener(_retry);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationService.consented.removeListener(_retry);
    _retryTimer?.cancel();
    LocationService.permissionRev.removeListener(_retry);
    super.dispose();
  }

  /// 앱으로 돌아올 때 한 번 더 — 위치를 못 잡았던 자리에서 나갔다 온 것일 수 있다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retry();
  }

  /// 아직 후보가 없을 때만 다시 — 있으면 하루 한 번의 추천을 흔들지 않는다.
  void _retry() {
    if (_candidates == null) _loadCandidates();
  }

  @override
  void didUpdateWidget(TodayCourseCard old) {
    super.didUpdateWidget(old);
    if (old.dog?.serverId != widget.dog?.serverId) _loadGoal();
  }

  /// 후보를 준 곳 — 카드를 누르면 `placeOf` 로 장소 시트의 재료를 묻는다(#723).
  CourseCandidateSource? _source;

  Future<void> _load() async {
    await Future.wait([_loadCandidates(), _loadGoal()]);
  }

  bool _retriedLocate = false;
  Timer? _retryTimer;

  Future<void> _loadCandidates() async {
    final where = await (widget.locate ?? _locate)();
    if (where == null) {
      // 2026-09-21 폰에서 카드가 떴다가 **사라졌다** — 홈이 다시 그려지며 이 카드가 새로 서고, 그 순간
      // 위치를 못 잡으면 그 세션 내내 카드가 없었다. 한 번만 조금 뒤에 다시 본다(동의·권한이 없는
      // 경우는 `consented`·`permissionRev` 가 따로 깨운다).
      if (!_retriedLocate) {
        _retriedLocate = true;
        _retryTimer = Timer(TodayCourseCard.retryDelay, () {
          if (mounted) _retry();
        });
      }
      return;
    }
    final source = widget.source ?? CourseCandidates(includeMine: !widget.data.guest);
    _source = source;
    List<CourseCandidate> found;
    try {
      found = await source.around(lat: where.lat, lng: where.lng);
    } catch (e) {
      if (kDebugMode) debugPrint('[TodayCourse] 후보를 못 모음: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _candidates = found);
  }

  Future<void> _loadGoal() async {
    final dog = widget.dog;
    final saved = dog == null ? null : await widget.goals.read(petId: dog.serverId);
    if (!mounted) return;
    setState(() => _goal = saved ??
        (dog == null
            ? null
            : WalkGoal.recommendedFor(species: dog.species, size: dog.size, ageMonths: dog.ageMonths)));
  }

  /// 권한이 없으면 **묻지 않는다** — 안전 카드와 같은 이유다(#517). 그쪽의 "허용" 줄이
  /// 설명을 먼저 보여 주고, 허용되면 `permissionRev` 로 여기까지 온다.
  static Future<({double lat, double lng})?> _locate() async {
    final fix = await LocationService.locate(prompt: false);
    final p = fix.position;
    if (p != null) return (lat: p.latitude, lng: p.longitude);
    // 새 좌표를 못 받았다(실내 GPS 시간 초과 등). 마지막으로 알던 자리면 충분하다 — 이 카드는 2km·5km
    // 반경으로 고르니 100m 는 상관없다. 동의·권한 문제면 그대로 없음이다(위치를 안 쓰기로 한 사람).
    if (fix.denial != LocationDenial.unavailable) return null;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      return (lat: last.latitude, lng: last.longitude);
    } catch (_) {
      return null;
    }
  }

  /// 오늘 걸을 분 — 목표가 없으면(아이 없음 · 개가 아님) 30분.
  int _targetMinutes() {
    final goal = _goal;
    final daily = goal == null ? 30 : (goal.minutesPerWeek / goal.daysPerWeek).round();
    return CourseRecommender.todayMinutes(
      dailyMinutes: daily,
      weeklyMinutes: goal?.minutesPerWeek ?? daily * WalkGoal.defaultDaysPerWeek,
      minutesThisWeek: widget.data.minutesThisWeek,
    );
  }

  /// 최근 7일에 간 카탈로그 장소 — 그곳은 뒤로 민다.
  Set<String> _recentIds() {
    final since = (widget.now ?? DateTime.now)().subtract(const Duration(days: 7));
    return {
      for (final w in widget.data.walks)
        if (w.startedAt.isAfter(since) && w.place?.contentId != null) w.place!.contentId!,
    };
  }

  List<CourseRecommendation> _ranked(WalkSafetyVerdict? verdict) => CourseRecommender.rank(
        candidates: _candidates ?? const [],
        targetMinutes: _targetMinutes(),
        safety: verdict?.level,
        paceKmPerHour: CourseRecommender.paceOf(
            [for (final w in widget.data.walks.take(10)) (distanceM: w.distanceM, durationS: w.durationS)]),
        recentIds: _recentIds(),
        hot: (WalkSafetyStore.reading?.tempC ?? 0) >= 25,
      );

  /// 큰 칩을 눌렀을 때. 카탈로그 장소면 **장소 시트를 연다** — 추천 코스(1·2·3km, #725)와 진짜
  /// "이 코스 걷기" 가 거기 있다. 2026-09-21 실기기에서 이 칩을 눌러 바로 "N km 떨어져 있어요" 로
  /// 갔고 추천 코스는 한 번도 못 봤다 — 시트는 본문을 눌러야 열렸고, 본문이 눌린다는 표시가 없었다.
  /// 내 코스는 열 시트가 아직 없어서(#723 다음 조각) 예전처럼 바로 [_start] 다.
  Future<void> _primary(CourseCandidate c) {
    final place = _source?.placeOf(c);
    final open = widget.onOpen;
    if (place != null && open != null) return open(context, c, place);
    return _start(c);
  }

  /// 시트를 열 것이면 '코스 보기', 바로 걷기 시작이면 '이 코스 걷기' — 하는 일과 이름이 같아야 한다.
  String _primaryLabel(CourseCandidate c) =>
      _source?.placeOf(c) != null && widget.onOpen != null ? '코스 보기' : '이 코스 걷기';

  Future<void> _start(CourseCandidate c) async {
    final place = WalkPlaceRef(title: c.title, source: c.source, contentId: c.contentId);
    // 좌표를 함께 넘긴다 (#623). 이 카드는 `450m 거리` 를 직접 보여 주면서 그 거리를
    // 없는 것처럼 다뤘다 — 이제 어디서 시작할지 묻는다.
    final lat = c.lat;
    final lng = c.lng;
    await widget.onStart(
      context,
      place,
      lat == null || lng == null
          ? null
          : WalkDestination(lat: lat, lng: lng, distanceM: c.distanceM),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.guest || _candidates == null || _candidates!.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<WalkSafetyVerdict?>(
      valueListenable: WalkSafetyStore.latest,
      builder: (_, verdict, __) {
        if (verdict?.level == WalkSafetyLevel.avoid) return _rest(verdict!);
        final ranked = _ranked(verdict);
        if (ranked.isEmpty) return const SizedBox.shrink();
        final pick = ranked[_index % ranked.length];
        return _card(pick, verdict, hasNext: ranked.length > 1);
      },
    );
  }

  /// "피하세요" 면 코스를 고르지 않는다 — 그 대신 언제 다시 볼지.
  Widget _rest(WalkSafetyVerdict verdict) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GlassCard(
          key: const Key('today-course-rest'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            const Icon(Icons.wb_sunny_outlined, color: T.warmEnd),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('오늘의 코스는 쉬어요',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 2),
                Text(verdict.headline, style: const TextStyle(fontSize: 12, color: T.textMuted)),
              ]),
            ),
          ]),
        ),
      );

  Widget _card(CourseRecommendation pick, WalkSafetyVerdict? verdict, {required bool hasNext}) {
    final c = pick.course;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        key: const Key('today-course'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        // 본문 어디를 눌러도 장소 시트가 열린다(#723) — 예전에는 칩 하나만 반응했다. 칩과
        // '다른 코스' 는 안쪽 GestureDetector 라 먼저 잡고, 본문으로 번지지 않는다.
        child: GestureDetector(
          key: const Key('today-course-open'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen == null ? null : () => widget.onOpen!(context, c, _source?.placeOf(c)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('오늘의 코스',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: T.warmText)),
              const Spacer(),
              Text(c.kind.label, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _leading(c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.title,
                      key: const Key('today-course-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 3),
                  Text(_subtitle(c), style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text(_reason(pick, verdict),
                key: const Key('today-course-reason'),
                style: const TextStyle(fontSize: 12, color: T.textMuted, height: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              if (hasNext)
                TextButton(
                  key: const Key('today-course-next'),
                  onPressed: () => setState(() => _index++),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('다른 코스',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
                ),
              const Spacer(),
              GestureDetector(
                key: const Key('today-course-start'),
                onTap: () => _primary(c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.pets, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    // '여기서 산책 시작' 이었다 — 멀리서도 "여기서" 로 읽혀서 바꿨다(#724). 장소면
                    // '코스 보기' 로 시트를 연다(2026-09-21) — 추천 코스와 걷기 버튼이 거기 있다.
                    Text(_primaryLabel(c),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _leading(CourseCandidate c) {
    final image = c.image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: image == null
            ? _iconTile(c)
            : Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _iconTile(c)),
      ),
    );
  }

  Widget _iconTile(CourseCandidate c) => Container(
        color: T.surface,
        alignment: Alignment.center,
        child: Icon(
          switch (c.kind) {
            CourseKind.trail || CourseKind.localTrail => Icons.route_rounded,
            CourseKind.playground => Icons.fence_rounded,
            CourseKind.park => Icons.park_rounded,
            CourseKind.myCourse => Icons.bookmark_rounded,
          },
          color: T.warmEnd,
        ),
      );

  static String _subtitle(CourseCandidate c) {
    final parts = <String>[_distanceLabel(c.distanceM)];
    final len = c.lengthM;
    if (len != null) parts.add('코스 ${(len / 1000).toStringAsFixed(1)}km');
    return parts.join(' · ');
  }

  static String _distanceLabel(double meters) =>
      meters < 950 ? '${(meters / 50).round() * 50}m 거리' : '${(meters / 1000).toStringAsFixed(1)}km 거리';

  /// 이유 — 사실만 늘어놓는다. "AI" 라고 쓰지 않는다(#347).
  static String _reason(CourseRecommendation pick, WalkSafetyVerdict? verdict) {
    final parts = <String>[];
    if (verdict != null && verdict.reasons.isNotEmpty) parts.add(verdict.reasons.first);
    if (pick.shortened) parts.add('오늘은 짧게');
    parts.add('목표 ${pick.targetKm.toStringAsFixed(1)}km');
    if (pick.course.isMine) parts.add('내가 만든 코스');
    if (pick.visitedRecently) parts.add('최근에 간 곳');
    // 2km 안에 걷는 곳이 없어 넓힌 후보다(`CourseCandidates.widenRadiusM`). 왜 먼 코스를 권하는지
    // 말해야 "2.6km 거리" 가 실수로 안 읽힌다 — 양재동에서 카드가 조용히 사라지던 자리(2026-09-21).
    if (pick.course.distanceM > CourseCandidates.radiusM) parts.add('2km 안엔 걸을 곳이 없어 조금 멀어요');
    return parts.join(' · ');
  }
}
