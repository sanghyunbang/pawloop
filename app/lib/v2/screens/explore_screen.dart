import 'dart:async';

import '../data/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import '../widgets/map_unavailable.dart';
import '../widgets/marker_icons.dart';
import '../widgets/place_sheet.dart';
import '../widgets/place_loop_picker.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import 'post_write_screen.dart';
import '../domain/pet.dart';
import '../domain/map_camera_owner.dart';
import '../domain/serial_refresh.dart';
import '../domain/vet_hours.dart';
import '../walk/route_image.dart';
import '../domain/course_path.dart';
import '../domain/walk_destination.dart';
import '../data/course_repository.dart';
import 'start_walk.dart';
import '../data/walk_repository.dart';
import '../data/pet_places_repository.dart';
import '../data/place_catalog_repository.dart';
import '../data/place_loop_repository.dart';
import '../data/trail_route_repository.dart';
import '../data/location_upload_policy.dart';
import '../data/location_service.dart';
import '../data/neighborhood_store.dart';
import '../domain/neighborhood.dart';
import '../widgets/aurora.dart';
import 'course_sheet.dart' show placePostsLink;
import 'main_shell.dart' show RootTab;
import '../widgets/profile_avatar.dart';

/// 지도 — 관광공사 반려동물 동반여행(KTO) 기반 "우리 아이랑 갈 수 있는 곳".
/// 리스트/지도 토글 + 카테고리 필터.
///
/// 병원·펫샵·산책로 칩은 #282 에서 가짜와 함께 내렸다가 #291 에서 실데이터로 돌아왔다 —
/// 행정안전부 인허가(전국)와 두루누비 걷기여행길을 서버가 카탈로그 한 벌에 이어 붙인다.
/// 산책로는 카탈로그에 **시작점**만 있고, 시트를 열면 선을 따로 받아 지도에 그린다
/// (`TrailRouteRepository`). 지도 키 없는 빌드는 선을 못 그리고 카드의 요약만 본다.
///
/// 칩을 누르면 **칩 키를 붙여 다시 조회**한다. 가까운 80곳을 받아 놓고 그 안에서 거르면
/// 병원 칩이 빈다 — 서울시청 근처는 백화점 매장 80곳이 어느 병원보다 가깝다(#291 실측).
/// 서버·카탈로그는 거른 뒤에 자르므로 키만 붙이면 된다. 늦게 돌아온 옛 조회는 버린다.
/// "여기서 산책 시작" 을 붙이는 카테고리 (#338).
///
/// 여행지·카페·식당·레포츠·산책로다. 병원·펫샵·숙박·쇼핑·문화는 뺐다 — 거기서 산책을
/// 시작한다는 말이 어색하고, 어색한 버튼은 화면의 신뢰를 깎는다.
const Set<String> kWalkStartCategories = {'12', '39', '28', 'trail'};

/// 선이 없는 산책로를 눌렀을 때의 지도 배율 (#619).
///
/// 목록의 기본값(12~13)보다 가깝다. 시작 지점 <b>하나</b>를 보여 주는 자리라, 그 점이
/// 어느 동네인지 읽힐 만큼은 들어가야 한다. 선이 있는 코스는 이 값을 안 쓴다 —
/// 거기는 선 전체가 들어오게 맞춘다(`fitBounds`).
const double _kTrailPointZoom = 15;

/// 지도 뷰의 **판단** 둘 — 이슈 #628.
///
/// 지도 SDK 는 위젯 테스트에 없어서 화면으로는 못 잰다. 그래서 판단만 여기 떼어 둔다.
/// 화면이 맞게 그리는지는 실기기에서 보고, 여기서 지키는 것은 **숫자가 조용히 바뀌지
/// 않는 것**이다 — 문턱이 100m 나 10km 가 되면 화면은 멀쩡해 보이면서 버튼이 계속 뜨거나
/// 영영 안 뜬다.
class ExploreMap {
  ExploreMap._();

  /// 이만큼 멀어져야 "이 지역에서 다시 찾기" 를 띄운다.
  ///
  /// 조회 반경이 8km 다. 그 안에서 조금 움직인 것으로 버튼을 띄우면 같은 답을 다시 받게
  /// 되고, 버튼이 깜빡여 지도를 가린다. 1km 는 **목록이 실제로 달라지기 시작하는** 거리다 —
  /// 걸어서 15분쯤이고, 그만큼 옮겼으면 다른 동네를 보는 중이다.
  static const double researchThresholdM = 1000;

  /// 지도를 여기까지 옮겼다. 다시 찾을 만큼 멀면 그 지점, 아니면 `null`.
  static NLatLng? researchTarget(NLatLng loadedAt, NLatLng cameraAt) =>
      haversineMeters(loadedAt.latitude, loadedAt.longitude, cameraAt.latitude,
                  cameraAt.longitude) >=
              researchThresholdM
          ? cameraAt
          : null;

  /// 지도를 옮겼을 때 **바로** 다시 거를 것인가.
  ///
  /// 기기 안에서 거르는 빌드(지금)는 전국 한 벌이 이미 기기에 있어 **네트워크가 0** 이다 —
  /// 부를 서버가 없는데 버튼을 눌러 달라고 할 이유가 없다.
  ///
  /// 신고를 마치고 `UPLOAD_LOCATION` 을 켜면 이 조회가 서버로 간다. 그때는 끄는 동안 계속
  /// 부르게 되므로 버튼으로 묻는다. **이 한 줄이 그 갈래 전부다** — 화면에는 판단이 없다.
  static bool get refiltersOnDrag => !LocationUploadPolicy.canQueryNearbyPlaces;

  /// 뭉친 곳의 개수 딱지.
  ///
  /// **이게 없으면 80곳이 한 점으로 보인다.** 패키지 기본 빌더
  /// (`NaverMapClusteringOptions.defaultClusterMarkerBuilder`)는 이걸 하는데, 우리가
  /// 아이콘을 쓰려고 빌더를 덮으면서 같이 잃었다 — 2026-09-17 신고.
  static NOverlayCaption clusterCaption(int size) => NOverlayCaption(
        text: '$size',
        textSize: 13,
        color: Colors.white,
        haloColor: Colors.transparent,
      );
}

class ExploreScreen extends StatefulWidget {
  final String initialView; // 'list' | 'map'

  /// 테스트가 진짜 네트워크·카탈로그에 닿지 않게 끼우는 자리. 없으면 실물이다.
  final PetPlacesRepository? repository;

  /// 이웃 코스 저장소. 테스트가 꽂는 자리다 (#339).
  final CourseRepository? courses;
  /// 내 동네를 읽는 자리 (#342). **테스트만 넘긴다.**
  final NeighborhoodStore? neighborhoods;

  /// 산책로 경로 저장소 — 선이든 경유지든 (#291 · #619). **테스트만 넘긴다.**
  final TrailRouteRepository? trailRoutes;

  /// 추천 코스 저장소 (#725) — 장소 시트의 1·2·3km 줄이 쓴다. **테스트만 넘긴다.**
  final PlaceLoopRepository? loops;

  const ExploreScreen({
    super.key,
    this.initialView = 'list',
    this.repository,
    this.courses,
    this.neighborhoods,
    this.trailRoutes,
    this.loops,
  });
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late String view = widget.initialView;
  NaverMapController? _mapCtrl;
  late final PetPlacesRepository _repo = widget.repository ?? PetPlacesRepository();
  late final CourseRepository _courses = widget.courses ?? CourseRepository();
  late final TrailRouteRepository _trails = widget.trailRoutes ?? TrailRouteRepository();

  // 기본 중심: 서울 시청. (추후 현재 위치)
  NLatLng _center = const NLatLng(37.5665, 126.9816);
  List<PetPlace> _places = const [];

  // ─────────────────── 검색 (#620) ───────────────────
  //
  // **서버를 안 부른다.** 카탈로그 한 벌(18,870곳)이 이미 기기에 있고 찾는 일도 거기서
  // 한다(`PlaceCatalogRepository.search`, #338). 검색어를 서버로 보내면 A안(#235)이
  // 깨진다 — 좌표를 안 보내면서 "서울숲" 을 보내면 앞문을 잠그고 뒷문을 여는 셈이다.
  //
  // 그 함수는 글쓰기·동네 고르기 화면이 이미 쓰고 있었다. **지도만 안 붙어 있었고**,
  // 그 자리에 `TextField` 가 아니라 `Text` 가 있었다 — 눌러도 아무 일이 없는 그림이었다.
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  List<PetPlace> _hits = const [];
  bool _searching = false;

  /// 글자마다 18,870곳을 훑지 않는다. 손이 멈추면 한 번 훑는다.
  Timer? _searchDebounce;

  bool get _isSearching => _query.trim().isNotEmpty;

  // ─────────── 지도를 움직였을 때 (#628) ───────────
  //
  // 지도를 끌면 보고 있는 곳이 바뀌는데 목록은 처음 받은 자리 것 그대로였다. 다시 받는
  // 코드가 **한 줄도 없었다** — `onCameraIdle` 을 아예 안 듣고 있었다.

  /// 카메라가 여기서 멈췄다. `null` 이면 다시 찾을 거리만큼 안 움직였다는 뜻이다.
  NLatLng? _movedTo;

  /// 이만큼 멀어져야 "다시 찾기" 를 띄운다.
  ///
  /// 조회 반경이 8km 다. 그 안에서 조금 움직인 것으로 버튼을 띄우면 같은 답을 다시 받게
  /// 되고, 버튼이 계속 깜빡여 지도를 가린다. 1km 는 **목록이 실제로 달라지기 시작하는**
  /// 거리다 — 걸어서 15분쯤이고, 그만큼 옮겼으면 다른 동네를 보는 중이다.

  bool _loading = true;
  /// 내가 고른 동네 (#342). 현위치를 못 받았을 때 서울시청 대신 여기를 쓴다.
  Neighborhood? _myNeighborhood;

  /// 현위치를 못 받아 **기본 중심**인가. 게스트(동의 전)·권한 거부·실패 모두 여기다.
  /// 그 기본이 서울시청인지 내 동네인지는 [_myNeighborhood] 가 정한다(#342).
  /// 화면에 그 말이 없으면 사용자는 왜 중구가 나오는지 모른다(#324).
  bool _fallbackCenter = true;
  /// 시트에서 "지도에서 보기" 를 눌렀는데 지도 뷰가 아직 안 만들어졌을 때 — 만들어지면 그린다.
  PetPlace? _pendingTrail;
  /// 클러스터 핀 그림 — 한 번 그려 두고 `_clusterMarker` 가 쓴다. 빌더는 동기라 여기서 못 그린다.
  NOverlayImage? _clusterIcon;
  /// null = 전체, 아니면 contenttypeid 또는 레이어 열쇠말(`vet`·`shop`·`trail`…).
  ///
  /// 처음 값은 오늘의 케어 카드가 부탁한 갈래다(#560) — [RootTab.exploreCategory].
  /// 읽고 바로 되돌리므로 다음에 지도를 그냥 열면 전체다.
  String? _catFilter = RootTab.takeExploreCategory();

  /// 카메라를 지금 누가 쥐고 있나 — 앱인가 사용자인가(#769).
  final MapCameraOwner _camera = MapCameraOwner();

  /// 앱이 **스스로** 카메라를 옮긴다. 사용자가 이미 지도를 만졌으면 옮기지 않는다.
  ///
  /// 여기를 지나지 않는 `updateCamera` 는 **사용자가 부탁한 이동**이다(산책로를 고르면 그 코스로,
  /// 검색 결과를 누르면 그 장소로). 그런 것까지 막으면 눌러도 지도가 안 따라오는 다른 고장이 된다.
  Future<void> _autoMoveCamera(NCameraUpdate update) async {
    if (!_camera.mayAutoMove) return;
    await _mapCtrl?.updateCamera(update);
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 고른 동네를 **기다리지 않는다** (#342). 기기 저장소 읽기가 늦거나 실패해도 지도는
    // 그대로 열려야 한다 — 여기서 await 하면 그 하나가 첫 조회 전체를 붙잡는다.
    unawaited(_applyMyNeighborhood());

    // 현위치 확보 → 실패 시 기본 중심(서울시청 또는 고른 동네) 유지.
    final pos = await LocationService.current();
    if (mounted && pos != null) {
      // **사용자가 이미 지도를 만졌으면 뺏지 않는다**(#769). 현위치는 최대 25초까지 기다리는데
      // (`LocationService.currentSettingsFor` 의 `timeLimit`), 그 사이 사용자는 이미 확대해 놓았다.
      // 늦게 도착한 값이 그것을 덮어 장소가 다시 뭉치로 접혔다(에뮬레이터 실측).
      //
      // 그때는 **보고 있는 곳**이 목록의 기준이다 — 카메라만 남기고 기준점을 현위치로 옮기면
      // 화면은 명동인데 마커는 성수에 찍힌다. 내 위치로 가고 싶으면 지도의 현위치 버튼이 있다.
      final at = _camera.mayAutoMove ? null : await _mapCtrl?.getCameraPosition();
      if (mounted) {
        _center = at?.target ?? NLatLng(pos.latitude, pos.longitude);
        _fallbackCenter = false;
        await _autoMoveCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
      }
    }
    await _load();
  }

  /// 고른 동네가 있으면 그 동네에서 연다 (#342).
  ///
  /// 좌표는 기기 안의 자산에서 온 값이라 서버도 위치 권한도 필요 없다. **현위치가 이미
  /// 잡혔으면 안 건드린다** — 늦게 도착한 이 값이 진짜 위치를 덮으면 안 된다.
  Future<void> _applyMyNeighborhood() async {
    Neighborhood? read;
    try {
      read = await (widget.neighborhoods ?? NeighborhoodStore()).read();
    } catch (_) {
      // 저장소를 못 읽어도 지도는 열린다.
      return;
    }
    final mine = read;
    if (!mounted || mine == null || !_fallbackCenter) return;
    setState(() {
      _myNeighborhood = mine;
      _center = NLatLng(mine.lat, mine.lng);
    });
    await _autoMoveCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
  }

  /// 조회 순번 — 칩을 빠르게 두 번 누르면 먼저 간 조회가 늦게 돌아올 수 있다. 마지막만 남긴다.
  /// 병원 칩 안의 "24시" 토글. 이름 기준이고, 카테고리를 바꾸면 꺼진다 —
  /// 켜 둔 채로 다른 칩으로 가면 "왜 안 나오지" 가 된다.
  bool _only24h = false;

  /// 산책로 칩 안의 "이웃 코스" 토글 (#339). 켜면 공공데이터 산책로 대신 **사람들이 올린
  /// 코스**를 본다. 카테고리를 바꾸면 꺼진다.
  bool _neighbourCourses = false;

  /// 받아 둔 공개 코스에서 **기기가 고른** 가까운 것들. 좌표는 서버로 안 나간다(A안 #235).
  List<Course> _nearbyCourses = const [];
  bool _coursesLoading = false;

  /// 장소를 못 받은 이유. `null` 이면 못 받은 것이 아니라 **없는 것**이다(#515).
  PlaceFailure? _placesFailure;

  /// 이웃 코스를 못 받은 이유. 같은 규칙이다.
  CourseFailure? _coursesFailure;

  int _loadSeq = 0;

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    // 칩 키를 조회에 붙인다 — 받아 놓은 80곳 안에서 거르면 병원은 매장 뒤에 묻힌다(#291 실측).
    List<PetPlace> places;
    try {
      places = await _repo.fetchNearby(
        lat: _center.latitude,
        lng: _center.longitude,
        contentTypeId: _catFilter,
      );
    } on PlaceFailure catch (failure) {
      // 못 받은 것을 "없다" 고 말하지 않는다(#515). 예전에는 저장소가 실패를 빈 목록으로
      // 돌려줘서, 서버가 죽은 날 지도가 "이 지역엔 등록된 곳이 없어요" 를 그렸다.
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _placesFailure = failure;
        _places = const [];
        _loading = false;
      });
      return;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _places = places;
      _placesFailure = null;
      _loading = false;
    });
    await _refreshMarkers();
    if (_catFilter == 'trail') await _fitToPlaces();
  }

  /// 공개 코스 한 벌을 받아 **기기에서** 가까운 20개를 고른다 (#339).
  ///
  /// 서버에 좌표를 안 보낸다 — 장소 카탈로그(#273)와 같은 방식이다. 못 받으면 빈 목록이고,
  /// 화면은 "아직 없어요" 를 말한다: 가짜를 놓지 않는다.
  Future<void> _loadCourses() async {
    setState(() => _coursesLoading = true);
    List<Course> all;
    try {
      all = await _courses.publicCourses();
    } on CourseFailure catch (failure) {
      // "아직 이웃이 올린 코스가 없어요" 는 못 받았을 때 하는 거짓말이다(#515).
      if (!mounted) return;
      setState(() {
        _coursesFailure = failure;
        _nearbyCourses = const [];
        _coursesLoading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _coursesFailure = null;
      _nearbyCourses = nearestByStart<Course>(
        all,
        _center.latitude,
        _center.longitude,
        startOf: (course) => course.start,
      );
      _coursesLoading = false;
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<PetPlace> get _filtered {
    // 검색 중에는 **칩을 안 본다** (#620). 켜 둔 칩이 결과를 조용히 지우면 사용자는
    // "그 이름이 없다" 고 읽는다 — 실제로는 칩이 가린 것이다. 대신 칩 줄을 검색어
    // 하나로 바꿔서 지금 무엇을 보고 있는지 화면이 말한다.
    if (_isSearching) return _hits;

    final byCat = _catFilter == null
        ? _places
        : _places.where((p) => p.categoryKey == _catFilter).toList();
    // 24시는 병원 칩 안에서만 켤 수 있다 — 이름 기준이라 다른 카테고리에 쓰면 뜻이 없다(#337).
    if (!_only24h) return byCat;
    return byCat.where((p) => isTwentyFourHourByName(p.title)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: view == 'list' ? _listView() : _mapView(),
        ),
      ),
    );
  }

  // ───────────── 이웃 코스 (#339) ─────────────

  Widget _courseCard(Course course) => GestureDetector(
        onTap: () => _showCourseSheet(course),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: T.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            SizedBox(
              width: 78,
              height: 56,
              child: course.path.length >= 2
                  ? CustomPaint(
                      painter: RouteCanvasPainter(
                        RouteArt(lngLat: course.path, distanceLabel: '', timeLabel: '', dateLabel: ''),
                        withCaption: false,
                      ),
                    )
                  : const Icon(Icons.route_rounded, size: 22, color: T.textFaint),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 4),
                Text('${course.km.toStringAsFixed(2)}km${course.mine ? ' · 내 코스' : ''}',
                    style: const TextStyle(fontSize: 12, color: T.textMuted)),
                if (course.note != null && course.note!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(course.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: T.textSecondary)),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: T.textFaint),
          ]),
        ),
      );

  /// 코스 하나 — 온전한 선은 **여기서** 받는다(목록에는 시작점만 온다).
  Future<void> _showCourseSheet(Course summary) async {
    Course course = summary;
    try {
      course = await _courses.one(summary.id);
    } catch (_) {
      // 못 받아도 시트는 연다 — 이름과 거리는 목록에 이미 있다.
    }
    if (!mounted) return;
    if (view == 'map' && course.path.length >= 2) unawaited(_drawCourse(course));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(course.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(sheetCtx),
              child: const Icon(Icons.close, size: 22, color: T.textFaint),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${course.km.toStringAsFixed(2)}km · 시작·끝 100m 는 빠져 있어요',
              style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
          if (course.note != null && course.note!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(course.note!, style: const TextStyle(fontSize: 13.5, color: T.textSecondary)),
          ],
          if (course.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (final tag in course.tags) _courseTag(tag),
            ]),
          ],
          if (course.path.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: CustomPaint(
                painter: RouteCanvasPainter(
                  RouteArt(lngLat: course.path, distanceLabel: '', timeLabel: '', dateLabel: ''),
                  withCaption: false,
                ),
                size: Size.infinite,
              ),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () async {
              Navigator.pop(sheetCtx);
              await startWalk(context, courseLine: course.path);
            },
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [T.warmStart, T.warmEnd],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('이 코스 다시 걷기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _courseTag(String tag) {
    const labels = {'leash': '목줄 규정', 'poopbag': '배변봉투통', 'shade': '그늘·물'};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: const Color(0x140B7A75), borderRadius: BorderRadius.circular(9)),
      child: Text(labels[tag] ?? tag,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0B7A75))),
    );
  }

  /// 지도에 코스 선을 얹는다. 공공데이터 산책로와 색이 다르다 — 다른 종류의 것이다.
  Future<void> _drawCourse(Course course) async {
    final c = _mapCtrl;
    if (c == null || course.path.length < 2) return;
    final coords = [for (final p in course.path) NLatLng(p[1], p[0])];
    await c.addOverlay(NPolylineOverlay(
      id: 'course-${course.id}',
      coords: coords,
      color: const Color(0xFF0B7A75),
      width: 6,
    ));
    double minLat = coords.first.latitude, maxLat = minLat;
    double minLng = coords.first.longitude, maxLng = minLng;
    for (final q in coords) {
      if (q.latitude < minLat) minLat = q.latitude;
      if (q.latitude > maxLat) maxLat = q.latitude;
      if (q.longitude < minLng) minLng = q.longitude;
      if (q.longitude > maxLng) maxLng = q.longitude;
    }
    await c.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds(southWest: NLatLng(minLat, minLng), northEast: NLatLng(maxLat, maxLng)),
      padding: const EdgeInsets.all(60),
    ));
  }

  // ───────────── 리스트 ─────────────
  Widget _listView() {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 100),
      children: [
        Row(children: const [
          // '지도' 였다 — 지도는 보여 주는 방식 중 하나지 이 탭의 일이 아니다(2026-09-21 사장님).
          Text('탐색', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          ProfileAvatar(),
        ]),
        const SizedBox(height: 4),
        const Text('우리 아이랑 갈 수 있는 곳', style: TextStyle(fontSize: 13, color: T.textSecondary)),
        const SizedBox(height: 12),
        _searchRow(),
        const SizedBox(height: 10),
        // 검색 중에는 칩 대신 검색어 하나. 두 개를 같이 두면 켜 둔 칩이 결과를 조용히
        // 지우고, 사용자는 "그 이름이 없다" 고 읽는다.
        _isSearching ? _searchChip() : _catChips(),
        const SizedBox(height: 14),
        if (_neighbourCourses) ...[
          if (_coursesLoading)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF0B7A75))))
          else if (_coursesFailure != null)
            Padding(
              key: const Key('explore-courses-failed'),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Text(
                    switch (_coursesFailure!.kind) {
                      CourseFailureKind.network => '이웃 코스를 못 받았어요 · 연결을 확인해 주세요',
                      _ => '이웃 코스를 못 받았어요 · 잠시 뒤 다시 시도해 주세요',
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: T.textMuted)),
                TextButton(onPressed: _loadCourses, child: const Text('다시 시도')),
              ]),
            )
          else if (_nearbyCourses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text('아직 이웃이 올린 코스가 없어요 · 산책 회고에서 코스를 만들어 공개하면 여기 쌓여요',
                  style: TextStyle(fontSize: 13, color: T.textMuted)),
            )
          else ...[
            Row(children: [
              const Icon(Icons.people_alt_rounded, size: 15, color: Color(0xFF0B7A75)),
              const SizedBox(width: 5),
              Text('이웃 코스 · ${_nearbyCourses.length}개',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0B7A75))),
              const Spacer(),
              const Text('사람들이 올린 길 · 시작·끝은 빠져 있어요',
                  style: TextStyle(fontSize: 10.5, color: T.textMuted)),
            ]),
            const SizedBox(height: 10),
            for (final course in _nearbyCourses) ...[
              _courseCard(course),
              const SizedBox(height: 12),
            ],
          ],
        ] else if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: T.warmMid)))
        else if (_filtered.isEmpty)
          _emptyBox()
        else ...[
          Row(children: [
            const Icon(Icons.pets, size: 15, color: T.warmMid),
            const SizedBox(width: 5),
            Text('${_headerLabel()} · ${_filtered.length}곳',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
            const SizedBox(width: 8),
            // 출처 한 마디가 먼저 접힌다 — 큰 글자(1.6배)에서 이 줄이 190px 넘쳤다(#449 테스트).
            // 개수는 짧고 자주 읽는 값이라 그대로 둔다.
            Expanded(
              child: Text(_sourceCaption(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 10.5, color: T.textMuted)),
            ),
          ]),
          if (_fallbackCenter) ...[
            const SizedBox(height: 6),
            Text(
              // 동네를 골랐으면 그 이름을 말한다 (#342) — "서울시청 기준" 은 고른 사람에게
              // 틀린 말이고, 그 문구를 보고 위치 권한을 켜러 갈 이유도 없다.
              _myNeighborhood != null
                  ? '현재 위치를 못 받아 ${_myNeighborhood!.dong} 기준이에요 · 위치를 켜면 내 주변'
                  : AuthState.isGuest
                      ? '현재 위치를 못 받아 서울시청 기준이에요 · 로그인하고 위치를 켜면 내 주변'
                      : '현재 위치를 못 받아 서울시청 기준이에요 · 위치 권한을 켜면 내 주변',
              style: const TextStyle(fontSize: 11, color: T.textMuted),
            ),
          ],
          if (_farNotice != null) ...[
            const SizedBox(height: 6),
            Text(_farNotice!,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: T.warmText)),
          ],
          const SizedBox(height: 10),
          for (int i = 0; i < _filtered.length; i++) ...[
            _placeCard(_filtered[i]),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }


  /// 한 벌을 **아예 못 받은** 상태인가 — "이 지역에 없음" 과 다르다 (이슈 #275).
  ///
  /// 이것은 A안(기기 안 카탈로그)의 실패다. 서버 조회(B안)의 실패는 [_placesFailure] 가
  /// 따로 든다 — 예전에는 그쪽이 실패를 빈 목록으로 돌려줘서 구분 자체가 없었고,
  /// 그래서 서버가 죽은 날 "이 지역엔 등록된 곳이 없어요" 가 떴다(#515).
  bool get _catalogUnavailable =>
      !LocationUploadPolicy.canQueryNearbyPlaces && !PlaceCatalogRepository.instance.hasCatalog;

  Future<void> _retryCatalog() async {
    // 누르는 즉시 스피너로 바꾼다. 안 그러면 `retry()` 가 타임아웃(30초)까지 기다리는
    // 동안 빈 카드와 살아 있는 버튼이 그대로라 사람이 여러 번 누른다 — 요청은
    // `_inFlight` 로 합쳐지지만 끝난 뒤 `_load()` 가 누른 수만큼 돈다. #283 검토.
    if (_loading) return;
    setState(() => _loading = true);
    await PlaceCatalogRepository.instance.retry();
    if (mounted) await _load();
  }

  Widget _emptyBox() {
    // 찾는 중이면 "없다" 가 아직 아니다 (#620).
    if (_isSearching) {
      return GlassCard(
        key: const Key('explore-search-empty'),
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
        child: Column(children: [
          Icon(_searching ? Icons.hourglass_empty_rounded : Icons.search_off_rounded,
              size: 36, color: T.textMuted),
          const SizedBox(height: 10),
          Text(_searching ? '찾는 중이에요' : '"${_query.trim()}" 은 아직 없어요',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
          if (!_searching) ...[
            const SizedBox(height: 4),
            // 왜 없는지를 말한다. "다시 시도" 를 권하면 몇 번을 눌러도 같은 답이 온다 —
            // 이 목록은 반려동반이 확인된 곳만 모은 것이라 그 밖은 원래 없다.
            const Text('반려동반이 되는 곳만 모아 둔 목록이라 없을 수 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          ],
        ]),
      );
    }

    // 못 받은 것을 "없다" 고 말하면 안 된다. "지도를 움직여 보세요" 는 그 사람이 시킨
    // 대로 해도 소용이 없는 안내고, 5분 백오프 때문에 움직여도 다시 안 받는다.
    final failure = _placesFailure;
    if (failure != null) {
      return GlassCard(
        key: const Key('explore-places-failed'),
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
        child: Column(children: [
          const Icon(Icons.cloud_off_outlined, size: 36, color: T.textMuted),
          const SizedBox(height: 10),
          const Text('장소 목록을 못 받았어요',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 4),
          Text(failure.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ]),
      );
    }
    if (_catalogUnavailable) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
        child: Column(children: [
          const Icon(Icons.cloud_off_outlined, size: 36, color: T.textMuted),
          const SizedBox(height: 10),
          const Text('장소 목록을 아직 못 받았어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 4),
          const Text('네트워크를 확인하고 다시 시도해 주세요', style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          const SizedBox(height: 12),
          TextButton(onPressed: _retryCatalog, child: const Text('다시 시도')),
        ]),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      child: Column(children: [
        Image.asset('assets/emoji/paw.png', width: 40, height: 40),
        const SizedBox(height: 10),
        const Text('이 지역엔 등록된 곳이 없어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
        const SizedBox(height: 4),
        // "지도를 움직여 보세요" 라고 하지 않는다 — 지도를 움직여도 다시 읽지 않는다
        // (`_load` 는 `_boot` 에서 한 번만 불린다). 시킨 대로 해도 소용없는 안내는 거짓이다.
        Text(
          switch (_catFilter) {
            // 놀이터는 지자체가 올린 파일을 모은 것이라 아직 지역이 성기다(#346).
            // "필터를 바꿔보세요" 는 여기서 거짓이다 — 필터를 바꿔도 놀이터는 안 는다.
            'playground' => '아직 자료를 올린 지자체가 적어요 · 다른 칩을 둘러보세요',
            // #401 부터 산책로도 8km 를 먼저 본다. 반경 안이 비면 넓혀서 보여 주므로,
            // 여기까지 왔다면 카탈로그에 코스가 아예 없는 것이다.
            'trail' => '가까운 코스를 못 찾았어요 · 잠시 뒤 다시 열어 보세요',
            _ => '현위치 8km 안을 봤어요 · 필터를 바꿔보세요',
          },
          style: const TextStyle(fontSize: 12.5, color: T.textMuted),
        ),
      ]),
    );
  }

  /// 목록 머리 라벨 — 산책로를 "반려동반 가능" 이라고 부르지 않는다(#328).
  String _headerLabel() => _isSearching
      ? '"${_query.trim()}" 검색'
      : switch (_catFilter) {
        'trail' => '가까운 산책로',
        'vet' => '동물병원',
        'shop' => '펫샵',
        'playground' => '반려견 놀이터',
        _ => '반려동반 가능',
      };

  /// 산책로 칩인데 가장 가까운 코스가 8km 밖이면 그 말을 한다 — 빈 지도·먼 목록의 이유(#328).
  /// 목록은 거리순이라 첫 항목이 가장 가깝다(#321).
  String? get _farNotice {
    if (_catFilter != 'trail' || _filtered.isEmpty) return null;
    final nearest = _filtered.first;
    if (nearest.distM <= 8000) return null;
    return '가장 가까운 코스는 ${nearest.distLabel} 밖이에요';
  }

  /// 산책로 칩: 카메라를 가까운 코스들에 맞춘다 — 코스가 화면 밖이면 지도가 비어 보였다(#328).
  Future<void> _fitToPlaces() async {
    final c = _mapCtrl;
    // 20개를 다 담으면 파주부터 수원까지 한 화면이다. 가까운 다섯이면 "어디쯤인지" 는 보인다.
    final places = _filtered.take(5).toList();
    if (c == null || !mounted || places.isEmpty) return;
    double minLat = places.first.lat, maxLat = minLat, minLng = places.first.lng, maxLng = minLng;
    for (final p in places) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    if (!_camera.mayAutoMove) return; // 사용자가 쥔 카메라는 안 뺏는다(#769).
    if (minLat == maxLat && minLng == maxLng) {
      await c.updateCamera(NCameraUpdate.withParams(target: NLatLng(minLat, minLng), zoom: 12));
      return;
    }
    await c.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds(southWest: NLatLng(minLat, minLng), northEast: NLatLng(maxLat, maxLng)),
      padding: const EdgeInsets.all(80),
    ));
  }

  /// 겹친 핀을 숫자 하나로 접는다 — 성수동 쇼핑 핀 수십 개가 한 덩어리였다(#328).
  void _clusterMarker(NClusterInfo info, NClusterMarker marker) {
    final icon = _clusterIcon;
    if (icon != null) marker.setIcon(icon);
    marker.setSize(const Size(44, 44));
    // **개수를 적는다.** 패키지 기본 빌더는 이걸 하는데(`defaultClusterMarkerBuilder`),
    // 우리가 아이콘을 쓰려고 빌더를 덮으면서 같이 잃었다. 그래서 80곳이 한 점으로 뭉쳐도
    // 숫자가 없어 "장소가 하나뿐" 으로 보였다 — 2026-09-17 신고.
    marker.setCaption(ExploreMap.clusterCaption(info.size));
    // 글자를 원 **안**에 놓는다. 기본은 핀 아래라 원과 따로 떠 보인다.
    marker.setCaptionAligns(const [NAlign.center]);
    // 숫자는 흰 글자 + 보라 후광 — 기본 핀 위에 흰 글자만 얹으면 안 보였다(에뮬레이터 확인).
    marker.setCaption(NOverlayCaption(
      text: '${info.size}',
      color: Colors.white,
      haloColor: T.accent,
      textSize: 13,
    ));
  }

  /// 클러스터 핀 그림 하나 — 보라 원에 흰 테두리. 숫자는 캡션이 얹는다.
  Future<void> _prepareClusterIcon() async {
    if (_clusterIcon != null || !mounted) return;
    _clusterIcon = await NOverlayImage.fromWidget(
      context: context,
      size: const Size(44, 44),
      widget: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: T.accent,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
      ),
    );
  }

  /// 목록 머리의 출처 한 마디 — 칩에 따라 다르다 (#291).
  String _sourceCaption() => switch (_catFilter) {
        'vet' || 'shop' => '행정안전부 인허가 · 전국',
        'trail' => '지자체 걷는 길 · 두루누비',
        // 전국 표준데이터가 없어 지자체 파일을 모은 것이다(#346) — 아직 지역이 성기다.
        'playground' => '지자체 현황 · 모으는 중',
        null => '관광공사 · 인허가 · 걷는 길',
        _ => '관광공사',
      };

  Widget _imgFallback(PetCategory cat) => Container(
        width: 64, height: 64, alignment: Alignment.center,
        decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.14)),
        child: Icon(cat.icon, size: 26, color: cat.color),
      );

  /// 장소 카드 (#449). 관광공사 사진이 있는 곳은 **사진이 먼저, 카드 폭**이다 — 지도 탭도
  /// 사진 앱이다. AllTrails 의 코스 카드(사진 → 이름 → 거리)와 같은 순서. 사진이 없는
  /// 공공데이터 층(병원·펫샵·산책로·놀이터)은 카테고리 아이콘의 한 줄 카드 그대로다 —
  /// 사진 없이 카드만 키우면 밀도만 잃는다.
  Widget _placeCard(PetPlace p) {
    final cat = p.petCategory;
    if (p.image.isNotEmpty) return _photoCard(p, cat);
    return GestureDetector(
      key: Key('place-card-${p.contentId}'),
      onTap: () => _showPlaceSheet(p),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ClipRRect(
            key: Key('place-thumb-${p.contentId}'),
            borderRadius: BorderRadius.circular(14),
            child: _imgFallback(cat),
          ),
          const SizedBox(width: 12),
          Expanded(child: _placeText(p, cat)),
          const Icon(Icons.chevron_right, size: 20, color: T.textFaint),
        ]),
      ),
    );
  }

  /// 사진 카드 — 사진(16:9, 카드 폭) 아래 이름·태그·거리·주소. 세로 사진도 16:9 로 자른다 —
  /// 관광공사 사진은 거의 가로이고, 목록에서는 한 화면에 두어 곳은 보여야 한다(#465 의 밀도).
  Widget _photoCard(PetPlace p, PetCategory cat) => GestureDetector(
        key: Key('place-card-${p.contentId}'),
        onTap: () => _showPlaceSheet(p),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              key: Key('place-photo-${p.contentId}'),
              aspectRatio: 16 / 9,
              child: Image.network(p.image,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => placePhotoFallback(cat, p.contentId)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 13),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _placeText(p, cat)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 20, color: T.textFaint),
              ]),
            ),
          ]),
        ),
      );

  /// 이름 · 태그와 거리 · 요약 · 주소 — 사진 카드와 한 줄 카드가 같은 글 묶음을 쓴다.
  Widget _placeText(PetPlace p, PetCategory cat) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 6),
        Row(children: [
          // 배지가 먼저 줄어든다 — 거리는 짧고, 카드에서 가장 자주 읽는 값이다.
          // 좁은 폭에서 배지가 안 줄어들어 줄이 통째로 넘쳤다(393dp 에서 8.5px).
          Flexible(child: placeCategoryTag(cat)),
          if (p.distLabel.isNotEmpty) ...[
            const SizedBox(width: 7),
            const Icon(Icons.near_me, size: 12, color: T.textMuted),
            const SizedBox(width: 2),
            Text(p.distLabel, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
          ],
        ]),
        if (p.summary.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: T.textSecondary)),
        ],
        if (p.addr.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(p.addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: T.textMuted)),
        ],
      ]);


  /// 칩 줄에서 먼저 보이는 다섯 — 자주 쓰는 것(#449). 나머지는 "더보기" 뒤다.
  ///
  /// Google 지도의 카테고리 줄이 같은 꼴이다(자주 쓰는 몇 개 + More). 순서는 여기서만 정한다 —
  /// `kPetCategories` 는 색 · 아이콘 · 범례의 SSOT 이고 순서까지 맡기면 범례도 따라 바뀐다.
  static const List<String> _primaryChipKeys = ['trail', 'vet', '39', '12', 'playground'];

  /// "더보기" 를 눌러 나머지 칩을 펼쳤나. 나머지 중 하나가 켜져 있는 동안은 "접기" 를 안 보인다 —
  /// 켜진 칩이 사라지면 무엇을 골랐는지 볼 수 없다. (나머지는 펼친 뒤에만 고를 수 있으니
  /// 켜져 있으면 이 값은 이미 true 다.)
  bool _moreChips = false;

  // 카테고리 필터 칩 (가로 스크롤).
  /// 검색 중일 때 칩 줄 자리에 서는 것 — 지금 무엇을 보고 있는지 한 칸으로 말한다.
  Widget _searchChip() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        key: const Key('explore-search-chip'),
        onTap: _clearSearch,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: T.accentSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: T.accentLine),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search, size: 14, color: T.accent),
            const SizedBox(width: 6),
            // 검색어가 길면 칩이 화면을 넘는다 — 칩 안에서 자른다.
            Flexible(
              child: Text(_query.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.accent)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.close_rounded, size: 14, color: T.accent),
          ]),
        ),
      ),
    );
  }

  Widget _catChips() {
    Widget chip(String label, String? key, Color color) {
      final on = _catFilter == key;
      return GestureDetector(
        key: Key('chip-${key ?? 'all'}'),
        onTap: () {
          if (_catFilter == key) return;
          // 갈래를 바꾸는 것은 "그쪽을 보여 달라" 는 부탁이다 — 다시 앱 차례다(#769).
          _camera.appWasAsked();
          setState(() {
            _catFilter = key;
            _only24h = false;
            _neighbourCourses = false;
          });
          _load(); // 끝나면 마커도 다시 그린다.
        },
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: on ? color : T.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Colors.transparent : T.line),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
        ),
      );
    }

    // 펼치기 · 접기 칩 — 카테고리 칩과 같은 꼴에 화살표 하나. 누르는 것은 조회가 아니라 줄이다.
    Widget toggle(String label, IconData icon, Key key, VoidCallback onTap) => GestureDetector(
          key: key,
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: T.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
              const SizedBox(width: 2),
              Icon(icon, size: 16, color: T.textMuted),
            ]),
          ),
        );

    final primary = [
      for (final key in _primaryChipKeys) kPetCategories.firstWhere((c) => c.key == key),
    ];
    final secondary = kPetCategories.where((c) => !_primaryChipKeys.contains(c.key)).toList();
    final secondarySelected = secondary.any((c) => c.key == _catFilter);
    final expanded = _moreChips;

    return SizedBox(
      key: const Key('chip-row'),
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        chip('전체', null, T.warmMid),
        for (final c in primary) chip(c.label, c.key, c.color),
        if (!expanded)
          toggle('더보기', Icons.expand_more_rounded, const Key('chip-more'),
              () => setState(() => _moreChips = true)),
        if (expanded) ...[
          for (final c in secondary) chip(c.label, c.key, c.color),
          if (!secondarySelected)
            toggle('접기', Icons.expand_less_rounded, const Key('chip-less'),
                () => setState(() => _moreChips = false)),
        ],
        // 병원을 고른 뒤에만 나온다. 이름에 24시가 있는 곳만 남긴다(#337).
        if (_catFilter == 'vet') _only24hChip(),
        // 산책로를 고른 뒤에만 나온다. 공공데이터 대신 사람들이 올린 코스를 본다(#339).
        if (_catFilter == 'trail' && LocationUploadPolicy.sharesRoutes) _neighbourChip(),
      ]),
    );
  }

  /// "이웃 코스" 토글 칩. 켜면 공개 코스를 받아 기기에서 가까운 20개를 고른다.
  Widget _neighbourChip() {
    const teal = Color(0xFF0B7A75);
    return GestureDetector(
      onTap: () {
        final next = !_neighbourCourses;
        setState(() => _neighbourCourses = next);
        if (next && _nearbyCourses.isEmpty) _loadCourses();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _neighbourCourses ? teal : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _neighbourCourses ? Colors.transparent : const Color(0x330B7A75)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_alt_rounded, size: 13, color: _neighbourCourses ? Colors.white : teal),
          const SizedBox(width: 5),
          Text('이웃 코스',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _neighbourCourses ? Colors.white : teal)),
        ]),
      ),
    );
  }

  /// "24시" 토글 칩. 조회를 다시 하지 않는다 — 받아 둔 병원 목록에서 이름으로 거른다.
  Widget _only24hChip() {
    const red = Color(0xFFD7263D);
    return GestureDetector(
      onTap: () => setState(() => _only24h = !_only24h),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _only24h ? red : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _only24h ? Colors.transparent : const Color(0x33D7263D)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.nightlight_round, size: 13, color: _only24h ? Colors.white : red),
          const SizedBox(width: 5),
          Text('24시',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _only24h ? Colors.white : red)),
        ]),
      ),
    );
  }

  /// 이름으로 찾는다 — **기기 안에서** (#620).
  ///
  /// 여기 있던 것은 `Container` 안의 `Text` 였다. 검색창처럼 생겼지만 `TextField` 도
  /// `onTap` 도 없어서 눌러도 키보드가 안 올라왔다 — 2026-09-17 에 사장님이
  /// "아예 무용지물" 이라고 신고했다.
  Widget _searchRow() {
    return Row(children: [
      Expanded(
        child: Container(
          height: 46,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _searchFocus.hasFocus ? T.accent : T.cardBorder),
          ),
          child: Row(children: [
            const Icon(Icons.search, size: 20, color: T.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('explore-search-field'),
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                // 엔터는 기다리지 않고 바로 찾는다 — 입력 중에도 이미 찾고 있다.
                onSubmitted: (_) => _runSearch(_searchCtrl.text, now: true),
                style: const TextStyle(fontSize: 14, color: T.textPrimary),
                cursorColor: T.accent,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  // 자리표시가 좁은 폭에서 줄을 넘겼다(393dp · 테스트 폰트에서 8.5px).
                  // 자리표시는 잘려도 뜻이 남는다 — 뒤의 "..." 가 이미 말줄임이다.
                  hintText: '카페, 공원, 산책로...',
                  hintMaxLines: 1,
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                ),
              ),
            ),
            if (_isSearching)
              GestureDetector(
                key: const Key('explore-search-clear'),
                onTap: _clearSearch,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Icon(Icons.close_rounded, size: 18, color: T.textMuted),
                ),
              )
            else
              const SizedBox(width: 8),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      _viewToggle(),
    ]);
  }

  /// 손이 멈추면 한 번 찾는다. 글자마다 18,870곳을 훑지 않는다.
  ///
  /// **기다리는 220ms 동안 "찾는 중" 이라고 말한다.** 안 그러면 아직 찾지도 않고
  /// "아직 없어요" 를 먼저 보여 주게 된다 — 글자를 칠 때마다 "없다" 가 깜빡인다.
  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    setState(() {
      _query = text;
      _searching = text.trim().isNotEmpty;
      // 옛 결과를 들고 있으면 새 검색어 밑에 지난 답이 깔린다.
      if (_searching) _hits = const [];
    });
    // 치는 동안 지도에 옛 결과가 남으면 화면이 거짓말을 한다 — 목록과 같은 순간에 비운다.
    if (_searching) unawaited(_refreshMarkers());
    _searchDebounce = Timer(const Duration(milliseconds: 220), () => _runSearch(text));
  }

  Future<void> _runSearch(String text, {bool now = false}) async {
    if (now) _searchDebounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      if (mounted) setState(() { _hits = const []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    final found = await _repo.searchByName(q, limit: _searchLimit);
    // 타이핑이 이어졌으면 지난 답이다 — 늦게 온 것이 새 답을 덮으면 화면이 뒤로 간다.
    if (!mounted || _searchCtrl.text.trim() != q) return;
    setState(() {
      // 거리는 카탈로그에 없다 — 지금 보고 있는 중심에서 재서 붙인다(#539 의 그 자리).
      _hits = [for (final p in found) p.withDistance(haversineMeters(_center.latitude, _center.longitude, p.lat, p.lng))];
      _searching = false;
    });
    // **지도도 같이 바뀌어야 한다.** `_filtered` 는 검색 중이면 `_hits` 를 주는데,
    // 마커를 다시 그리는 곳이 `_load()` 와 `onMapReady` 뿐이었다 — 에뮬레이터에서
    // 검색어를 넣었더니 목록만 비고 마커 80개가 그대로 떠 있었다(2026-09-17).
    await _refreshMarkers();
  }

  /// 한 화면에 보여 줄 검색 결과 수. 목록이 끝없이 길면 고르는 일이 더 어려워진다.
  static const int _searchLimit = 30;

  Future<void> _clearSearch() async {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _hits = const [];
      _searching = false;
    });
    // 지우면 주변 목록이 돌아온다 — 지도도 같이 돌아와야 한다.
    await _refreshMarkers();
  }

  Widget _viewToggle() {
    Widget seg(String v, IconData icon) {
      final on = view == v;
      return GestureDetector(
        onTap: () => setState(() => view = v),
        child: Container(
          width: 42, height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [T.warmStart, T.warmEnd]) : null,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 21, color: on ? Colors.white : T.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: T.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: T.cardBorder),
      ),
      child: Row(children: [seg('list', Icons.view_agenda_outlined), seg('map', Icons.map_outlined)]),
    );
  }

  // ───────────── 지도 ─────────────
  Widget _mapView() {
    return Stack(children: [
      Positioned.fill(child: _mapStack()),
      Positioned(
        top: 6, left: 16, right: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              // 목록 뷰와 **같은 칸**이다 — 같은 컨트롤러·같은 포커스를 쓴다(#620). 뷰를
              // 바꿔도 검색어가 안 사라지고, 결과도 그대로다(`_filtered` 하나를 본다).
              child: Container(
                height: 42, padding: const EdgeInsets.only(left: 14, right: 4),
                decoration: BoxDecoration(
                  color: const Color(0xF2FFFFFF), borderRadius: BorderRadius.circular(13),
                  boxShadow: const [BoxShadow(color: Color(0x1F5A4690), blurRadius: 14, offset: Offset(0, 5))],
                ),
                child: Row(children: [
                  const Icon(Icons.search, size: 18, color: T.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('explore-map-search-field'),
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(_searchCtrl.text, now: true),
                      style: const TextStyle(fontSize: 13.5, color: T.textPrimary),
                      cursorColor: T.accent,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '이 지역에서 찾기...',
                        hintMaxLines: 1,
                        hintStyle: TextStyle(fontSize: 13.5, color: T.textMuted),
                      ),
                    ),
                  ),
                  if (_isSearching)
                    GestureDetector(
                      key: const Key('explore-map-search-clear'),
                      onTap: _clearSearch,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                        child: Icon(Icons.close_rounded, size: 17, color: T.textMuted),
                      ),
                    )
                  else
                    const SizedBox(width: 10),
                ]),
              ),
            ),
            const SizedBox(width: 9),
            _viewToggle(),
            const SizedBox(width: 9),
            const ProfileAvatar(size: 40),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 40, child: _isSearching ? _searchChip() : _catChips()),
        ]),
      ),
      Positioned(left: 16, bottom: 128, child: _legend()),
    ]);
  }

  Widget _mapStack() {
    return Stack(children: [
      Positioned.fill(
        child: !Env.hasNaverMap
            ? const MapUnavailable(
                what: '주변 반려동물 동반 장소를 지도에 보여드리는 화면이에요.')
            : NaverMap(
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(target: _center, zoom: 12),
            locationButtonEnable: true,
            locale: const Locale('ko'),
            scaleBarEnable: false,
            minZoom: 9,
            maxZoom: 18,
          ),
          clusterOptions: NaverMapClusteringOptions(clusterMarkerBuilder: _clusterMarker),
          // 지도를 움직이면 그 지역을 다시 찾을 수 있게 한다 (#628).
          //
          // **자동으로 다시 받지 않는다.** 손이 미끄러진 것과 "여기를 보고 싶다" 를 앱이
          // 못 가른다 — 네이버·카카오 지도가 버튼을 두는 이유다. 대신 버튼이 뜨는 것까지는
          // 자동이라, 움직였는데 아무 말이 없는 일은 없다.
          //
          // 드래그한 중심은 **사용자의 현재 위치가 아니다.** A안(#235)이 막는 것은 기기가
          // 아는 내 위치를 서버로 보내는 것이지, 사용자가 손으로 고른 지점이 아니다.
          onCameraIdle: _onCameraIdle,
          // 카메라가 움직인 이유를 플러그인이 알려 준다 — 손가락(제스처)과 줌 컨트롤만 사용자 것이다(#769).
          onCameraChange: (reason, _) => _camera.moved(
              byUser: reason == NCameraUpdateReason.gesture ||
                  reason == NCameraUpdateReason.control),
          onMapReady: (c) async {
            _mapCtrl = c;
            // 아이콘을 굽는 동안 지도는 **이미 만질 수 있다** — 그 사이 확대했으면 여기서도 안 뺏는다(#769).
            await _prepareClusterIcon();
            await _autoMoveCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
            await _refreshMarkers();
            if (_catFilter == 'trail') await _fitToPlaces();
            final pending = _pendingTrail;
            if (pending != null) {
              _pendingTrail = null;
              await _drawTrail(pending);
            }
          },
        ),
      ),
      // "이 지역에서 다시 찾기" — 지도를 1km 넘게 옮겼을 때만 뜬다 (#628).
      if (_movedTo != null && !_loading)
        Positioned(
          top: 106, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              key: const Key('explore-research-here'),
              onTap: _researchHere,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [T.warmStart, T.warmEnd],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33E04A2B), blurRadius: 14, offset: Offset(0, 5)),
                  ],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded, size: 17, color: Colors.white),
                  SizedBox(width: 7),
                  Text('이 지역에서 다시 찾기',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      if (!_loading && _farNotice != null && _movedTo == null)
        Positioned(
          top: 112, left: 16, right: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: T.cardBg, borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Text(_farNotice!,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.warmText)),
            ),
          ),
        ),
      if (_loading)
        const Positioned(
          top: 112, left: 0, right: 0,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: T.warmMid)),
                  SizedBox(width: 10),
                  Text('주변 장소 불러오는 중...', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  /// 지도가 멈췄다. 멀리 왔으면 그 지역을 다시 거른다.
  ///
  /// <h3>기기 안에서 거르는 빌드는 바로 한다</h3>
  /// 이 빌드는 서버에 좌표를 안 보낸다(#235 · #200). 전국 한 벌을 통째로 받아 두고 거리
  /// 계산을 기기에서 하므로({@code PlaceCatalogRepository}) **다시 거르는 데 네트워크가
  /// 0 이다.** 부를 서버가 없는데 버튼을 눌러 달라고 할 이유가 없다.
  ///
  /// 이 자리를 한 번 버튼으로 뒀다가 바로 고쳤다 — "조회가 폭발한다" 고 썼는데 폭발할
  /// 조회가 애초에 없었다. 사장님이 "어떤 구조로 하고 있길래" 라고 물어 다시 따라가 보고
  /// 알았다(2026-09-17).
  ///
  /// <h3>서버를 부르는 빌드는 버튼으로 둔다</h3>
  /// 신고를 마치고 `UPLOAD_LOCATION` 을 켜면 이 조회가 서버로 간다. 그때는 끄는 동안 계속
  /// 부르게 되므로 버튼이 맞다 — 그 갈래를 `LocationUploadPolicy` 하나로 가른다.
  Future<void> _onCameraIdle() async {
    final c = _mapCtrl;
    if (c == null || !mounted) return;
    final pos = await c.getCameraPosition();
    if (!mounted) return;
    final next = ExploreMap.researchTarget(_center, pos.target);
    if (next != null && ExploreMap.refiltersOnDrag) {
      await _moveTo(next);
      return;
    }
    // 같은 답이면 다시 그리지 않는다 — 끄는 동안 이 콜백이 여러 번 온다.
    if ((next == null) == (_movedTo == null) &&
        (next == null || haversineMeters(next.latitude, next.longitude,
                _movedTo!.latitude, _movedTo!.longitude) < 50)) {
      return;
    }
    setState(() => _movedTo = next);
  }

  /// 지금 보고 있는 곳으로 다시 받는다 — 버튼을 눌렀을 때.
  Future<void> _researchHere() async {
    final target = _movedTo;
    if (target == null) return;
    _camera.appWasAsked(); // 사용자가 "여기를 보여 달라" 고 눌렀다(#769).
    await _moveTo(target);
  }

  /// 기준점을 옮기고 다시 거른다. 자동(`_onCameraIdle`)과 버튼이 **같은 길**을 쓴다.
  Future<void> _moveTo(NLatLng target) async {
    setState(() {
      _center = target;
      _movedTo = null;
      // 여기는 내가 고른 동네도, 현위치도 아니다 — "서울시청 기준" 안내를 지운다.
      _fallbackCenter = false;
    });
    await _load();
  }

  /// 한 번에 하나만 다시 그린다 — #758. `onMapReady` 와 카메라 이동 뒤의 `_load` 가 겹치면
  /// 한쪽의 `clearOverlays` 가 다른 쪽이 넣는 중인 마커를 지워 플러그인이 "overlay can't
  /// found" 를 내고, 그 상태에서 네이버 지도 클러스터러가 AssertionError 로 앱을 죽였다
  /// (에뮬레이터 실측, 2026-09-21). 겹친 부름은 끝난 뒤 한 번 더 돈다.
  final SerialRefresh _markerRefresh = SerialRefresh();

  Future<void> _refreshMarkers() => _markerRefresh.run(_refreshMarkersNow);

  Future<void> _refreshMarkersNow() async {
    final c = _mapCtrl;
    if (c == null || !mounted) return;
    await c.clearOverlays();
    final markers = <NAddableOverlay>{};
    for (final p in _filtered) {
      final icon = await _markerIcon(p.petCategory);
      // 겹치면 숫자로 접힌다 — `NaverMap.clusterOptions` 와 짝(#328).
      final m = NClusterableMarker(id: p.contentId.isEmpty ? p.title : p.contentId, position: NLatLng(p.lat, p.lng), icon: icon);
      m.setOnTapListener((_) => _showPlaceSheet(p));
      markers.add(m);
    }
    // 아이콘을 굽는 사이 지도가 바뀌었으면(탭 이동·재생성) 옛 컨트롤러에 넣지 않는다.
    if (!mounted || _mapCtrl != c) return;
    if (markers.isNotEmpty) await c.addOverlayAll(markers);
    // 필터를 바꿔도 카메라는 안 옮긴다 — 사용자가 보고 있는 곳이 기준이다. 산책로만 예외다
    // (`_fitToPlaces`, #328): 가장 가까운 코스가 화면 밖이라 빈 지도가 됐었다.
  }

  /// 카테고리색 핀 — **카테고리마다 한 번만** 굽는다(#533). 장소마다 구우면 80곳에서
  /// 31초가 든다(재 본 값: 전체 31730ms 중 아이콘 31471ms). 종류는 아홉(+기타)뿐이다.
  late final MarkerIcons<NOverlayImage> _icons = MarkerIcons(_drawMarkerIcon);

  Future<NOverlayImage> _markerIcon(PetCategory cat) => _icons.of(cat);

  /// 실제로 굽는 일(플랫폼 통일 — Flutter 위젯 렌더). 이 자리는 캐시를 모른다.
  Future<NOverlayImage> _drawMarkerIcon(PetCategory cat) async {
    return NOverlayImage.fromWidget(
      context: context,
      size: const Size(50, 50),
      widget: SizedBox(
        width: 50, height: 50,
        child: Center(
          child: Container(
            width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: cat.color,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: cat.color.withValues(alpha: 0.5), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: Icon(cat.icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// 이 장소를 물고 커뮤니티 글쓰기로 간다 — 이슈 #172.
  ///
  /// **장소 단위 UGC 가 차별화 논리다**(`market-competition.md:87`). 나중에 붙이면 이미
  /// 쌓인 글에는 영영 장소가 없다. 그래서 처음부터 `contentId` 를 싣는다.
  ///
  /// `contentId` 가 비어 있으면 안 싣는다 — 서버가 모르는 장소를 글에 묶으면 아무
  /// 장소와도 안 이어지는 글이 남는다. 그때는 이름(`loc`)만 들고 간다.
  ///
  /// 시트를 먼저 닫는다. 그리고 `sheetCtx` 가 아니라 화면의 `context` 로 민다 —
  /// 닫힌 시트의 컨텍스트는 죽어 있다.
  Widget _writeAboutPlace(BuildContext sheetCtx, PetPlace p) {
    final linkable = p.contentId.isNotEmpty;
    return GestureDetector(
      onTap: () {
        Navigator.pop(sheetCtx);
        writePost(
          context,
          initialBoard: CommunityBoard.petPlace,
          loc: p.title,
          contentId: linkable ? p.contentId : null,
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        // 두 번째 동작이다 — 주 동작(전화·길찾기·지도에서 보기)은 `_sheetActions` 에 있다(#328).
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_outlined, size: 16, color: T.textSecondary),
          SizedBox(width: 7),
          Text('이 장소로 글쓰기',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textSecondary)),
        ]),
      ),
    );
  }

  /// 산책로가 **거쳐 가는 곳** — 이슈 #619.
  ///
  /// 선이 있으면 아무것도 안 그린다. 지도에 그려진 길이 이미 어디로 가는지 말하고, 그 아래
  /// 같은 말을 이름으로 또 적으면 시트만 길어진다.
  ///
  /// <h3>한 줄로 흘리지 않는다</h3>
  /// 예전에 카드 요약에 `보신각 → 보성사 터 →…` 꼴로 넣었다가 화면이 말줄임으로 잘라
  /// **"화살표가 이어지다 끊긴 문장"** 이 됐다(사장님 신고로 뺐다). 여기서는 조각마다 한
  /// 칸씩 준다 — 이름이 길면 그 칸만 줄바꿈되고, 뜻이 깨지지 않는다.
  ///
  /// <h3>왜 "시작 지점만" 을 굳이 적나</h3>
  /// 카드가 `4.2km · 약 1시간 30분` 이라고 말해 놓고 지도에 점 하나만 찍으면, 사용자는
  /// 앱이 고장 난 줄 안다. 선이 없다는 것은 **숨길 일이 아니라 말할 일**이다.
  /// 선이 없는 산책로일 때만 그린다. 아직 받는 중이거나 못 받았으면 빈 자리다 — 시트가
  /// 열리면서 칸이 늘었다 줄었다 하면 누르던 손이 미끄러진다.
  Widget _whenLineless(Future<TrailRoute?> pending, Widget Function(TrailRoute) build) {
    return FutureBuilder<TrailRoute?>(
      future: pending,
      builder: (context, snap) {
        final route = snap.data;
        if (route == null || route.hasLine || route.waypoints.isEmpty) {
          return const SizedBox.shrink();
        }
        return build(route);
      },
    );
  }

  /// 선이 없다는 한 줄 — 요약 바로 밑이다.
  ///
  /// <b>이 줄은 위에 있어야 합니다.</b> 카드가 `4.2km · 약 1시간 30분` 이라고 말해 놓고
  /// 지도에 점 하나만 찍으면 사용자는 고장 난 줄 안다. 그 오해는 요약을 읽는 순간 생기므로
  /// 답도 거기 있어야 한다.
  Widget _trailNoLineNote(Future<TrailRoute?> pending) {
    return _whenLineless(pending, (route) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: T.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text('지도에는 시작 지점만 표시돼요 — 이 길은 공개된 경로 정보가 이름뿐이에요',
                key: const Key('trail-no-line-note'),
                style: const TextStyle(fontSize: 12, height: 1.45, color: T.textMuted)),
          ),
        ]),
      );
    });
  }

  /// 거쳐 가는 곳 목록 — <b>버튼들 아래</b>다.
  ///
  /// 처음에는 요약 바로 밑에 뒀는데, 경유지가 열한 곳인 코스에서 <b>주 동작 버튼이 화면
  /// 밖으로 밀렸다</b>(2026-09-17 실기기). 시트는 스크롤되니 "없는" 것은 아니지만, 찾아서
  /// 내려야 보이는 버튼은 없는 것과 비슷하다 — 사장님이 "지도로 넘어갈 수가 없다" 고 했다.
  ///
  /// 그래서 <b>누를 것을 먼저, 읽을 것을 나중에</b> 둔다. 조각 수가 코스마다 1~51 로 크게
  /// 달라서, 이 목록 위에 무엇을 두든 그만큼 밀린다.
  ///
  /// <h3>한 줄로 흘리지 않는다</h3>
  /// 예전에 카드 요약에 `보신각 → 보성사 터 →…` 꼴로 넣었다가 화면이 말줄임으로 잘라
  /// <b>"화살표가 이어지다 끊긴 문장"</b> 이 됐다(사장님 신고로 뺐다). 조각마다 한 칸씩
  /// 주면 이름이 길어도 그 칸만 줄바꿈되고 뜻이 안 깨진다.
  Widget _trailStops(Future<TrailRoute?> pending, PetCategory cat) {
    return _whenLineless(pending, (route) {
      {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 18),
          Text('거쳐 가는 곳 ${route.waypoints.length}곳',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 9),
          Wrap(
            key: const Key('trail-waypoints'),
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var i = 0; i < route.waypoints.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: T.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: T.cardBorder),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, color: cat.color)),
                    const SizedBox(width: 6),
                    // 이름 하나가 화면보다 길 수 있다 — 그 칸 안에서 줄을 바꾼다.
                    Flexible(
                      child: Text(route.waypoints[i],
                          style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
                    ),
                  ]),
                ),
            ],
          ),
        ]);
      }
    });
  }

  /// 산책로를 지도에서 보여 준다 (#291 · #619). 선은 카탈로그에 없어 시트를 열 때 따로 받는다.
  ///
  /// **선이 없는 코스도 여기로 온다.** 동네 길은 원본에 좌표가 없어 그릴 선이 없는데,
  /// 예전에는 그때 아무 일도 안 났다 — 사용자가 눌러도 화면이 그대로였다(2026-09-17 신고).
  /// 지금은 카메라를 그 시작 지점으로 옮긴다. 거쳐 가는 곳 이름은 시트가 따로 보여 준다.
  ///
  /// 못 받으면 아무것도 안 그린다 — 산책로 항목은 이미 시작점 마커로 화면에 있고 선은
  /// 덧그림이다. 지도가 없는 빌드(`_mapCtrl == null`)는 받지도 않는다.
  Future<void> _drawTrail(PetPlace p) async {
    final c = _mapCtrl;
    if (c == null) return;
    final route = await _trails.fetch(p.trailCourseId);
    if (!mounted || _mapCtrl == null) return;
    if (route == null || !route.hasLine) {
      // 그릴 선이 없다. 그래도 **어디인지**는 보여 준다 — 시작 지점으로 옮긴다.
      await c.updateCamera(
          NCameraUpdate.withParams(target: NLatLng(p.lat, p.lng), zoom: _kTrailPointZoom));
      return;
    }
    final coords = [for (final q in route.lngLat) NLatLng(q[1], q[0])];
    await c.addOverlay(NPolylineOverlay(
      id: 'trail-${p.trailCourseId}',
      coords: coords,
      color: p.petCategory.color,
      width: 6,
    ));
    double minLat = coords.first.latitude, maxLat = minLat, minLng = coords.first.longitude, maxLng = minLng;
    for (final q in coords) {
      if (q.latitude < minLat) minLat = q.latitude;
      if (q.latitude > maxLat) maxLat = q.latitude;
      if (q.longitude < minLng) minLng = q.longitude;
      if (q.longitude > maxLng) maxLng = q.longitude;
    }
    await c.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds(southWest: NLatLng(minLat, minLng), northEast: NLatLng(maxLat, maxLng)),
      padding: const EdgeInsets.all(60),
    ));
  }

  /// 추천 코스(#725)의 선을 지도 위에 깐다 — 시트가 받은 고리다. 길이를 바꾸면 옛 선을 지우고
  /// 새 선을 깐다(`null` 이면 지우기만). 리스트 뷰거나 지도가 아직 없으면 아무것도 안 한다.
  /// 시트가 화면 아래를 가리므로 아래쪽 여백을 크게 두어 선이 시트 위에 보이게 한다.
  Future<void> _drawLoop(PetPlace p, PlaceLoop? loop) async {
    final c = _mapCtrl;
    if (c == null || view != 'map' || !mounted) return;
    final id = 'loop-${p.contentId}';
    try {
      await c.deleteOverlay(NOverlayInfo(type: NOverlayType.polylineOverlay, id: id));
    } catch (_) {
      // 없던 선을 지우는 것은 실패가 아니다.
    }
    if (loop == null || loop.lngLat.length < 2) return;
    final coords = [for (final q in loop.lngLat) NLatLng(q[1], q[0])];
    await c.addOverlay(NPolylineOverlay(id: id, coords: coords, color: T.warmEnd, width: 5));
    double minLat = coords.first.latitude, maxLat = minLat, minLng = coords.first.longitude, maxLng = minLng;
    for (final q in coords) {
      if (q.latitude < minLat) minLat = q.latitude;
      if (q.latitude > maxLat) maxLat = q.latitude;
      if (q.longitude < minLng) minLng = q.longitude;
      if (q.longitude > maxLng) maxLng = q.longitude;
    }
    await c.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds(southWest: NLatLng(minLat, minLng), northEast: NLatLng(maxLat, maxLng)),
      padding: const EdgeInsets.fromLTRB(60, 60, 60, 340),
    ));
  }

  /// 장소 상세 — 시트 자체는 [PlaceSheet] 가 그린다(#664).
  ///
  /// 예전에는 이 메서드가 시트를 통째로 그렸다. 그래서 급할 때 시트(#337)의 병원 카드는
  /// **누를 것이 전화 버튼 하나뿐**이었다 — 같은 상세를 보여 주고 싶어도 이 화면의 State
  /// 안에 있어서 부를 수가 없었다. 위젯으로 꺼내 둘이 같은 것을 쓴다.
  ///
  /// 여기 남은 것은 <b>이 화면이라야 뜻이 있는 것들</b>이다 — 뷰를 지도로 바꾸고 선을 그리는
  /// "지도에서 보기", 산책을 시작하는 버튼, 산책로의 경유지 목록.
  void _showPlaceSheet(PetPlace p) {
    if (p.isTrail && view == 'map') _drawTrail(p);
    // **빌더 안에서 만들면 안 된다.** 시트가 다시 그려질 때마다 새 Future 가 생겨
    // FutureBuilder 가 로딩으로 돌아가고, 목록이 깜빡인다. 받아 둔 것은 저장소가
    // 기억하므로(`_memory`) 여기서 한 번 부르는 값이 곧 캐시다.
    final Future<TrailRoute?>? stops = p.isTrail ? _trails.fetch(p.trailCourseId) : null;
    // 추천 코스(#725) — 홈 카드의 시트와 같은 줄. 걸을 만한 곳(아래 '이 코스 걷기' 와 같은 조건)에만.
    // 받은 선은 상자에 두고 "이 코스 걷기" 가 들고 간다. 지도 뷰면 지도 위에도 깐다(2026-09-21 —
    // 그리는 곳이 추적 화면 하나라 사장님이 우리 지도에 그려진 코스를 한 번도 못 봤다).
    final walkable = kWalkStartCategories.contains(p.categoryKey) && p.contentId.isNotEmpty;
    final loopHolder = ValueNotifier<PlaceLoop?>(null);
    PlaceSheet.show(
      context,
      p,
      beforeActions: stops == null ? null : _trailNoLineNote(stops),
      afterActions: !walkable && stops == null && p.contentId.isEmpty
          ? null
          : Builder(
              builder: (sheetCtx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (walkable)
                      PlaceLoopPicker(
                        contentId: p.contentId,
                        repository: widget.loops,
                        onLoop: (loop) {
                          loopHolder.value = loop;
                          unawaited(_drawLoop(p, loop));
                        },
                      ),
                    if (stops != null) _trailStops(stops, p.petCategory),
                    // 이 장소의 글 — 홈 시트에만 있던 문(#723)을 여기도(2026-09-21 사장님). 서버가
                    // 아는 장소(contentId)만 글을 모을 수 있다.
                    if (p.contentId.isNotEmpty) placePostsLink(context, sheetCtx, p),
                  ])),
      footer: Builder(builder: (sheetCtx) => _writeAboutPlace(sheetCtx, p)),
      // 순서가 예전과 같다 — 산책 시작 · 전화 · 지도에서 보기 · 길찾기.
      actions: (sheetCtx, messenger) => [
        // 발견에서 기록으로 잇는 자리 (#338). 걸을 만한 곳에만 둔다 — 병원·펫샵·숙박에
        // "이 코스 걷기" 는 뜻이 없다.
        if (kWalkStartCategories.contains(p.categoryKey))
          PlaceSheetAction(
            icon: Icons.directions_walk_rounded,
            // '여기서 산책 시작' 이었다 — 홈 카드가 #724 에서 바꾼 것과 같은 이유다: 멀면 시작하지
            // 않는데 "여기서" 라고 적혀 있었다. 추천 코스 줄이 "'이 코스 걷기' 를 누르면…" 이라고
            // 말하므로 이름이 같아야 한다.
            label: '이 코스 걷기',
            primary: true,
            onTap: () async {
              Navigator.pop(sheetCtx);
              await startWalk(
                context,
                place: WalkPlaceRef(title: p.title, source: p.source, contentId: p.contentId),
                // 홈 카드와 **같게** 군다 (#623). 두 곳이 다르면 같은 이름의 버튼이 다른 일을
                // 하게 되고, 그건 버튼 이름이 거짓이 되는 것과 같다.
                destination: WalkDestination(lat: p.lat, lng: p.lng, distanceM: p.distM),
                // 추천 코스를 받았으면 그 선을 따라 걷는다(#725). 못 받았으면 선 없이 — 지금까지와 같다.
                courseLine: loopHolder.value?.lngLat,
              );
            },
          ),
        if (p.tel.isNotEmpty) PlaceActions.call(p, messenger),
        // 산책로면 전부 (#619). 예전에는 선이 있는 두루누비만 이 버튼을 달았는데, 그러면
        // 동네 길은 **누를 것이 하나도 없는 시트**가 된다. 선이 없어도 할 일이 있다 —
        // 지도를 시작 지점으로 옮기는 것이다.
        if (p.isTrail)
          PlaceSheetAction(
            icon: Icons.map_rounded,
            label: '지도에서 보기',
            primary: true,
            onTap: () async {
              Navigator.pop(sheetCtx);
              if (view != 'map') {
                // 지도 뷰가 만들어지면 onMapReady 가 그린다.
                setState(() {
                  view = 'map';
                  _pendingTrail = p;
                });
              } else {
                await _drawTrail(p);
              }
            },
          ),
        PlaceActions.directions(p, messenger, primary: p.tel.isEmpty && !p.isTrail),
      ],
    );
  }


  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: T.cardBg, borderRadius: BorderRadius.circular(13),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('카테고리',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: T.textSecondary)),
        const SizedBox(height: 8),
        SizedBox(
          width: 168,
          child: Wrap(spacing: 10, runSpacing: 6, children: [
            for (final c in kPetCategories)
              Row(mainAxisSize: MainAxisSize.min, children: [
                // 색만으로 가르지 않는다 — 아이콘을 같이 그린다(#328).
                Container(
                  width: 14, height: 14, alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: c.color),
                  child: Icon(c.icon, size: 9, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Text(c.label, style: const TextStyle(fontSize: 10.5, color: T.textSecondary)),
              ]),
          ]),
        ),
      ]),
    );
  }
}
