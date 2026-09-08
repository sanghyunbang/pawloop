import '../widgets/walk_locating_view.dart';
import '../widgets/walk_stats_panel.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_tokens.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import '../widgets/map_unavailable.dart';
import '../domain/pet.dart';
import '../domain/walk_moment.dart';
import '../data/location_service.dart';
import '../data/location_upload_policy.dart';
import '../data/pet_places_repository.dart';
import '../data/place_catalog_repository.dart';
import '../data/walk_in_progress.dart';
import '../data/walk_outbox.dart';
import '../data/walk_repository.dart';
import '../walk/route_image.dart';
import '../walk/route_photo_saver.dart';
import '../widgets/walk_finish_sheet.dart';
import '../widgets/walk_moment_bar.dart';
import 'create_screen.dart';

/// 실시간 산책 트래킹 — "기록계"가 아니라 걷는 동안 주변을 탐색하는 지도.
/// - 지도 자유 조작(핀치줌 + 줌 버튼), 제스처 시 자동 따라가기 해제 → 따라가기 버튼으로 복귀
/// - 주변 반려 장소 검색(카테고리/텍스트) + POI 핀 탭 정보
/// - 스탯(거리/시간)은 접힌 알약이 기본, 탭하면 펼침
/// - 뒤로가기는 확인 후 종료(실수 방지)
class WalkTrackingScreen extends StatefulWidget {
  /// 끊긴 산책의 스냅숏. 있으면 그 경로·거리·초에서 이어 간다(#335).
  final WalkInProgress? resume;

  /// 어디서 시작했나 — 지도에서 "여기서 산책 시작" 으로 왔으면 채워진다(#338).
  /// 초안에 실려 저장 화면까지 간다. 좌표가 아니라 카탈로그의 이름·식별자다.
  final WalkPlaceRef? place;

  /// 따라 걸을 코스의 선 (#339). "다시 걷기" 로 왔으면 지도에 <b>연한 선</b>으로 깔아 준다.
  /// 내 경로와 색이 다르다 — 겹쳐 놓고도 어느 쪽이 지금 걷는 것인지 알아야 한다.
  final List<List<double>>? courseLine;

  /// 함께 나간 아이들의 서버 id — 이슈 #343. 시작 전에 "누구랑 나가요?" 로 고른 것이다.
  ///
  /// **비어 있을 수 있다.** 한 마리면 묻지 않으므로 비고, 그때는 전송이 대표 아이 하나로
  /// 보낸다(계약이 `dogIds` 를 선택으로 받는다).
  final List<int> dogIds;

  const WalkTrackingScreen({
    super.key,
    this.resume,
    this.place,
    this.courseLine,
    this.dogIds = const [],
  });
  @override
  State<WalkTrackingScreen> createState() => _WalkTrackingScreenState();
}

class _WalkTrackingScreenState extends State<WalkTrackingScreen> with WidgetsBindingObserver {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  NaverMapController? _ctrl;
  Timer? _timer;
  StreamSubscription<Position>? _posSub;
  bool _paused = false;

  /// 위치 판정 결과. **`null` 이면 아직 판정 전이고, 그동안 지도를 만들지 않는다.**
  ///
  /// 예전에는 위치를 못 잡으면 이 화면이 서울숲 근처 가짜 루프를 그리고 거리를 올렸다
  /// (`_makeRoute`/`_advanceSim`). M0 시절 UX 확인용이었는데 실 GPS 가 붙은 뒤로는
  /// **지어낸 숫자가 저장 화면까지 흘러가는 통로**였다. 이슈 #160 에서 통째로 지웠다.
  ///
  /// 판정 전에 지도를 만들지 않는 이유는 따로 있다. 타이머가 첫 위치를 기다리는 동안
  /// 그린 점이 경로 앞머리에 남기 때문이다. 실측한 것: 광화문에서 시작했더니 저장된
  /// 경로가 `LINESTRING(37.5448 127.0397, … 37.5665 126.978, …)` 이었다 — 앞 4점이
  /// 서울숲이고 그 다음이 5.5km 떨어진 진짜 위치였다. 앱이 잰 거리는 555m 인데 DB 의
  /// `ST_Length` 는 6,421m 였다. **경로와 거리가 서로 다른 말을 했다.** (#145)
  LocationFix? _fix;
  bool _follow = true; // 카메라 자동 따라가기(제스처 시 해제)
  // 기본 펼침 — 종료 버튼이 첫 프레임부터 보인다(#327). 접는 것은 사용자가 고른다.
  bool _statsExpanded = WalkStatsPanel.expandedByDefault;
  bool _poisLoaded = false;

  /// 주변 장소를 받는 중인가.
  ///
  /// 이게 없으면 받는 동안 검색바가 '주변 반려 장소 찾기' 로 남고 시트를 열면
  /// '조건에 맞는 곳이 없어요' 라고 한다 — **기다리는 중인데 없다고 말한다.**
  /// 카탈로그는 첫 실행에 2.83MB 를 받으므로 그 창이 몇 초는 된다(이슈 #275).
  bool _poisLoading = false;

  /// 열려 있는 주변 장소 시트를 다시 그리는 손잡이. 닫히면 `null`.
  ///
  /// **부모의 `setState` 는 모달 시트를 다시 그리지 않는다.** 시트는 별도 라우트라
  /// `_poisLoading`·`_places` 가 바뀌어도 그대로다 — 받는 중에 열어 두면 로딩이
  /// 끝나도 스피너가 영원히 돈다(#283 검토, 프레임워크 소스로 확인). 그래서
  /// `StatefulBuilder` 의 `setSheet` 를 잡아 두고 값이 바뀔 때 직접 부른다.
  StateSetter? _sheetRefresh;
  int _seconds = 0;
  double _km = 0;

  /// 산책이 실제로 시작된 시각. **서버가 요구하는 값이고, 없으면 저장 자체가 안 된다.**
  ///
  /// `_seconds` 로 역산하지 않는다 — 일시정지 동안 그 값이 멈추므로 뺄셈이 실제 시작
  /// 시각보다 늦게 나온다. 시작한 순간을 그냥 적어 둔다.
  DateTime? _startedAt;

  /// 주변 반려 장소(검색 시트/핀 공용).
  List<PetPlace> _places = const [];

  /// 실제로 걸은 좌표만 들어간다. 지어낸 점은 한 개도 넣지 않는다.
  final List<NLatLng> _path = [];

  /// 각 점이 찍힌 시각 — **시작 기준 델타 초.** `_path` 와 길이가 같다. 이슈 #155.
  ///
  /// `LINESTRING` 은 x, y 만 담아서 점마다 몇 초에 찍혔는지가 어디에도 없었다. 시각은
  /// **그 순간에만 있는 정보라 나중에 만들 수 없다** — 안 보내면 그 산책에 대해 구간
  /// 페이스·일시정지 구간 복원·거리 재계산이 영영 불가능해진다.
  ///
  /// `_seconds` 를 그대로 쓴다. 그래서 **일시정지 동안은 초가 안 흐르고**, 델타가
  /// 건너뛰면 그 사이가 멈춘 구간이라는 것을 나중에 추론할 수 있다.
  final List<int> _pathT = [];

  /// 산책 중 한 탭으로 남긴 것들과 취소 규칙 (#340). 규칙은 화면 밖에 있다 —
  /// 이 화면은 지도·GPS 를 물고 있어 위젯 테스트로 못 띄우기 때문이다.
  final WalkMomentLog _log = WalkMomentLog();

  /// "다시 누르면 취소" 표시를 5초 뒤에 지우는 손잡이. 판정 자체는 [_log] 가 한다.
  Timer? _undoTimer;

  /// 화면에 지금 취소 안내를 띄울 종류. [_log] 의 판정을 그대로 옮겨 담는다.
  WalkMomentKind? _undoable;

  /// 5초마다 기기에 적는 스냅숏(#335). 앱이 죽었다 살아나면 [WalkResumePrompt] 가 읽는다.
  static const _snapshots = WalkInProgressStore();
  int _sinceSave = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 지도가 준비되기를 기다리지 않는다 — 위치 판정이 먼저다. 판정이 끝나야 지도를
    // 만들지 말지가 정해진다.
    _start();
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  /// 뒤로 갔다 돌아오면 그 사이 쌓인 점으로 선과 카메라를 맞춘다. 스트림은 포그라운드 서비스가
  /// 계속 돌린다(#335) — 여기서 다시 열지 않는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {});
    _drawPath();
    if (_follow && _path.isNotEmpty) _ctrl?.updateCamera(NCameraUpdate.withParams(target: _path.last));
  }

  void _snapshot() {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    unawaited(_snapshots.save(WalkInProgress(
      startedAt: startedAt,
      seconds: _seconds,
      distanceM: (_km * 1000).round(),
      path: [for (final p in _path) [p.longitude, p.latitude]],
      pathT: List<int>.of(_pathT),
      moments: _log.moments,
      savedAt: DateTime.now(),
    )));
  }

  /// 한 손 기록 버튼 (#340). **누르면 바로 기록**이고, 5초 안에 같은 것을 다시 누르면 취소다.
  ///
  /// 확인을 묻지 않는 이유는 이 기능의 전제다 — 확인이 붙으면 한 탭이 두 탭이 되고,
  /// 줄을 쥔 손으로는 그 두 번째를 못 누른다.
  void _tapMoment(WalkMomentKind kind) {
    HapticFeedback.selectionClick();
    _undoTimer?.cancel();

    final now = DateTime.now();
    final result = _log.tap(
      kind,
      tSec: _seconds,
      now: now,
      // 경로의 마지막 점 = 지금 서 있는 자리. 좌표를 새로 베끼지 않는다(A안 #235).
      pathIndex: _path.isEmpty ? null : _path.length - 1,
    );
    final undoing = result == WalkMomentTap.cancelled;
    setState(() => _undoable = _log.undoableAt(now));

    // 눌린 것이 화면 밖으로 사라지지 않게 스낵바로 한 줄 — 취소도 이 문장으로 알린다.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(undoing ? '${kind.label} 기록을 취소했어요' : '${kind.label} 기록했어요'),
        duration: const Duration(milliseconds: 1400),
      ));

    if (!undoing) {
      _undoTimer = Timer(WalkMomentLog.undoWindow, () {
        if (mounted) setState(() => _undoable = null);
      });
    }
    _snapshot();
  }

  // ───────────── 트래킹 ─────────────

  /// 위치를 판정하고, 쓸 수 있을 때에만 트래킹을 시작한다.
  ///
  /// 못 쓰면 **아무것도 시작하지 않는다** — 타이머도 안 돌린다. 걷지 않은 시간이
  /// 올라가면 저장 화면이 그 값을 물려받는다.
  Future<void> _start() async {
    final fix = await LocationService.locate();
    if (!mounted) return;
    setState(() => _fix = fix);
    final pos = fix.position;
    if (pos == null) return;

    final resume = widget.resume;
    if (resume != null) {
      // 끊긴 자리에서 이어 간다. 죽어 있던 동안은 초에 안 들어가고, 마지막 점에서 지금 자리까지는
      // 직선 거리로 더한다 — 실제로 걸은 길의 하한이다.
      _startedAt = resume.startedAt;
      _seconds = resume.seconds;
      _km = resume.km;
      _path.addAll([for (final p in resume.path) NLatLng(p[1], p[0])]);
      _pathT.addAll(resume.pathT);
      // 눌러 둔 것도 함께 살아난다 — 배변 두 번이 앱이 죽었다고 사라지면 안 된다(#340).
      _log.addAll(resume.moments);
    } else {
      _startedAt = DateTime.now();
    }
    final first = NLatLng(pos.latitude, pos.longitude);
    if (_path.isNotEmpty) _km += _dist(_path.last, first);
    _path.add(first);
    // 첫 점도 t 를 갖는다 — path 와 pathT 는 길이가 같아야 한다(스냅숏도 서버 계약도).
    _pathT.add(_seconds);
    // 안드로이드 13+: 알림 권한이 있어야 포그라운드 서비스 알림이 보인다. 거부해도 기록은 된다.
    await LocationService.requestNotificationPermission();
    if (!mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // 일시정지 중에도 적는다 — 멈춰 선 채 앱이 죽어도 그때까지의 경로는 남아야 한다.
      if (++_sinceSave >= 5) {
        _sinceSave = 0;
        _snapshot();
      }
      if (_paused) return;
      setState(() => _seconds++);
    });
    _listenPositions();
    _loadNearbyPlaces(_path.first);
  }

  /// 위치 스트림 구독. 끊기면(플러그인 오류·서비스 종료) 말하고 다시 이을 길을 준다 — 조용히
  /// 0km 로 걷게 두지 않는다. WAKE_LOCK 권한이 빠졌을 때 정확히 그렇게 됐다(#335 실측).
  void _listenPositions() {
    _posSub?.cancel();
    final dogName = kMyDog.value?.name ?? '우리 아이';
    _posSub = LocationService.stream(notificationTitle: '$dogName랑 산책 기록 중').listen((p) {
      if (_paused || !mounted) return;
      final cur = NLatLng(p.latitude, p.longitude);
      setState(() {
        if (_path.isNotEmpty) _km += _dist(_path.last, cur);
        _path.add(cur);
        // 둘을 **같은 setState 안에서** 늘린다. 나뉘면 그 사이에 길이가 어긋나고,
        // 서버가 400 으로 거절한다(계약: path 와 길이가 같아야 한다).
        _pathT.add(_seconds);
      });
      _drawPath();
      if (_follow) _ctrl?.updateCamera(NCameraUpdate.withParams(target: cur));
      if (!_poisLoaded) _loadNearbyPlaces(cur);
        }, onError: (Object e) {
      if (kDebugMode) debugPrint('[WalkTracking] 위치 스트림 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('위치 갱신이 끊겼어요'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: '다시 연결', onPressed: _listenPositions),
      ));
    });
  }

  /// 거절 화면에서 다시 시도. 판정을 처음 상태로 되돌리고 [_start] 를 다시 탄다.
  Future<void> _retry() async {
    setState(() => _fix = null);
    await _start();
  }

  double _dist(NLatLng a, NLatLng b) {
    const R = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _rad(double d) => d * math.pi / 180;

  /// 따라 걸을 코스 선. 내 경로보다 **먼저·연하게** 깐다 — 위에 내 선이 얹혀야 한다.
  Future<void> _drawCourseLine() async {
    final c = _ctrl;
    final line = widget.courseLine;
    if (c == null || line == null || line.length < 2) return;
    await c.addOverlay(NPolylineOverlay(
      id: 'course-line',
      coords: [for (final p in line) NLatLng(p[1], p[0])],
      color: const Color(0x668C7BFF),
      width: 9,
    ));
  }

  Future<void> _drawPath() async {
    final c = _ctrl;
    if (c == null || _path.length < 2) return;
    await c.addOverlay(
      NPolylineOverlay(
        id: 'walk-path',
        coords: _path,
        color: const Color(0xFFFF7E8A),
        width: 7,
      ),
    );
    await c.addOverlay(
      NMarker(
        id: 'walk-head',
        position: _path.last,
        iconTintColor: const Color(0xFFFF7E8A),
      ),
    );
  }

  // ───────────── 주변 장소 ─────────────
  Future<void> _loadNearbyPlaces(NLatLng center) async {
    // **여기서 멈추지 않는다** (이슈 #273).
    //
    // 예전에는 정책이 꺼져 있으면 `_poisLoaded = true` 로 두고 돌아섰다. 저장소가
    // 어차피 빈 목록을 줬고, 위치 스트림이 5m 마다 다시 부르면 산책 내내 헛일을
    // 반복하기 때문이었다.
    //
    // 지금은 좌표를 안 보내고도 답이 나온다 — 저장소가 전국 한 벌에서 기기 안으로
    // 거른다(`PlaceCatalogRepository`). 여기서 멈추면 그 길이 영영 안 불린다.
    //
    // 헛일 걱정은 그대로 없다: 두 번째부터는 메모리에 있는 목록을 훑을 뿐이고
    // 네트워크가 안 나간다.
    if (mounted) setState(() => _poisLoading = true);
    _sheetRefresh?.call(() {});
    final List<PetPlace> places;
    try {
      places = await PetPlacesRepository().fetchNearby(
        lat: center.latitude,
        lng: center.longitude,
        radius: 3000,
        numOfRows: 40,
      );
    } finally {
      if (mounted) setState(() => _poisLoading = false);
      // 시트가 열려 있으면 그것도 다시 그린다 — 안 그러면 스피너가 안 사라진다.
      _sheetRefresh?.call(() {});
    }
    if (!mounted || _ctrl == null || places.isEmpty) return;
    // setState 없이 필드만 바꾸면 검색바가 계속 '주변 반려 장소 찾기' 로 남는다 —
    // 찾아 놓고 못 찾은 척한다.
    setState(() => _places = places);
    _sheetRefresh?.call(() {});
    final markers = <NAddableOverlay>{};
    for (final p in places) {
      final m = NMarker(
        id: 'poi-${p.contentId.isEmpty ? p.title : p.contentId}',
        position: NLatLng(p.lat, p.lng),
        icon: await _poiIcon(p.petCategory),
      );
      m.setOnTapListener((_) => _showPoiInfo(p));
      markers.add(m);
    }
    if (mounted && markers.isNotEmpty) {
      await _ctrl?.addOverlayAll(markers);
      _poisLoaded = true;
    }
  }

  Future<NOverlayImage> _poiIcon(PetCategory cat) async {
    return NOverlayImage.fromWidget(
      context: context,
      size: const Size(36, 36),
      widget: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cat.color,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: cat.color.withValues(alpha: 0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(cat.icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _goTo(PetPlace p) {
    setState(() => _follow = false);
    _ctrl?.updateCamera(
      NCameraUpdate.withParams(target: NLatLng(p.lat, p.lng), zoom: 16.5),
    );
  }

  void _showPoiInfo(PetPlace p) {
    final cat = p.petCategory;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.of(sheetCtx).padding.bottom,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cat.color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(cat.icon, size: 23, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: T.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${cat.label}${p.distLabel.isNotEmpty ? ' · ${p.distLabel}' : ''} · 반려동반 가능',
                    style: const TextStyle(fontSize: 12, color: T.textMuted),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(sheetCtx),
              child: const Icon(
                Icons.close,
                size: 21,
                color: Color(0xFFBBB3CC),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 주변 찾기 시트 — 카테고리 + 텍스트 필터, 탭하면 그 위치로.
  void _openNearbySheet() {
    String q = '';
    String? cat;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          _sheetRefresh = setSheet;
          final cats = kPetCategories
              .where((c) => _places.any((p) => p.categoryKey == c.key))
              .toList();
          final list = _places.where((p) {
            if (cat != null && p.categoryKey != cat) return false;
            if (q.isNotEmpty && !p.title.contains(q)) return false;
            return true;
          }).toList();
          return Container(
            height: MediaQuery.of(sheetCtx).size.height * 0.66,
            decoration: const BoxDecoration(
              color: Color(0xFAFCFAFF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0x2E281E30),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  // 아직 세지 않은 것을 0 이라 적지 않는다 — 검색바와 같은 분기다.
                  _poisLoading && _places.isEmpty
                      ? '주변 장소를 불러오는 중…'
                      : '주변 반려 장소 ${_places.length}곳',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: T.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0x338C7BFF)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: TextField(
                    onChanged: (v) => setSheet(() => q = v.trim()),
                    style: const TextStyle(fontSize: 14, color: T.textPrimary),
                    decoration: const InputDecoration(
                      icon: Icon(Icons.search, size: 19, color: T.textMuted),
                      hintText: '이름으로 찾기 (예: 카페)',
                      hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _catChip(
                        '전체',
                        null,
                        cat == null,
                        () => setSheet(() => cat = null),
                      ),
                      for (final c in cats)
                        _catChip(
                          c.label,
                          c.key,
                          cat == c.key,
                          () => setSheet(() => cat = c.key),
                          color: c.color,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: _poisLoading && _places.isEmpty
                              ? const Column(mainAxisSize: MainAxisSize.min, children: [
                                  SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFFF8F63))),
                                  SizedBox(height: 10),
                                  Text('주변 장소를 불러오는 중이에요',
                                      style: TextStyle(fontSize: 13, color: T.textMuted)),
                                ])
                              : Text(
                                  // 한 벌을 못 받은 것을 "없다" 고 말하지 않는다 —
                                  // 탐색 화면의 `_catalogUnavailable` 과 같은 판정.
                                  _places.isEmpty &&
                                          !LocationUploadPolicy.canQueryNearbyPlaces &&
                                          !PlaceCatalogRepository.instance.hasCatalog
                                      ? '장소 목록을 아직 못 받았어요'
                                      : '조건에 맞는 곳이 없어요',
                                  style: const TextStyle(fontSize: 13, color: T.textMuted),
                                ),
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final p = list[i];
                            final c = p.petCategory;
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                _goTo(p);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: c.color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Icon(
                                        c.icon,
                                        size: 18,
                                        color: c.color,
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: T.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${c.label}${p.distLabel.isNotEmpty ? ' · ${p.distLabel}' : ''}',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: T.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.near_me_outlined,
                                      size: 17,
                                      color: Color(0xFFCABFDC),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null); // 닫히면 손잡이를 놓는다 — 죽은 시트를 다시 그리지 않는다
  }

  Widget _catChip(
    String label,
    String? key,
    bool on,
    VoidCallback onTap, {
    Color? color,
  }) {
    final c = color ?? const Color(0xFFFF8F63);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: on ? c : const Color(0xFFF1ECF7),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : T.textSecondary,
          ),
        ),
      ),
    );
  }

  // ───────────── 종료/이탈 ─────────────
  String get _timeLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _pace {
    if (_km < 0.01 || _seconds == 0) return "-'--\"";
    final secPerKm = _seconds / _km;
    final m = (secPerKm ~/ 60), s = (secPerKm % 60).round();
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  // 뒤로가기/이탈 — 실수로 산책 날리지 않게 확인.
  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFFFCFAFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '산책을 그만둘까요?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: T.textPrimary,
          ),
        ),
        content: const Text(
          '지금 나가면 이번 산책 기록은 저장되지 않아요.',
          style: TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text(
              '계속 걷기',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFE07A4E),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('나가기', style: TextStyle(color: T.textMuted)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _timer?.cancel();
      _posSub?.cancel();
      unawaited(_snapshots.clear());
      Navigator.of(context).pop();
    }
  }

  /// 방금 끝낸 산책을 초안으로 만든다. **여기서 만들지 못하면 기록이 사라진다.**
  ///
  /// ## 좌표를 뒤집어 담는다
  ///
  /// `NLatLng` 는 (위도, 경도)인데 계약과 서버는 **`[경도, 위도]`** 다. 이 한 줄을
  /// 빠뜨리면 지도에 엉뚱한 곳이 찍히고, 서버가 400 으로 거절한다(위도 자리에 127 이
  /// 오기 때문이다).
  ///
  /// `_startedAt` 이 없으면 `null` 이다. 트래킹이 시작되지 않았다는 뜻이고
  /// (`_start` 가 위치 없이는 아무것도 시작하지 않는다), 그러면 저장 화면이 손입력으로
  /// 열린다. 지어낸 값을 조용히 올리는 것보다 낫다.
  WalkDraft? _draft() {
    final startedAt = _startedAt;
    if (startedAt == null) return null;

    return WalkDraft.fresh(
      dogIds: widget.dogIds,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      distanceM: (_km * 1000).round(),
      durationS: _seconds,
      path: [
        for (final p in _path) [p.longitude, p.latitude],
      ],
      pathT: List<int>.of(_pathT),
      place: widget.place,
      moments: _log.moments,
    );
  }

  /// 산책 완료 시트 — 몸통은 `WalkFinishSheet`(#310) 다. 이 화면은 geolocator·네이버 지도를
  /// 물고 있어 위젯 테스트로 못 띄우므로, 시트의 동작(경로 미리보기 · 사진 저장 · 두 버튼)은
  /// 그 위젯의 테스트가 잰다. 여기서는 메모리에 든 좌표를 그대로 건넨다 — 새로 GPS 를 켜지 않는다.
  void _finish() {
    _timer?.cancel();
    _posSub?.cancel();
    // 산책은 끝났다 — 저장 화면이 실패해도 초안 큐(WalkOutbox)가 맡는다. 스냅숏은 지운다.
    unawaited(_snapshots.clear());
    final walkedAt = _startedAt ?? DateTime.now();
    final distanceLabel = '${_km.toStringAsFixed(2)}km';
    final art = RouteArt(
      // 계약·초안 큐와 같은 [경도, 위도] 순서 — `_draft()` 와 같다.
      lngLat: [for (final p in _path) [p.longitude, p.latitude]],
      distanceLabel: distanceLabel,
      timeLabel: _timeLabel,
      dateLabel: WalkFinishSheet.dateLabel(walkedAt),
      moments: _log.moments,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => WalkFinishSheet(
        timeLabel: _timeLabel,
        distanceLabel: distanceLabel,
        paceLabel: _pace,
        art: art,
        walkedAt: walkedAt,
        saver: RoutePhotoSaver.gallery(),
        // 공유 카드 (#344) — 아이 이름과 장소는 이 화면이 이미 알고 있다.
        // 색은 앱의 코랄을 쓴다: DogProfile 에 아이별 색이 없다(#344 본문의
        // "아바타 테두리색" 은 아직 저장되는 값이 아니다).
        dogName: kMyDog.value?.name,
        placeName: widget.place?.title,
        warm: _warm,
        onSave: () {
          Navigator.pop(sheetCtx);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CreateScreen(
                prefillPlace: widget.place?.title,
                draft: _draft(),
              ),
            ),
          );
        },
        onDiscard: () {
          Navigator.pop(sheetCtx);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    // 판정 전에는 지도를 만들지 않는다. 만들면 초기 카메라를 어딘가로 잡아야 하는데,
    // 그 '어딘가' 가 예전의 서울숲이었다.
    final fix = _fix;
    if (fix == null) return const _LocatingScreen();
    final denial = fix.denial;
    if (denial != null) {
      return WalkLocationDeniedScreen(denial: denial, onRetry: _retry, placeTitle: widget.place?.title);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              // 키가 없으면 지도를 그리지 않는다. 트래킹 자체는 계속 돈다 —
              // GPS·거리·시간은 지도와 무관하고, 아래 스탯 패널이 그대로 보인다.
              child: !Env.hasNaverMap
                  ? const MapUnavailable(
                      what: '산책은 계속 기록되고 있어요.\n경로를 지도에 그리지 못할 뿐이에요.')
                  : NaverMap(
                options: NaverMapViewOptions(
                  // 판정을 통과했으므로 _path 에 실제 첫 좌표가 이미 들어 있다.
                  initialCameraPosition: NCameraPosition(
                    target: _path.first,
                    zoom: 16,
                  ),
                  locale: const Locale('ko'),
                  scaleBarEnable: false,
                ),
                onMapReady: (c) {
                  _ctrl = c;
                  // 지도가 늦게 준비되는 동안 이미 걸었을 수 있다 — 지금까지의
                  // 경로를 바로 그리고 카메라를 마지막 점으로 옮긴다.
                  c.updateCamera(
                    NCameraUpdate.withParams(target: _path.last, zoom: 16),
                  );
                  _drawCourseLine();
                  _drawPath();
                  // _start 가 지도보다 먼저 끝나면 그때의 POI 적재는 `_ctrl == null`
                  // 로 버려진다. 가만히 서 있는 사용자는 위치 스트림 갱신
                  // (distanceFilter 5m)이 안 와서 재시도 기회도 없다. 여기서 한 번
                  // 더 건다.
                  if (!_poisLoaded) _loadNearbyPlaces(_path.last);
                },
                // 사용자가 지도를 움직이면 자동 따라가기 해제(자유 탐색).
                onCameraChange: (reason, animated) {
                  if (reason == NCameraUpdateReason.gesture && _follow) {
                    setState(() => _follow = false);
                  }
                },
              ),
            ),
            // 상단: 뒤로(확인) + 주변 찾기 검색바
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _confirmExit,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x1F000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: T.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openNearbySheet,
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F5A4690),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                size: 18,
                                color: T.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _places.isEmpty
                                    ? (_poisLoading ? '주변 장소를 불러오는 중…' : '주변 반려 장소 찾기')
                                    : '주변 반려 장소 ${_places.length}곳 보기',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: T.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 우측: 줌 컨트롤 + 따라가기
            Positioned(
              right: 12,
              bottom: 150,
              child: Column(
                children: [
                  _roundBtn(
                    Icons.add,
                    () => _ctrl?.updateCamera(NCameraUpdate.zoomBy(1)),
                  ),
                  const SizedBox(height: 8),
                  _roundBtn(
                    Icons.remove,
                    () => _ctrl?.updateCamera(NCameraUpdate.zoomBy(-1)),
                  ),
                  const SizedBox(height: 8),
                  _roundBtn(
                    Icons.my_location_rounded,
                    () {
                      setState(() => _follow = true);
                      if (_path.isNotEmpty) {
                        _ctrl?.updateCamera(
                          NCameraUpdate.withParams(
                            target: _path.last,
                            zoom: 16,
                          ),
                        );
                      }
                    },
                    color: _follow ? const Color(0xFFE07A4E) : T.textSecondary,
                  ),
                ],
              ),
            ),
            // 하단: 한 손 기록 줄 + 스탯 패널(기본 접힘 알약, 탭하면 펼침)
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 스탯 패널이 접히든 펼쳐지든 **항상 보인다** — 눌러야 할 때 패널을 먼저
                  // 펼쳐야 한다면 그건 이미 한 탭이 아니다(#340).
                  WalkMomentBar(
                    tally: _log.tally,
                    undoable: _undoable,
                    onTap: _tapMoment,
                  ),
                  const SizedBox(height: 8),
                  _statsPanel(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: color ?? T.textSecondary),
      ),
    );
  }

  Widget _statsPanel(BuildContext context) => WalkStatsPanel(
        km: _km,
        timeLabel: _timeLabel,
        paceLabel: _pace,
        paused: _paused,
        expanded: _statsExpanded,
        onToggle: () => setState(() => _statsExpanded = !_statsExpanded),
        onPauseToggle: () => setState(() => _paused = !_paused),
        onFinish: _finish,
        bottomInset: MediaQuery.of(context).padding.bottom,
      );
}

/// 위치를 판정하는 동안. 아주 짧게 스쳐 가지만, 이 순간에 지도를 만들지 않는 것이
/// 이 화면의 요점이다 — 판정 전에 만든 지도는 카메라를 어딘가 잡아야 하고, 그
/// '어딘가' 가 예전의 서울숲 가짜 좌표였다.
class _LocatingScreen extends StatelessWidget {
  const _LocatingScreen();

  @override
  Widget build(BuildContext context) => const WalkLocatingView();
}

/// 위치를 쓸 수 없을 때. **가짜 경로 대신 이 화면이 나온다.**
///
/// `private` 이 아닌 이유는 테스트가 이유별 문구를 직접 확인하기 때문이다 — 완료
/// 조건이 "권한 거부와 사용자 중단이 다른 문구를 낸다" 이고, 그건 화면을 펌프해
/// 봐야 알 수 있다.
///
/// 이유마다 사용자가 할 일이 다르다. 예전에는 이유를 구분하지 않았고, 애초에 이
/// 화면이 없었다 — 위치가 없으면 서울숲 근처를 대신 걸어 주고 거리가 올라갔다.
/// 부산에서 권한을 끈 사람의 산책이 서울숲에 기록될 수 있었다. (이슈 #160)
class WalkLocationDeniedScreen extends StatelessWidget {
  final LocationDenial denial;
  final Future<void> Function() onRetry;

  /// 지도에서 "여기서 산책 시작" 으로 왔으면 그 이름 (#338). 위치가 막혀 손으로 적더라도
  /// 어디였는지는 이미 알고 있으므로 저장 화면에 미리 채워 준다.
  final String? placeTitle;

  const WalkLocationDeniedScreen({
    super.key,
    required this.denial,
    required this.onRetry,
    this.placeTitle,
  });

  /// 무엇이 막혔는지. 사용자가 화면에서 읽는 문장이다.
  String get _title => switch (denial) {
    LocationDenial.notConsented => '위치기반서비스 동의가 필요해요',
    LocationDenial.pausedByUser => '위치 수집을 중단해 두셨어요',
    LocationDenial.serviceOff => '기기의 위치 서비스가 꺼져 있어요',
    LocationDenial.denied => '위치 권한이 필요해요',
    LocationDenial.deniedForever => '위치 권한이 꺼져 있어요',
    LocationDenial.unavailable => '현재 위치를 확인할 수 없어요',
  };

  /// 무엇을 하면 되는지. 사용자가 고칠 수 없는 경우(실내·터널)에는 고치라고 하지
  /// 않는다.
  String get _body => switch (denial) {
    LocationDenial.notConsented =>
      '약관 동의를 확인하는 중이에요. 잠시 뒤 다시 시도해 주세요.',
    LocationDenial.pausedByUser =>
      '프로필에서 켜면 산책 경로가 다시 기록돼요.',
    LocationDenial.serviceOff =>
      '설정에서 위치 서비스를 켜 주세요. 앱 권한과는 별개예요.',
    LocationDenial.denied =>
      '경로를 그리려면 위치가 필요해요. 다시 시도하면 한 번 더 여쭤볼게요.',
    LocationDenial.deniedForever =>
      '앱에서는 다시 여쭤볼 수 없어요. 설정 > 앱 > 위치에서 허용해 주세요.',
    LocationDenial.unavailable =>
      '실내나 터널에서는 신호가 약할 수 있어요. 잠시 뒤 다시 시도해 주세요.',
  };

  /// 첫 번째 버튼이 하는 일 — 이유마다 다르다.
  ///
  /// `deniedForever` 는 앱이 권한을 다시 물을 수 없으므로 OS 설정으로 보낸다.
  /// `serviceOff` 는 앱 권한이 아니라 기기 설정이라 위치 설정 화면으로 보낸다.
  /// `pausedByUser` 는 **앱 안에서 끝난다** — 토글을 끄고 바로 다시 시도한다.
  (String, Future<void> Function()) get _primary => switch (denial) {
    // 이 화면은 로그인한 사람만 온다 — `startWalk` 이 미로그인이면 로그인 화면부터
    // 띄운다. 그러니 여기서 동의가 없다는 것은 **아직 못 읽었다**는 뜻이고,
    // 다시 시도가 정확한 답이다. '로그인하기' 라고 적어 놓고 재시도만 하면 화면이
    // 거짓말하는 것이 된다.
    LocationDenial.notConsented => ('다시 시도', onRetry),
    LocationDenial.pausedByUser => (
      '위치 수집 다시 켜기',
      () async {
        // 디스크에도 남긴다 — 여기서만 메모리를 바꾸면 다음 실행에 다시 중단된다.
        await LocationService.setPaused(false);
        await onRetry();
      },
    ),
    LocationDenial.serviceOff => (
      '위치 설정 열기',
      () async {
        await Geolocator.openLocationSettings();
      },
    ),
    LocationDenial.deniedForever => (
      '앱 설정 열기',
      () async {
        await Geolocator.openAppSettings();
      },
    ),
    LocationDenial.denied || LocationDenial.unavailable => (
      '다시 시도',
      onRetry,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (primaryLabel, primaryAction) = _primary;
    return Scaffold(
      backgroundColor: T.lilacTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: T.textPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x22FF8F63),
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  size: 38,
                  color: Color(0xFFE07A4E),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: T.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.55,
                  color: Color(0xBD463C64),
                ),
              ),
              const Spacer(),
              _filled(primaryLabel, primaryAction),
              const SizedBox(height: 10),
              // 위치 없이도 기록은 남길 수 있다 — 다만 사용자가 직접 적는다.
              // 앱이 대신 지어내지 않는다.
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateScreen(prefillPlace: placeTitle),
                  ),
                ),
                child: const Text(
                  '직접 입력해서 기록하기',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: T.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filled(String label, Future<void> Function() onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.8, -1),
          end: Alignment(0.8, 1),
          colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    ),
  );
}
