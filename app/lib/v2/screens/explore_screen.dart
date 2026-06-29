import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/places.dart';
import '../widgets/aurora.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      children: [
        const Text('탐색', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 4),
        const Text.rich(TextSpan(children: [
          TextSpan(text: '어떤 마음이 ', style: TextStyle(fontSize: 13.5, color: Color(0xC2463C64))),
          TextSpan(text: '되고 싶나요?', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF8E7BFF))),
          TextSpan(text: ' 그 변화를 도와준 곳들이에요.', style: TextStyle(fontSize: 13.5, color: Color(0xC2463C64))),
        ])),
        const SizedBox(height: 14),
        _emoFilters(),
        const SizedBox(height: 10),
        _petPill(full: true),
        const SizedBox(height: 12),
        _searchRow(),
        const SizedBox(height: 14),
        for (final p in list) ...[_placeCard(p), const SizedBox(height: 12)],
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('해당하는 곳이 아직 없어요.', style: TextStyle(color: T.textMuted))),
          ),
      ],
    );
  }

  Widget _emoFilters({bool withPet = false}) {
    Widget chip(String label, int? idx) {
      final on = exEmo == idx;
      final grad = idx == null ? null : kEmotions[idx].grad;
      return GestureDetector(
        onTap: () => setState(() => exEmo = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: on ? grad : null,
            color: on ? (grad == null ? const Color(0xFF8E7BFF) : null) : const Color(0xC2FFFFFF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: on ? Colors.transparent : const Color(0x66FFFFFF)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (idx != null) ...[Text(kEmotions[idx].emoji, style: const TextStyle(fontSize: 14)), const SizedBox(width: 5)],
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
          ]),
        ),
      );
    }

    Widget petChip() => GestureDetector(
          onTap: () => setState(() => pet = !pet),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: pet ? const LinearGradient(colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]) : null,
              color: pet ? null : const Color(0xC2FFFFFF),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: pet ? Colors.transparent : const Color(0x66FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('🐾', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Text('반려동물',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pet ? Colors.white : T.textSecondary)),
            ]),
          ),
        );

    return Wrap(spacing: 8, runSpacing: 8, children: [
      chip('전체', null),
      for (int i = 0; i < kEmotions.length; i++) chip(kEmotions[i].label, i),
      if (withPet) petChip(),
    ]);
  }

  Widget _petPill({bool full = false}) {
    final w = GestureDetector(
      onTap: () => setState(() => pet = !pet),
      child: Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: pet
              ? const LinearGradient(colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)])
              : null,
          color: pet ? null : const Color(0xC2FFFFFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: pet ? Colors.transparent : const Color(0x66FFFFFF)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🐾', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('반려동물 동반',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: pet ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
    return w;
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
              child: Text(to.emoji, style: const TextStyle(fontSize: 26)),
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
            child: Text(to.emoji, style: const TextStyle(fontSize: 26)),
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
      child: Text(e.emoji, style: const TextStyle(fontSize: 11)),
    );
  }

  // ───────────── 지도 뷰 ─────────────
  Widget _mapView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(children: [
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xCCFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              child: const Row(children: [
                Icon(Icons.search, size: 20, color: T.textMuted),
                SizedBox(width: 8),
                Text('이 지역에서 찾기...', style: TextStyle(fontSize: 14, color: T.textMuted)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          _viewToggle(),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: _emoFilters(withPet: true),
      ),
      Expanded(child: _mapStack()),
    ]);
  }

  Widget _mapStack() {
    final list = _filtered;
    return Stack(children: [
      // 스타일라이즈드 맵 배경
      Positioned.fill(
        child: Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          color: const Color(0xFFEFEAF6),
          child: CustomPaint(painter: _MapPainter()),
        ),
      ),
      // 안내 배너
      Positioned(
        top: 10,
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
      // 핀들
      LayoutBuilder(builder: (context, c) {
        return Stack(children: [
          for (int i = 0; i < list.length; i++)
            Positioned(
              left: list[i].x / 100 * c.maxWidth - 24,
              top: list[i].y / 100 * c.maxHeight - 54,
              child: _AnimatedPin(
                emotion: kEmotions[list[i].to],
                pet: list[i].pet,
                tempoMs: 2600 + i * 430,
                onTap: () => _showPlaceCard(list[i]),
              ),
            ),
          // 내 위치
          Positioned(
            left: 0.5 * c.maxWidth - 7,
            top: 0.45 * c.maxHeight - 7,
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF4A90FF), shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [BoxShadow(color: Color(0x554A90FF), blurRadius: 8)],
              ),
            ),
          ),
        ]);
      }),
      // 줌/위치 버튼
      Positioned(
        right: 16, top: 90,
        child: Column(children: [
          _mapBtn(Icons.add), const SizedBox(height: 1), _mapBtn(Icons.remove),
          const SizedBox(height: 10), _mapBtn(Icons.my_location),
        ]),
      ),
      // 범례
      Positioned(left: 16, bottom: 78, child: _legend()),
      // 하단 CTA
      Positioned(
        left: 40, right: 40, bottom: 18,
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

  Widget _mapBtn(IconData icon) {
    return Container(
      width: 40, height: 40,
      margin: const EdgeInsets.symmetric(vertical: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF), borderRadius: BorderRadius.circular(11),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Icon(icon, size: 21, color: T.textSecondary),
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

/// 천천히 부유하는 핀 (핀마다 다른 템포). pet=true면 발바닥 배지.
class _AnimatedPin extends StatefulWidget {
  final Emotion emotion;
  final bool pet;
  final int tempoMs;
  final VoidCallback onTap;
  const _AnimatedPin({required this.emotion, required this.pet, required this.tempoMs, required this.onTap});
  @override
  State<_AnimatedPin> createState() => _AnimatedPinState();
}

class _AnimatedPinState extends State<_AnimatedPin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: widget.tempoMs))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.emotion;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final dy = math.sin(_c.value * 2 * math.pi) * 6;
        return Transform.translate(
          offset: Offset(0, dy),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
            width: 50,
            height: 72,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: e.grad,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [BoxShadow(color: e.c2.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 5))],
                  ),
                  child: Text(e.emoji, style: const TextStyle(fontSize: 20)),
                ),
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: Icon(Icons.arrow_drop_down, color: e.c2, size: 22),
                ),
              ]),
              if (widget.pet)
                Positioned(
                  right: 0,
                  top: -3,
                  child: Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
                    ),
                    child: const Text('🐾', style: TextStyle(fontSize: 10)),
                  ),
                ),
            ]),
          )),
        );
      },
    );
  }
}

/// 스타일라이즈드 맵 배경 (격자 + 부드러운 색 띠).
class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 부드러운 색 띠
    final bands = [
      [const Color(0x33FFD8A8), const Offset(0, 0), const Offset(1, 0.35)],
      [const Color(0x2A9EE2C4), const Offset(0, 0.45), const Offset(1, 0.8)],
      [const Color(0x269EC3FF), const Offset(0.2, 0.7), const Offset(1, 1)],
    ];
    for (final b in bands) {
      final color = b[0] as Color;
      final p1 = b[1] as Offset, p2 = b[2] as Offset;
      final paint = Paint()
        ..shader = LinearGradient(colors: [color, color.withOpacity(0)]).createShader(
            Rect.fromLTWH(0, p1.dy * size.height, size.width, (p2.dy - p1.dy) * size.height))
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTRB(0, p1.dy * size.height, size.width, p2.dy * size.height), paint);
    }
    // 격자
    final grid = Paint()
      ..color = const Color(0x14785AA0)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
