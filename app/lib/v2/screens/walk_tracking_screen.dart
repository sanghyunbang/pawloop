import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../data/location_service.dart';
import '../data/pet_places_repository.dart';
import 'create_screen.dart';

/// 실시간 산책 트래킹 — "기록계"가 아니라 걷는 동안 주변을 탐색하는 지도.
/// - 지도 자유 조작(핀치줌 + 줌 버튼), 제스처 시 자동 따라가기 해제 → 따라가기 버튼으로 복귀
/// - 주변 반려 장소 검색(카테고리/텍스트) + POI 핀 탭 정보
/// - 스탯(거리/시간)은 접힌 알약이 기본, 탭하면 펼침
/// - 뒤로가기는 확인 후 종료(실수 방지)
class WalkTrackingScreen extends StatefulWidget {
  const WalkTrackingScreen({super.key});
  @override
  State<WalkTrackingScreen> createState() => _WalkTrackingScreenState();
}

class _WalkTrackingScreenState extends State<WalkTrackingScreen> {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  NaverMapController? _ctrl;
  Timer? _timer;
  StreamSubscription<Position>? _posSub;
  bool _paused = false;
  bool _real = false; // true = 실제 GPS, false = 시뮬(위치 불가 시 폴백)
  bool _follow = true; // 카메라 자동 따라가기(제스처 시 해제)
  bool _statsExpanded = false; // 스탯 패널 펼침 여부(기본 접힘)
  bool _poisLoaded = false;
  int _seconds = 0;
  double _km = 0;

  /// 주변 반려 장소(검색 시트/핀 공용).
  List<PetPlace> _places = const [];

  // 더미 경로(서울숲 근처 루프) — 위치 불가 시 시뮬레이션.
  late final List<NLatLng> _route = _makeRoute();
  final List<NLatLng> _path = [];
  int _idx = 0;

  static List<NLatLng> _makeRoute() {
    const lat0 = 37.5445, lng0 = 127.0374;
    final pts = <NLatLng>[];
    for (int i = 0; i < 40; i++) {
      final t = i / 40 * 2 * math.pi;
      final r = 0.0016 + 0.0006 * math.sin(t * 3);
      pts.add(NLatLng(lat0 + r * math.sin(t), lng0 + r * math.cos(t) * 1.25));
    }
    return pts;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  // ───────────── 트래킹 ─────────────
  Future<void> _start() async {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || !mounted) return;
      setState(() => _seconds++);
      if (!_real) _advanceSim();
    });
    final pos = await LocationService.current();
    if (!mounted) return;
    if (pos != null) {
      _real = true;
      _path.add(NLatLng(pos.latitude, pos.longitude));
      await _ctrl?.updateCamera(
        NCameraUpdate.withParams(target: _path.last, zoom: 16),
      );
      await _drawPath();
      _posSub = LocationService.stream().listen((p) {
        if (_paused || !mounted) return;
        final cur = NLatLng(p.latitude, p.longitude);
        setState(() {
          if (_path.isNotEmpty) _km += _dist(_path.last, cur);
          _path.add(cur);
        });
        _drawPath();
        if (_follow) _ctrl?.updateCamera(NCameraUpdate.withParams(target: cur));
        if (!_poisLoaded) _loadNearbyPlaces(cur);
      });
    } else {
      _path.add(_route[0]);
    }
    _loadNearbyPlaces(_path.last);
  }

  void _advanceSim() {
    if (_idx >= _route.length - 1) return;
    setState(() {
      _idx++;
      _km += _dist(_route[_idx - 1], _route[_idx]);
      _path.add(_route[_idx]);
    });
    _drawPath();
    if (_follow)
      _ctrl?.updateCamera(NCameraUpdate.withParams(target: _path.last));
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
    final places = await PetPlacesRepository().fetchNearby(
      lat: center.latitude,
      lng: center.longitude,
      radius: 3000,
      numOfRows: 40,
    );
    if (!mounted || _ctrl == null || places.isEmpty) return;
    _places = places;
    final markers = <NAddableOverlay>{};
    for (final p in places) {
      final m = NMarker(
        id: 'poi-${p.contentId.isEmpty ? p.title : p.contentId}',
        position: NLatLng(p.lat, p.lng),
        icon: await _poiIcon(p.category),
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
    final cat = p.category;
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
          final cats = kPetCategories
              .where((c) => _places.any((p) => p.contentTypeId == c.key))
              .toList();
          final list = _places.where((p) {
            if (cat != null && p.contentTypeId != cat) return false;
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
                  '주변 반려 장소 ${_places.length}곳',
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
                      ? const Center(
                          child: Text(
                            '조건에 맞는 곳이 없어요',
                            style: TextStyle(fontSize: 13, color: T.textMuted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final p = list[i];
                            final c = p.category;
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
    );
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
      Navigator.of(context).pop();
    }
  }

  void _finish() {
    _timer?.cancel();
    _posSub?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          18 + MediaQuery.of(sheetCtx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '산책 완료! 🐾',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: T.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _sumCell(_timeLabel, '시간'),
                _sumCell('${_km.toStringAsFixed(2)}km', '거리'),
                _sumCell(_pace, '페이스'),
              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateScreen(prefillPlace: '오늘 산책'),
                  ),
                );
              },
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: _warm,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  '기록 저장하기',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(sheetCtx);
                Navigator.pop(context);
              },
              child: const Text('저장 안 함', style: TextStyle(color: T.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sumCell(String v, String label) => Column(
    children: [
      Text(
        v,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: T.textPrimary,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0x9E463C64)),
      ),
    ],
  );

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: NaverMap(
                options: NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: _route[0],
                    zoom: 16,
                  ),
                  locale: const Locale('ko'),
                  scaleBarEnable: false,
                ),
                onMapReady: (c) {
                  _ctrl = c;
                  _start();
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
                                    ? '주변 반려 장소 찾기'
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
            // 하단: 스탯 패널(기본 접힘 알약, 탭하면 펼침)
            Align(
              alignment: Alignment.bottomCenter,
              child: _statsPanel(context),
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

  Widget _statsPanel(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    if (!_statsExpanded) {
      // 접힘: 작은 알약 — 핵심만(상태·거리·시간). 탭하면 펼침.
      return GestureDetector(
        onTap: () => setState(() => _statsExpanded = true),
        child: Container(
          margin: EdgeInsets.only(bottom: bottom + 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E5A4690),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _paused
                      ? const Color(0xFFBBB3CC)
                      : const Color(0xFFFF7E8A),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_km.toStringAsFixed(2)}km · $_timeLabel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: T.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: T.textMuted,
              ),
            ],
          ),
        ),
      );
    }
    // 펼침: 큰 스탯 + 일시정지/종료.
    return Container(
      margin: EdgeInsets.fromLTRB(14, 0, 14, bottom + 14),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E5A4690),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _statsExpanded = false),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _paused
                        ? const Color(0xFFBBB3CC)
                        : const Color(0xFFFF7E8A),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _paused ? '일시정지됨' : '산책 기록 중',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _paused ? T.textMuted : const Color(0xFFE07A4E),
                  ),
                ),
                const Spacer(),
                Text(
                  _real ? '실시간 GPS' : '데모',
                  style: const TextStyle(fontSize: 11, color: T.textMuted),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: T.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(_km.toStringAsFixed(2), 'km'),
              _stat(_timeLabel, '시간'),
              _stat(_pace, '페이스'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _paused = !_paused),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1ECF7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 21,
                          color: T.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _paused ? '재개' : '일시정지',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: T.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _finish,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _warm,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop_rounded, size: 21, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          '종료',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String v, String label) => Column(
    children: [
      Text(
        v,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: T.textPrimary,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 11.5, color: Color(0x9E463C64)),
      ),
    ],
  );
}
