import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/places.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import '../data/explore_repository.dart';
import 'place_detail_screen.dart';
import 'create_screen.dart';

/// 탐색 (explore) — 리스트/지도 토글. 핀/카드 = 다녀온 뒤의 마음(A→B).
class ExploreScreen extends StatefulWidget {
  final String initialView; // 'list' | 'map'
  const ExploreScreen({super.key, this.initialView = 'list'});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  int? exEmo; // null = 전체, 아니면 to == exEmo
  bool pet = false;
  late String view = widget.initialView; // 'list' | 'map'
  NaverMapController? _mapCtrl;
  late final Future<List<RemotePlace>> _remote = ExploreRepository().fetchPlaces();

  List<Place> get _filtered {
    var list = kPlaces.where((p) => exEmo == null || p.to == exEmo);
    if (pet) list = list.where((p) => p.pet);
    final out = list.toList()..sort((a, b) => b.lift.compareTo(a.lift));
    return out;
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

  // ───────────── 리스트 뷰 ─────────────
  Widget _listView() {
    final list = _filtered;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 100),
      children: [
        Row(children: const [
          Text('탐색', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          ProfileAvatar(),
        ]),
        const SizedBox(height: 12),
        _searchRow(),
        const SizedBox(height: 10),
        _filterBar(),
        const SizedBox(height: 16),
        FutureBuilder<List<RemotePlace>>(
          future: _remote,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF8E7BFF))),
              );
            }
            final remote = snap.data ?? const <RemotePlace>[];
            if (snap.hasError || remote.isEmpty) {
              // 폴백: 큐레이션 더미(A→B)
              return Column(children: [
                for (final p in list) ...[_placeCard(p), const SizedBox(height: 12)],
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.cloud_done, size: 15, color: Color(0xFF33BFA6)),
                SizedBox(width: 5),
                Text('실시간 장소 · 백엔드 연동', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2E9E88))),
              ]),
              const SizedBox(height: 10),
              for (final rp in remote) ...[_remoteCard(rp), const SizedBox(height: 12)],
            ]);
          },
        ),
      ],
    );
  }

  Widget _imgFallback() => Container(
        width: 64, height: 64,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF0E6FA), Color(0xFFE0D2F0)]),
        ),
        child: const Icon(Icons.image_outlined, size: 24, color: Color(0xFFB6A8D0)),
      );

  Widget _remoteCard(RemotePlace rp) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateScreen())),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: rp.image.isNotEmpty
                  ? Image.network(rp.image, width: 60, height: 60, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imgFallback())
                  : _imgFallback(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rp.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0x148E7BFF), borderRadius: BorderRadius.circular(8)),
                  child: Text(rp.categoryLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF8E7BFF))),
                ),
                if (rp.region.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(rp.region, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: T.textMuted)),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCABFDC)),
          ]),
          const SizedBox(height: 11),
          Container(height: 1, color: const Color(0x148C7BFF)),
          const SizedBox(height: 9),
          // 빈 상태: 아직 감정 기록이 없는 장소 → 첫 기록 유도
          Row(children: const [
            Text('🌱', style: TextStyle(fontSize: 13)),
            SizedBox(width: 6),
            Expanded(child: Text('아직 마음 기록이 없어요', style: TextStyle(fontSize: 12.5, color: Color(0xA8463C64)))),
            Text('첫 기록 남기기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF8E7BFF))),
            SizedBox(width: 2),
            Icon(Icons.arrow_forward, size: 13, color: Color(0xFF8E7BFF)),
          ]),
        ]),
      ),
    );
  }

  // 필터 버튼(누르면 시트). 가로 스크롤 대신.
  Widget _filterBar() {
    final parts = <String>[];
    if (exEmo != null) parts.add(kEmotions[exEmo!].label);
    if (pet) parts.add('반려동물');
    final active = parts.isNotEmpty;
    final label = active ? parts.join(' · ') : '필터';
    return Row(children: [
      GestureDetector(
        onTap: _openFilterSheet,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [Color(0xFFC8A0FF), Color(0xFF9E7BFF)]) : null,
            color: active ? null : const Color(0xC9FFFFFF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? Colors.transparent : const Color(0x73FFFFFF)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune, size: 17, color: active ? Colors.white : T.textSecondary),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : T.textSecondary)),
            const SizedBox(width: 5),
            Icon(Icons.expand_more, size: 17, color: active ? const Color(0xCCFFFFFF) : T.textMuted),
          ]),
        ),
      ),
      const Spacer(),
    ]);
  }

  void _openFilterSheet() {
    int? tmpEmo = exEmo;
    bool tmpPet = pet;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        Widget chip(String label, int? idx) {
          final on = tmpEmo == idx;
          final grad = idx == null ? null : kEmotions[idx].grad;
          return GestureDetector(
            onTap: () => setSheet(() => tmpEmo = idx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                gradient: on ? grad : null,
                color: on ? (grad == null ? const Color(0xFF8E7BFF) : null) : const Color(0xFFF1ECF7),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: on ? Colors.transparent : const Color(0x1F8C7BFF)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (idx != null) ...[kEmotions[idx].icon(21), const SizedBox(width: 5)],
                Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
              ]),
            ),
          );
        }

        return Container(
          decoration: const BoxDecoration(color: Color(0xFAFCFAFF), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 16),
            const Text('어떤 마음이 되고 싶나요?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 4),
            const Text('되고 싶은 마음을 고르면 그 변화를 도와준 곳을 보여드려요.', style: TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              chip('전체', null),
              for (int i = 0; i < kEmotions.length; i++) chip(kEmotions[i].label, i),
            ]),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setSheet(() => tmpPet = !tmpPet),
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                const Text('🐾', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                const Expanded(child: Text('반려동물 동반 가능', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: T.textSecondary))),
                Container(
                  width: 46, height: 28,
                  alignment: tmpPet ? Alignment.centerRight : Alignment.centerLeft,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: tmpPet ? const Color(0xFF8E7BFF) : const Color(0x33836FFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Row(children: [
              GestureDetector(
                onTap: () => setSheet(() { tmpEmo = null; tmpPet = false; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(color: const Color(0xFFF1ECF7), borderRadius: BorderRadius.circular(14)),
                  child: const Text('초기화', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() { exEmo = tmpEmo; pet = tmpPet; });
                    _refreshMarkers();
                    Navigator.pop(sheetCtx);
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.7, 1), colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('적용', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        );
      }),
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
            Text('카페, 공원, 산책...', style: TextStyle(fontSize: 14, color: T.textMuted)),
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
          width: 42,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFFC8A0FF), Color(0xFF9E7BFF)]) : null,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 21, color: on ? Colors.white : T.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xC2FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(children: [seg('list', Icons.view_agenda_outlined), seg('map', Icons.map_outlined)]),
    );
  }

  void _openPlace(Place p) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: p)),
      );

  void _showPlaceCard(Place p) {
    final to = kEmotions[p.to], from = kEmotions[p.from];
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
              decoration: BoxDecoration(gradient: to.grad, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: to.c2.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))]),
              child: to.icon(36.4),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: to.c2.withOpacity(0.14), borderRadius: BorderRadius.circular(9)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.trending_up, size: 12, color: to.c2),
                      const SizedBox(width: 2),
                      Text('+${p.lift}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: to.c2)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 3),
                Text('${p.cat} · ${p.dist}', style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
              ]),
            ),
            GestureDetector(onTap: () => Navigator.pop(sheetCtx), child: const Icon(Icons.close, size: 22, color: Color(0xFFBBB3CC))),
          ]),
          const SizedBox(height: 12),
          Text(p.line, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xCC463C64))),
          const SizedBox(height: 12),
          Row(children: [
            _miniDot(from), const SizedBox(width: 6),
            const Icon(Icons.arrow_forward, size: 14, color: T.textMuted), const SizedBox(width: 6),
            _miniDot(to), const SizedBox(width: 8),
            Text('${from.label} → ${to.label}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            GestureDetector(
              onTap: () { Navigator.pop(sheetCtx); _openPlace(p); },
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12), child: Text('더보기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary))),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () { Navigator.pop(sheetCtx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateScreen(initialPlace: p))); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
                decoration: BoxDecoration(gradient: to.grad, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: to.c2.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.edit, size: 17, color: Colors.white),
                  SizedBox(width: 7),
                  Text('기록', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _placeCard(Place p) {
    final to = kEmotions[p.to];
    final from = kEmotions[p.from];
    return GestureDetector(
      onTap: () => _openPlace(p),
      child: GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: to.grad, borderRadius: BorderRadius.circular(16)),
            child: to.icon(36.4),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: to.c2.withOpacity(0.14), borderRadius: BorderRadius.circular(9)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.trending_up, size: 12, color: to.c2),
                    const SizedBox(width: 2),
                    Text('+${p.lift}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: to.c2)),
                  ]),
                ),
              ]),
              const SizedBox(height: 3),
              Text('${p.cat} · ${p.dist}', style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
              const SizedBox(height: 6),
              Text(p.line, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xCC463C64))),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: const Color(0x14785AA0)),
        const SizedBox(height: 10),
        Row(children: [
          _miniDot(from), const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 14, color: T.textMuted), const SizedBox(width: 6),
          _miniDot(to), const SizedBox(width: 7),
          Text('${from.label} → ${to.label}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const Spacer(),
          Text('${p.n}명 호전', style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
      ]),
    ));
  }

  Widget _miniDot(Emotion e) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
      child: e.icon(15.4),
    );
  }

  // ───────────── 지도 뷰 ─────────────
  Widget _mapView() {
    // 지도는 화면을 꽉 채우고, 검색/필터는 그 위에 얇게 떠 있음(개방감).
    return Stack(children: [
      Positioned.fill(child: _mapStack()),
      Positioned(
        top: 6, left: 16, right: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(13),
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
          _filterBar(),
        ]),
      ),
    ]);
  }

  Widget _mapStack() {
    return Stack(children: [
      // 실제 네이버 지도
      Positioned.fill(
        child: NaverMap(
          options: const NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(target: NLatLng(37.5446, 127.018), zoom: 11.4),
            locationButtonEnable: true,
            locale: Locale('ko'),
            scaleBarEnable: false,
            minZoom: 9,
            maxZoom: 17,
          ),
          onMapReady: (c) {
            _mapCtrl = c;
            _refreshMarkers();
          },
        ),
      ),
      // 안내 배너 (떠 있는 검색/필터 아래에)
      Positioned(
        top: 112,
        left: 20,
        right: 20,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xF0FFFFFF),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: const Text('이 동네는 주로 마음을 평온으로 이끌어요 😌',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
          ),
        ),
      ),
      // 범례
      Positioned(left: 16, bottom: 168, child: _legend()),
      // 하단 CTA
      Positioned(
        left: 40, right: 40, bottom: 108,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF9E7D), Color(0xFFFF8FB0)]),
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Color(0x40FF8FB0), blurRadius: 16, offset: Offset(0, 8))],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.touch_app_outlined, color: Colors.white, size: 18),
            SizedBox(width: 7),
            Text('핀을 눌러 마음의 변화를 확인하세요',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
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
      final icon = await _markerIcon(p);
      final m = NMarker(id: p.name, position: NLatLng(p.lat, p.lng), icon: icon);
      m.setOnTapListener((_) => _showPlaceCard(p));
      markers.add(m);
    }
    if (markers.isNotEmpty) await c.addOverlayAll(markers);
  }

  /// 감정색 오브 마커(플랫폼 통일 — Flutter 위젯을 이미지로 렌더).
  Future<NOverlayImage> _markerIcon(Place p) async {
    final e = kEmotions[p.to];
    return NOverlayImage.fromWidget(
      context: context,
      size: const Size(52, 52),
      widget: SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: e.grad,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: e.c2.withOpacity(0.55), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: e.icon(30.8),
          ),
        ),
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
        const Text('핀 색 = 다녀온 뒤의 마음',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: T.textSecondary)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (int i = 0; i < kEmotions.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, gradient: kEmotions[i].grad)),
              const SizedBox(width: 4),
              Text(kEmotions[i].label, style: const TextStyle(fontSize: 10.5, color: T.textSecondary)),
            ]),
        ]),
      ]),
    );
  }

}
