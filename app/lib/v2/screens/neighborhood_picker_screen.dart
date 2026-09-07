// lib/v2/screens/neighborhood_picker_screen.dart
//
// 동네 고르기 — 이슈 #342.
//
// ## 세 단계와 검색을 함께 두는 이유
//
// 시도 → 시군구 → 동은 **아는 사람에게 확실한** 길이고, 검색은 **이름을 아는 사람에게 빠른**
// 길이다. 둘 중 하나만 두면 반대쪽 사람이 헤맨다 — 3,516개를 스크롤로 찾게 하거나,
// "수유1동" 이 강북구인 줄 모르는 사람을 막는다.
//
// ## "현재 위치로 찾기" 는 후보만 준다
//
// 좌표는 **기기 안에서** 목록과 견준다(`RegionCatalog.nearest`). 서버에 물어보지 않고,
// 고르는 것은 사람이다 — 중심점 거리라 경계와 다를 수 있어서 자동으로 정하면 옆 동이 된다.
//
// ## 출처 한 줄은 지우면 안 된다
//
// 목록의 원자료가 통계청 SGIS 이고 가공본이 CC BY 4.0 이라, 파생물인 이 화면에도 출처 표시
// 의무가 남는다.
import 'package:flutter/material.dart';

import '../data/location_service.dart';
import '../data/neighborhood_store.dart';
import '../data/region_catalog.dart';
import '../domain/neighborhood.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

class NeighborhoodPickerScreen extends StatefulWidget {
  const NeighborhoodPickerScreen({
    super.key,
    this.catalog,
    this.store,
    this.locate,
  });

  /// 테스트가 꽂는 자리. `null` 이면 자산에서 읽는다.
  final RegionCatalog? catalog;

  final NeighborhoodStore? store;

  /// 현재 위치. `null` 이면 진짜 GPS 다. 좌표는 이 화면 밖으로 안 나간다.
  final Future<({double lat, double lng})?> Function()? locate;

  @override
  State<NeighborhoodPickerScreen> createState() => _NeighborhoodPickerScreenState();
}

class _NeighborhoodPickerScreenState extends State<NeighborhoodPickerScreen> {
  final _query = TextEditingController();

  RegionCatalog? _catalog;
  String? _sido;
  String? _sigungu;
  List<Neighborhood> _suggested = const [];
  bool _locating = false;
  bool _saving = false;

  late final NeighborhoodStore _hood = widget.store ?? NeighborhoodStore();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = widget.catalog ?? await RegionCatalog.load();
    if (!mounted) return;
    setState(() => _catalog = catalog);
  }

  Future<void> _findByLocation() async {
    final catalog = _catalog;
    if (catalog == null) return;
    setState(() => _locating = true);

    final fix = await (widget.locate ?? _gps)();
    if (!mounted) return;
    setState(() {
      _locating = false;
      // 못 잡았으면 조용히 아무것도 안 한다 — 아래 목록은 그대로 쓸 수 있다.
      _suggested = fix == null ? const [] : catalog.nearest(fix.lat, fix.lng);
    });
    if (fix == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('위치를 잡지 못했어요 · 목록에서 고를 수 있어요'),
      ));
    }
  }

  static Future<({double lat, double lng})?> _gps() async {
    final fix = await LocationService.locate();
    final p = fix.position;
    if (p == null) return null;
    return (lat: p.latitude, lng: p.longitude);
  }

  Future<void> _choose(Neighborhood neighborhood) async {
    if (_saving) return;
    setState(() => _saving = true);
    // 기기에는 반드시 남는다. 서버 전송이 실패해도(게스트·오프라인) 지도는 그 동네로 열린다.
    await _hood.save(neighborhood);
    if (!mounted) return;
    Navigator.of(context).pop(neighborhood);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(context),
            if (catalog == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(child: _body(catalog)),
          ]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 18, 6),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          const Text('내 동네 고르기',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
      );

  Widget _body(RegionCatalog catalog) {
    final query = _query.text.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
      children: [
        TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '동네 이름으로 찾기 (예: 성수동)',
            prefixIcon: const Icon(Icons.search, size: 20, color: T.textMuted),
            filled: true,
            fillColor: const Color(0xCCFFFFFF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _locating ? null : _findByLocation,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Icon(_locating ? Icons.hourglass_empty : Icons.my_location_rounded,
                size: 17, color: const Color(0xFFE07A4E)),
            const SizedBox(width: 7),
            Text(_locating ? '위치를 찾는 중…' : '현재 위치로 찾기',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('좌표는 기기 밖으로 안 나가요',
                  style: TextStyle(fontSize: 11.5, color: T.textMuted)),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        if (query.isNotEmpty)
          ..._section('검색 결과', catalog.search(query))
        else if (_suggested.isNotEmpty)
          ..._section('현재 위치 근처', _suggested)
        else
          ..._steps(catalog),

        const SizedBox(height: 22),
        // 라이선스가 요구하는 표시다. 지우면 안 된다.
        Text(catalog.attribution,
            style: const TextStyle(fontSize: 10.5, color: T.textMuted)),
      ],
    );
  }

  List<Widget> _section(String title, List<Neighborhood> items) => [
        Text(title,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0x9E463C64))),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('찾는 동네가 없어요 · 아래에서 시도부터 골라 보세요',
                style: TextStyle(fontSize: 13, color: T.textMuted)),
          ),
        for (final n in items) _dongTile(n),
      ];

  List<Widget> _steps(RegionCatalog catalog) {
    final sido = _sido;
    final sigungu = _sigungu;

    if (sido == null) {
      return [
        _stepTitle('어느 시·도인가요'),
        _chips(catalog.sidos, (v) => setState(() => _sido = v)),
      ];
    }
    if (sigungu == null) {
      return [
        _crumb('$sido >', () => setState(() => _sido = null)),
        _stepTitle('어느 시·군·구인가요'),
        _chips(catalog.sigungusOf(sido), (v) => setState(() => _sigungu = v)),
      ];
    }
    return [
      _crumb('$sido > $sigungu >', () => setState(() => _sigungu = null)),
      _stepTitle('어느 동인가요'),
      for (final n in catalog.dongsOf(sido: sido, sigungu: sigungu)) _dongTile(n),
    ];
  }

  Widget _stepTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
      );

  Widget _crumb(String text, VoidCallback onBack) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: onBack,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            const Icon(Icons.chevron_left, size: 16, color: Color(0xFFE07A4E)),
            Text(text,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
          ]),
        ),
      );

  Widget _chips(List<String> names, ValueChanged<String> onTap) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in names)
            GestureDetector(
              onTap: () => onTap(name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xC9FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1F8C7BFF)),
                ),
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
              ),
            ),
        ],
      );

  Widget _dongTile(Neighborhood n) => GestureDetector(
        onTap: () => _choose(n),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xCCFFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.label,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 2),
                Text(n.sido, style: const TextStyle(fontSize: 12, color: T.textMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBB3CC)),
          ]),
        ),
      );
}
