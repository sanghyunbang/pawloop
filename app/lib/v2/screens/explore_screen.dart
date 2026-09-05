import 'package:flutter/material.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import '../widgets/map_unavailable.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import 'post_write_screen.dart';
import '../domain/pet.dart';
import '../data/pet_places_repository.dart';
import '../data/place_catalog_repository.dart';
import '../data/location_upload_policy.dart';
import '../data/location_service.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';

/// 지도 — 관광공사 반려동물 동반여행(KTO) 기반 "우리 아이랑 갈 수 있는 곳".
/// 리스트/지도 토글 + 카테고리 필터.
class ExploreScreen extends StatefulWidget {
  final String initialView; // 'list' | 'map'
  const ExploreScreen({super.key, this.initialView = 'list'});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late String view = widget.initialView;
  NaverMapController? _mapCtrl;
  final _repo = PetPlacesRepository();

  // 기본 중심: 서울 시청. (추후 현재 위치)
  NLatLng _center = const NLatLng(37.5665, 126.9816);
  List<PetPlace> _places = const [];
  bool _loading = true;
  String? _catFilter; // null = 전체, 아니면 contenttypeid

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 현위치 확보 → 실패 시 서울 시청 유지.
    final pos = await LocationService.current();
    if (mounted && pos != null) {
      _center = NLatLng(pos.latitude, pos.longitude);
      await _mapCtrl?.updateCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final places = await _repo.fetchNearby(lat: _center.latitude, lng: _center.longitude);
    if (!mounted) return;
    setState(() {
      _places = places;
      _loading = false;
    });
    _refreshMarkers();
  }

  List<PetPlace> get _filtered {
    if (_catFilter == 'trail') return const []; // 산책로는 선(폴리라인)으로 표시
    if (_catFilter == 'vet' || _catFilter == 'shop') return _dummyLayer(_catFilter!);
    if (_catFilter == null) return _places;
    return _places.where((p) => p.contentTypeId == _catFilter).toList();
  }

  bool get _isLayer => _catFilter != null && kLayerKeys.contains(_catFilter);

  // ── 병원/펫샵/산책로 더미 레이어 (실제론 LOCALDATA·두루누비 공공데이터) ──
  List<PetPlace> _dummyLayer(String k) => k == 'vet' ? _dummyVet : _dummyShop;

  //
  // **거리를 안 싣는다** (`distM` 기본값 0 → `distLabel` 이 빈 문자열). 예전에는
  // 320·900·1600 을 박아 두어서 부산 사용자에게도 "320m 동물병원" 이 떴다 — 더미가
  // 측정값처럼 읽히는 순간 더미였을 때보다 나쁘다(`insight_screen.dart` 가 #160 때
  // 같은 판단을 적어 뒀다). 전화번호도 뺀다 — `02-000-0000` 은 누르면 엉뚱한 데로 간다.
  static const List<PetPlace> _dummyVet = [
    PetPlace(contentId: 'v1', title: '서울숲동물병원', contentTypeId: 'vet', addr: '서울 성동구 왕십리로 66', image: '', tel: '', lat: 37.5462, lng: 127.0388),
    PetPlace(contentId: 'v2', title: '성수24시동물의료센터', contentTypeId: 'vet', addr: '서울 성동구 성수이로 118', image: '', tel: '', lat: 37.5445, lng: 127.0559),
    PetPlace(contentId: 'v3', title: '한강동물병원', contentTypeId: 'vet', addr: '서울 광진구 자양로 12', image: '', tel: '', lat: 37.5348, lng: 127.0663),
  ];
  static const List<PetPlace> _dummyShop = [
    PetPlace(contentId: 's1', title: '멍냥마트 성수점', contentTypeId: 'shop', addr: '서울 성동구 연무장길 33', image: '', tel: '', lat: 37.5423, lng: 127.0555),
    PetPlace(contentId: 's2', title: '보리네 펫살롱', contentTypeId: 'shop', addr: '서울 성동구 서울숲2길 18', image: '', tel: '', lat: 37.5471, lng: 127.0413),
  ];

  // 더미 산책로(서울숲 강변 코스).
  static const List<NLatLng> _trailCoords = [
    NLatLng(37.5448, 127.0374), NLatLng(37.5455, 127.0402), NLatLng(37.5451, 127.0435),
    NLatLng(37.5432, 127.0461), NLatLng(37.5418, 127.0492), NLatLng(37.5427, 127.0521),
    NLatLng(37.5446, 127.0538),
  ];

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
        if (_loading && !_isLayer)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: Color(0xFFFF8F63))))
        else if (_catFilter == 'trail')
          _trailCard()
        else if (_filtered.isEmpty)
          _emptyBox()
        else ...[
          Row(children: [
            Icon(_isLayer ? petCatByType(_catFilter).icon : Icons.pets, size: 15, color: _isLayer ? petCatByType(_catFilter).color : const Color(0xFFFF8F63)),
            const SizedBox(width: 5),
            Text('${_isLayer ? petCatByType(_catFilter).label : "반려동반 가능"} · ${_filtered.length}곳',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _isLayer ? petCatByType(_catFilter).color : const Color(0xFFE07A4E))),
            const Spacer(),
            Text(_isLayer ? '공공데이터 (더미)' : '관광공사', style: const TextStyle(fontSize: 10.5, color: T.textMuted)),
          ]),
          const SizedBox(height: 10),
          for (int i = 0; i < _filtered.length; i++) ...[
            _placeCard(_filtered[i]),
            const SizedBox(height: 12),
            // P1 수익화 훅: 리스트 3번째 자리는 동네 제휴 업체 지면(슬롯만 설계, 채움은 P2).
            if (i == 1) ...[_sponsorSlot(), const SizedBox(height: 12)],
          ],
        ],
      ],
    );
  }

  // 제휴 업체 슬롯(placeholder) — 지면 설계용.
  Widget _sponsorSlot() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x66FFFFFF),
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(color: const Color(0x338C7BFF)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF9B7BFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.storefront_rounded, size: 22, color: Color(0xFF9B7BFF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('우리 동네 업체 자리', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            SizedBox(height: 3),
            Text('동네 펫샵·미용·병원이 여기에 소개될 예정이에요', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF9B7BFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('제휴', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF9B7BFF))),
        ),
      ]),
    );
  }

  /// 한 벌을 **아예 못 받은** 상태인가 — "이 지역에 없음" 과 다르다 (이슈 #275).
  ///
  /// A안 빌드만 가를 수 있다. 서버 조회(B안)는 실패도 빈 목록으로 오고 그 구분은
  /// 저장소 계약이 일부러 안 한다("실패를 빈 목록으로 다룬다"). 그쪽은 그대로 둔다.
  bool get _catalogUnavailable =>
      !LocationUploadPolicy.canQueryNearbyPlaces && !PlaceCatalogRepository.instance.hasCatalog;

  Future<void> _retryCatalog() async {
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
        const Text('지도를 움직이거나 필터를 바꿔보세요', style: TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
      ]),
    );
  }

  // 산책로 레이어 카드(더미 — 실제론 두루누비 걷기여행길).
  Widget _trailCard() {
    const trailColor = Color(0xFF2FB89B);
    Widget item(String name, String len, String tag) => GestureDetector(
          onTap: () => setState(() => view = 'map'),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 46, height: 46, alignment: Alignment.center,
                decoration: BoxDecoration(color: trailColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.route_rounded, color: trailColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 5),
                  Row(children: [
                    const Icon(Icons.straighten, size: 12, color: T.textMuted),
                    const SizedBox(width: 3),
                    Text(len, style: const TextStyle(fontSize: 12, color: T.textMuted)),
                    const SizedBox(width: 10),
                    Text(tag, style: const TextStyle(fontSize: 12, color: trailColor, fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCABFDC)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        const Icon(Icons.route_rounded, size: 15, color: trailColor),
        const SizedBox(width: 5),
        const Text('산책로 · 2곳', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: trailColor)),
        const Spacer(),
        const Text('공공데이터 (더미)', style: TextStyle(fontSize: 10.5, color: T.textMuted)),
      ]),
      const SizedBox(height: 10),
      item('서울숲 강변 산책 코스', '2.6km', '반려동반 · 완만'),
      const SizedBox(height: 12),
      item('중랑천 물길 산책로', '4.1km', '반려동반 · 평지'),
    ]);
  }

  Widget _imgFallback(PetCategory cat) => Container(
        width: 64, height: 64, alignment: Alignment.center,
        decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.14)),
        child: Icon(cat.icon, size: 26, color: cat.color),
      );

  Widget _placeCard(PetPlace p) {
    final cat = p.category;
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
          setState(() => _catFilter = key);
          _refreshMarkers();
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
      ]),
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
          onMapReady: (c) {
            _mapCtrl = c;
            c.updateCamera(NCameraUpdate.withParams(target: _center, zoom: 13));
            _refreshMarkers();
          },
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
    if (_catFilter == 'trail') {
      await c.addOverlay(NPolylineOverlay(id: 'trail', coords: _trailCoords, color: const Color(0xFF2FB89B), width: 6));
      await c.addOverlay(NMarker(id: 'trail-start', position: _trailCoords.first, icon: await _markerIcon(petCatByType('trail'))));
      await c.updateCamera(NCameraUpdate.withParams(target: const NLatLng(37.5436, 127.0456), zoom: 14));
      return;
    }
    final markers = <NAddableOverlay>{};
    for (final p in _filtered) {
      final icon = await _markerIcon(p.category);
      final m = NMarker(id: p.contentId.isEmpty ? p.title : p.contentId, position: NLatLng(p.lat, p.lng), icon: icon);
      m.setOnTapListener((_) => _showPlaceSheet(p));
      markers.add(m);
    }
    if (markers.isNotEmpty) await c.addOverlayAll(markers);
    // **레이어를 골라도 카메라를 옮기지 않는다.** 예전에는 더미가 있는 성수동으로
    // 날아갔다 — 부산 사용자가 병원 칩을 누르면 지도가 서울로 갔다. 더미는 사용자가
    // 보고 있는 곳에 없는 것이 정상이고, 그 사실을 감추려고 화면을 움직이면 안 된다.
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
  /// <b>단, 더미 레이어에서는 안 싣는다.</b> 병원·펫샵은 아직 공공데이터가 아니라
  /// `_dummyVet`·`_dummyShop` 의 하드코딩이고 `contentId` 가 `'v1'`·`'s1'` 이다. 서버가
  /// 본 적 없는 값이라, 실으면 나중에 진짜 데이터가 들어왔을 때 아무 장소와도 안 이어지는
  /// 글이 남는다. 이름(`loc`)만 들고 간다 — 그 필드가 정확히 그 자리다.
  ///
  /// 시트를 먼저 닫는다. 그리고 `sheetCtx` 가 아니라 화면의 `context` 로 민다 —
  /// 닫힌 시트의 컨텍스트는 죽어 있다.
  Widget _writeAboutPlace(BuildContext sheetCtx, PetPlace p) {
    final linkable = p.contentId.isNotEmpty && !kLayerKeys.contains(p.contentTypeId);
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
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_outlined, size: 16, color: Colors.white),
          SizedBox(width: 7),
          Text('이 장소로 글쓰기',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  void _showPlaceSheet(PetPlace p) {
    final cat = p.category;
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
                  if (p.distLabel.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Text(p.distLabel, style: const TextStyle(fontSize: 12, color: T.textMuted)),
                  ],
                ]),
              ]),
            ),
            GestureDetector(onTap: () => Navigator.pop(sheetCtx), child: const Icon(Icons.close, size: 22, color: Color(0xFFBBB3CC))),
          ]),
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
          // 출처 배지. **더미에 관광공사를 붙이지 않는다** — 리스트 헤더(`_listView`)는
          // 레이어일 때 '공공데이터 (더미)' 라고 밝히는데, 이 시트가 그것을 뒤집고
          // 있었다. 하드코딩 "서울숲동물병원"(전화 02-000-0000)이 공공데이터 배지를 달고
          // 나갔다. `_writeAboutPlace` 가 이미 같은 판정(`kLayerKeys`)을 한다.
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(kLayerKeys.contains(p.contentTypeId) ? Icons.science_outlined : Icons.pets,
                size: 13, color: const Color(0xFFFF8F63)),
            const SizedBox(width: 5),
            Text(
              kLayerKeys.contains(p.contentTypeId)
                  ? '예시 데이터 · 실제 업체가 아니에요'
                  : '반려동물 동반 가능 (관광공사)',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E)),
            ),
          ]),
          const SizedBox(height: 14),
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
          width: 150,
          child: Wrap(spacing: 10, runSpacing: 6, children: [
            for (final c in kPetCategories)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: c.color)),
                const SizedBox(width: 4),
                Text(c.label, style: const TextStyle(fontSize: 10.5, color: T.textSecondary)),
              ]),
          ]),
        ),
      ]),
    );
  }
}
