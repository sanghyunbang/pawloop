import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../data/pet_places_repository.dart';
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
    _load();
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

  List<PetPlace> get _filtered =>
      _catFilter == null ? _places : _places.where((p) => p.contentTypeId == _catFilter).toList();

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
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: Color(0xFFFF8F63))))
        else if (_filtered.isEmpty)
          _emptyBox()
        else ...[
          Row(children: [
            const Icon(Icons.pets, size: 15, color: Color(0xFFFF8F63)),
            const SizedBox(width: 5),
            Text('반려동반 가능 · ${_filtered.length}곳',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
            const Spacer(),
            const Text('관광공사', style: TextStyle(fontSize: 10.5, color: T.textMuted)),
          ]),
          const SizedBox(height: 10),
          for (final p in _filtered) ...[_placeCard(p), const SizedBox(height: 12)],
        ],
      ],
    );
  }

  Widget _emptyBox() => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
        child: Column(children: [
          Image.asset('assets/emoji/paw.png', width: 40, height: 40),
          const SizedBox(height: 10),
          const Text('이 지역엔 등록된 곳이 없어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 4),
          const Text('지도를 움직이거나 필터를 바꿔보세요', style: TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
        ]),
      );

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
        child: NaverMap(
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
    final markers = <NAddableOverlay>{};
    for (final p in _filtered) {
      final icon = await _markerIcon(p.category);
      final m = NMarker(id: p.contentId.isEmpty ? p.title : p.contentId, position: NLatLng(p.lat, p.lng), icon: icon);
      m.setOnTapListener((_) => _showPlaceSheet(p));
      markers.add(m);
    }
    if (markers.isNotEmpty) await c.addOverlayAll(markers);
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
          const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pets, size: 13, color: Color(0xFFFF8F63)),
            SizedBox(width: 5),
            Text('반려동물 동반 가능 (관광공사)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
          ]),
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
