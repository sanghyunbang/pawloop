import 'dart:async';

import '../data/external_maps.dart';
import '../data/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import '../widgets/map_unavailable.dart';
import '../widgets/vet_badge.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import 'post_write_screen.dart';
import '../domain/pet.dart';
import '../domain/vet_hours.dart';
import '../walk/route_image.dart';
import '../domain/course_path.dart';
import '../data/course_repository.dart';
import 'start_walk.dart';
import '../data/walk_repository.dart';
import '../data/pet_places_repository.dart';
import '../data/place_catalog_repository.dart';
import '../data/trail_route_repository.dart';
import '../data/location_upload_policy.dart';
import '../data/location_service.dart';
import '../data/neighborhood_store.dart';
import '../domain/neighborhood.dart';
import '../widgets/aurora.dart';
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

class ExploreScreen extends StatefulWidget {
  final String initialView; // 'list' | 'map'

  /// 테스트가 진짜 네트워크·카탈로그에 닿지 않게 끼우는 자리. 없으면 실물이다.
  final PetPlacesRepository? repository;

  /// 이웃 코스 저장소. 테스트가 꽂는 자리다 (#339).
  final CourseRepository? courses;
  /// 내 동네를 읽는 자리 (#342). **테스트만 넘긴다.**
  final NeighborhoodStore? neighborhoods;

  const ExploreScreen({
    super.key,
    this.initialView = 'list',
    this.repository,
    this.courses,
    this.neighborhoods,
  });
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late String view = widget.initialView;
  NaverMapController? _mapCtrl;
  late final PetPlacesRepository _repo = widget.repository ?? PetPlacesRepository();
  late final CourseRepository _courses = widget.courses ?? CourseRepository();
  final _trails = TrailRouteRepository();

  // 기본 중심: 서울 시청. (추후 현재 위치)
  NLatLng _center = const NLatLng(37.5665, 126.9816);
  List<PetPlace> _places = const [];
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
  String? _catFilter; // null = 전체, 아니면 contenttypeid

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
      _center = NLatLng(pos.latitude, pos.longitude);
      _fallbackCenter = false;
      await _mapCtrl?.updateCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
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
    await _mapCtrl?.updateCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
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

  int _loadSeq = 0;

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    // 칩 키를 조회에 붙인다 — 받아 놓은 80곳 안에서 거르면 병원은 매장 뒤에 묻힌다(#291 실측).
    final places = await _repo.fetchNearby(
      lat: _center.latitude,
      lng: _center.longitude,
      contentTypeId: _catFilter,
    );
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _places = places;
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
    } catch (_) {
      all = const [];
    }
    if (!mounted) return;
    setState(() {
      _nearbyCourses = nearestByStart<Course>(
        all,
        _center.latitude,
        _center.longitude,
        startOf: (course) => course.start,
      );
      _coursesLoading = false;
    });
  }

  List<PetPlace> get _filtered {
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
      backgroundColor: T.lilacTop,
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
            color: const Color(0xE6FFFFFF),
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
                  : const Icon(Icons.route_rounded, size: 22, color: Color(0xFFBBB3CC)),
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
                      style: const TextStyle(fontSize: 12, color: Color(0xCC463C64))),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBB3CC)),
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
              child: const Icon(Icons.close, size: 22, color: Color(0xFFBBB3CC)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${course.km.toStringAsFixed(2)}km · 시작·끝 100m 는 빠져 있어요',
              style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
          if (course.note != null && course.note!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(course.note!, style: const TextStyle(fontSize: 13.5, color: Color(0xCC463C64))),
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
                  colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
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
          Text('지도', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          ProfileAvatar(),
        ]),
        const SizedBox(height: 4),
        const Text('우리 아이랑 갈 수 있는 곳', style: TextStyle(fontSize: 13, color: Color(0xB3463C64))),
        const SizedBox(height: 12),
        _searchRow(),
        const SizedBox(height: 10),
        _catChips(),
        const SizedBox(height: 14),
        if (_neighbourCourses) ...[
          if (_coursesLoading)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF0B7A75))))
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: Color(0xFFFF8F63))))
        else if (_filtered.isEmpty)
          _emptyBox()
        else ...[
          Row(children: [
            const Icon(Icons.pets, size: 15, color: Color(0xFFFF8F63)),
            const SizedBox(width: 5),
            Text('${_headerLabel()} · ${_filtered.length}곳',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
            const Spacer(),
            Text(_sourceCaption(), style: const TextStyle(fontSize: 10.5, color: T.textMuted)),
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
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
  /// A안 빌드만 가를 수 있다. 서버 조회(B안)는 실패도 빈 목록으로 오고 그 구분은
  /// 저장소 계약이 일부러 안 한다("실패를 빈 목록으로 다룬다"). 그쪽은 그대로 둔다.
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
    // 못 받은 것을 "없다" 고 말하면 안 된다. "지도를 움직여 보세요" 는 그 사람이 시킨
    // 대로 해도 소용이 없는 안내고, 5분 백오프 때문에 움직여도 다시 안 받는다.
    if (_catalogUnavailable) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
        child: Column(children: [
          const Icon(Icons.cloud_off_outlined, size: 36, color: T.textMuted),
          const SizedBox(height: 10),
          const Text('장소 목록을 아직 못 받았어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 4),
          const Text('네트워크를 확인하고 다시 시도해 주세요', style: TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
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
          _catFilter == 'trail'
              // 산책로는 반경을 안 본다 — 비었다면 카탈로그에 코스가 아직 없는 것이다.
              ? '전국의 코스를 가까운 순으로 봤어요 · 잠시 뒤 다시 열어 보세요'
              : '현위치 8km 안을 봤어요 · 필터를 바꿔보세요',
          style: const TextStyle(fontSize: 12.5, color: Color(0xA8463C64)),
        ),
      ]),
    );
  }

  /// 목록 머리 라벨 — 산책로를 "반려동반 가능" 이라고 부르지 않는다(#328).
  String _headerLabel() => switch (_catFilter) {
        'trail' => '가까운 산책로',
        'vet' => '동물병원',
        'shop' => '펫샵',
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
    // 숫자는 흰 글자 + 보라 후광 — 기본 핀 위에 흰 글자만 얹으면 안 보였다(에뮬레이터 확인).
    marker.setCaption(NOverlayCaption(
      text: '${info.size}',
      color: Colors.white,
      haloColor: const Color(0xFF8E7BFF),
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
          color: const Color(0xFF8E7BFF),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
      ),
    );
  }

  /// 시트의 주 동작 — 전화 · 지도에서 보기(산책로) · 길찾기. 글쓰기는 그 아래 두 번째다(#328).
  Widget _sheetActions(BuildContext sheetCtx, PetPlace p) {
    Widget action(IconData icon, String label, Future<void> Function() onTap, {bool primary = false}) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: primary
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
                      )
                    : null,
                color: primary ? null : const Color(0xFFF1ECF7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: primary ? Colors.white : T.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: primary ? Colors.white : T.textSecondary)),
              ]),
            ),
          ),
        );
    final messenger = ScaffoldMessenger.of(context);
    final actions = <Widget>[
      // 발견에서 기록으로 잇는 자리 (#338). 걸을 만한 곳에만 둔다 — 병원·펫샵·숙박에
      // "여기서 산책 시작" 은 뜻이 없다.
      if (kWalkStartCategories.contains(p.categoryKey))
        action(Icons.directions_walk_rounded, '여기서 산책 시작', () async {
          Navigator.pop(sheetCtx);
          await startWalk(
            context,
            place: WalkPlaceRef(title: p.title, source: p.source, contentId: p.contentId),
          );
        }, primary: true),
      if (p.tel.isNotEmpty)
        action(Icons.call_rounded, '전화', () async {
          if (!await ExternalMaps.call(p.tel)) {
            messenger.showSnackBar(const SnackBar(content: Text('전화 앱을 열 수 없어요')));
          }
        }, primary: true),
      if (p.isTrail)
        action(Icons.map_rounded, '지도에서 보기', () async {
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
        }, primary: true),
      action(Icons.directions_walk_rounded, '길찾기', () async {
        if (!await ExternalMaps.directions(lat: p.lat, lng: p.lng, name: p.title)) {
          messenger.showSnackBar(const SnackBar(content: Text('지도 앱을 열 수 없어요')));
        }
      }, primary: p.tel.isEmpty && !p.isTrail),
    ];
    return Row(children: [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        actions[i],
      ],
    ]);
  }

  /// 목록 머리의 출처 한 마디 — 칩에 따라 다르다 (#291).
  String _sourceCaption() => switch (_catFilter) {
        'vet' || 'shop' => '행정안전부 인허가 · 전국',
        'trail' => '두루누비 · 가까운 코스 $kTrailNearestLimit개 (거리 제한 없음)',
        null => '관광공사 · 인허가 · 두루누비',
        _ => '관광공사',
      };

  Widget _imgFallback(PetCategory cat) => Container(
        width: 64, height: 64, alignment: Alignment.center,
        decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.14)),
        child: Icon(cat.icon, size: 26, color: cat.color),
      );

  Widget _placeCard(PetPlace p) {
    final cat = p.petCategory;
    return GestureDetector(
      onTap: () => _showPlaceSheet(p),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: p.image.isNotEmpty
                ? Image.network(p.image, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imgFallback(cat))
                : _imgFallback(cat),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 6),
              Row(children: [
                _catTag(cat),
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
            ]),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCABFDC)),
        ]),
      ),
    );
  }

  Widget _catTag(PetCategory cat) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(cat.icon, size: 12, color: cat.color),
          const SizedBox(width: 4),
          Text(cat.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cat.color)),
        ]),
      );

  // 카테고리 필터 칩 (가로 스크롤).
  Widget _catChips() {
    Widget chip(String label, String? key, Color color) {
      final on = _catFilter == key;
      return GestureDetector(
        onTap: () {
          if (_catFilter == key) return;
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
            color: on ? color : const Color(0xC9FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Colors.transparent : const Color(0x1F8C7BFF)),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        chip('전체', null, const Color(0xFFFF8F63)),
        for (final c in kPetCategories) chip(c.label, c.key, c.color),
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
          color: _neighbourCourses ? teal : const Color(0xC9FFFFFF),
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
          color: _only24h ? red : const Color(0xC9FFFFFF),
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

  Widget _searchRow() {
    return Row(children: [
      Expanded(
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xC2FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x66FFFFFF)),
          ),
          child: const Row(children: [
            Icon(Icons.search, size: 20, color: T.textMuted),
            SizedBox(width: 8),
            Text('카페, 공원, 산책로...', style: TextStyle(fontSize: 14, color: T.textMuted)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      _viewToggle(),
    ]);
  }

  Widget _viewToggle() {
    Widget seg(String v, IconData icon) {
      final on = view == v;
      return GestureDetector(
        onTap: () => setState(() => view = v),
        child: Container(
          width: 42, height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)]) : null,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 21, color: on ? Colors.white : T.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xC2FFFFFF), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66FFFFFF)),
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
              child: Container(
                height: 42, padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xF2FFFFFF), borderRadius: BorderRadius.circular(13),
                  boxShadow: const [BoxShadow(color: Color(0x1F5A4690), blurRadius: 14, offset: Offset(0, 5))],
                ),
                child: const Row(children: [
                  Icon(Icons.search, size: 18, color: T.textMuted),
                  SizedBox(width: 8),
                  Text('이 지역에서 찾기...', style: TextStyle(fontSize: 13.5, color: T.textMuted)),
                ]),
              ),
            ),
            const SizedBox(width: 9),
            _viewToggle(),
            const SizedBox(width: 9),
            const ProfileAvatar(size: 40),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 40, child: _catChips()),
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
          onMapReady: (c) async {
            _mapCtrl = c;
            await _prepareClusterIcon();
            c.updateCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
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
      if (!_loading && _farNotice != null)
        Positioned(
          top: 112, left: 16, right: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xF0FFFFFF), borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Text(_farNotice!,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
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
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8F63))),
                  SizedBox(width: 10),
                  Text('주변 장소 불러오는 중...', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Future<void> _refreshMarkers() async {
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
    if (markers.isNotEmpty) await c.addOverlayAll(markers);
    // 필터를 바꿔도 카메라는 안 옮긴다 — 사용자가 보고 있는 곳이 기준이다. 산책로만 예외다
    // (`_fitToPlaces`, #328): 가장 가까운 코스가 화면 밖이라 빈 지도가 됐었다.
  }

  /// 카테고리색 핀(플랫폼 통일 — Flutter 위젯 렌더).
  Future<NOverlayImage> _markerIcon(PetCategory cat) async {
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
          color: const Color(0xFFF1ECF7),
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

  /// 산책로의 선을 지도에 얹는다 (#291). 선은 카탈로그에 없어 시트를 열 때 따로 받는다.
  ///
  /// 못 받으면 아무것도 안 그린다 — 산책로 항목은 이미 시작점 마커로 화면에 있고 선은
  /// 덧그림이다. 카메라는 선이 보이게 옮긴다. 지도가 없는 빌드(`_mapCtrl == null`)는
  /// 받지도 않는다.
  Future<void> _drawTrail(PetPlace p) async {
    final c = _mapCtrl;
    if (c == null) return;
    final route = await _trails.fetch(p.trailCourseId);
    if (route == null || !mounted || _mapCtrl == null) return;
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

  void _showPlaceSheet(PetPlace p) {
    final cat = p.petCategory;
    if (p.isTrail && view == 'map') _drawTrail(p);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 56, height: 56, alignment: Alignment.center,
              decoration: BoxDecoration(color: cat.color, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: cat.color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5))]),
              child: Icon(cat.icon, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 4),
                Row(children: [
                  _catTag(cat),
                  // 진료시간 데이터가 없어서 이름으로 짐작한다 — 배지가 그 사실을 함께 말한다(#337).
                  if (p.categoryKey == 'vet' && isTwentyFourHourByName(p.title)) ...[
                    const SizedBox(width: 7),
                    const VetTwentyFourBadge(),
                  ],
                  if (p.distLabel.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Text(p.distLabel, style: const TextStyle(fontSize: 12, color: T.textMuted)),
                  ],
                ]),
              ]),
            ),
            GestureDetector(onTap: () => Navigator.pop(sheetCtx), child: const Icon(Icons.close, size: 22, color: Color(0xFFBBB3CC))),
          ]),
          if (p.summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              Icon(cat.icon, size: 16, color: cat.color),
              const SizedBox(width: 7),
              Expanded(child: Text(p.summary, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary))),
            ]),
          ],
          if (p.addr.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.place_outlined, size: 16, color: T.textMuted),
              const SizedBox(width: 7),
              Expanded(child: Text(p.addr, style: const TextStyle(fontSize: 13, color: Color(0xCC463C64)))),
            ]),
          ],
          if (p.tel.isNotEmpty) ...[
            const SizedBox(height: 9),
            Row(children: [
              const Icon(Icons.call_outlined, size: 16, color: T.textMuted),
              const SizedBox(width: 7),
              Text(p.tel, style: const TextStyle(fontSize: 13, color: Color(0xCC463C64))),
            ]),
          ],
          const SizedBox(height: 8),
          // 출처 배지 — 어디서 온 데이터인지 말한다 (#291). 가짜 레이어는 #282 로 사라졌다.
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pets, size: 13, color: Color(0xFFFF8F63)),
            const SizedBox(width: 5),
            Text(p.sourceLabel,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
          ]),
          const SizedBox(height: 14),
          _sheetActions(sheetCtx, p),
          const SizedBox(height: 10),
          _writeAboutPlace(sheetCtx, p),
        ]),
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xF0FFFFFF), borderRadius: BorderRadius.circular(13),
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
