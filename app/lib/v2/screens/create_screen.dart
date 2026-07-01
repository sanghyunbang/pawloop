import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 산책 기록 작성 (create) — 장소·거리·시간·메모·사진. (감정 도메인 제거, 강아지 산책 중심)
class CreateScreen extends StatefulWidget {
  final String? prefillPlace; // 장소 상세 "여기서 산책 기록 쓰기"에서 prefill
  const CreateScreen({super.key, this.prefillPlace});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _place = TextEditingController();
  final _memo = TextEditingController();

  double km = 2.0;
  int minutes = 30;

  static const _warm = LinearGradient(
    begin: Alignment(-0.7, -1), end: Alignment(0.7, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  void initState() {
    super.initState();
    if (widget.prefillPlace != null) _place.text = widget.prefillPlace!;
  }

  @override
  void dispose() {
    _place.dispose();
    _memo.dispose();
    super.dispose();
  }

  String get _dateLabel {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final n = DateTime.now();
    return '${n.month}월 ${n.day}일 (${w[n.weekday - 1]})';
  }

  void _save() {
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('산책 기록이 저장됐어요 🐾'), duration: Duration(milliseconds: 1500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _placeCard(),
                  const SizedBox(height: 14),
                  _metricsCard(),
                  const SizedBox(height: 14),
                  _photoCard(),
                  const SizedBox(height: 14),
                  _memoCard(),
                  const SizedBox(height: 18),
                  _saveButton(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x80FFFFFF)),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('산책 기록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: _save,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Text('저장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFFF7E8A))),
            ),
          ),
        ]),
      );

  // 라벨 + 입력박스 헬퍼
  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary));

  BoxDecoration get _fieldDeco => BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2E8C7BFF)),
      );

  // ── 장소 + 날짜 ─────────────────────────────
  Widget _placeCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('어디를 걸었나요?'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(children: [
            const Icon(Icons.place, size: 18, color: Color(0xFFFF9E7D)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _place,
                style: const TextStyle(fontSize: 14, color: T.textPrimary),
                decoration: const InputDecoration(
                  hintText: '예: 서울숲, 한강공원, 동네 한 바퀴',
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _label('날짜'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
          child: Row(children: [
            Text(_dateLabel, style: const TextStyle(fontSize: 14, color: Color(0xFF3A3550))),
            const Spacer(),
            const Icon(Icons.calendar_month, size: 18, color: T.textMuted),
          ]),
        ),
      ]),
    );
  }

  // ── 거리 · 시간 스텝퍼 ────────────────────────
  Widget _metricsCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('얼마나 걸었나요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 14),
        _stepperRow(
          icon: Icons.straighten,
          label: '거리',
          value: '${km.toStringAsFixed(1)} km',
          onMinus: () => setState(() => km = (km - 0.1).clamp(0.0, 99.0)),
          onPlus: () => setState(() => km = (km + 0.1).clamp(0.0, 99.0)),
        ),
        const SizedBox(height: 12),
        _stepperRow(
          icon: Icons.schedule,
          label: '시간',
          value: '$minutes 분',
          onMinus: () => setState(() => minutes = (minutes - 5).clamp(0, 600)),
          onPlus: () => setState(() => minutes = (minutes + 5).clamp(0, 600)),
        ),
      ]),
    );
  }

  Widget _stepperRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    Widget btn(IconData i, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xC9FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x2E8C7BFF)),
            ),
            child: Icon(i, size: 20, color: T.textSecondary),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x8CFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x298C7BFF)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0x22FF9E7D), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 18, color: const Color(0xFFFF8F63)),
        ),
        const SizedBox(width: 10),
        _label(label),
        const Spacer(),
        btn(Icons.remove, onMinus),
        SizedBox(
          width: 78,
          child: Text(value, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF3A3550))),
        ),
        btn(Icons.add, onPlus),
      ]),
    );
  }

  // ── 사진(플레이스홀더) ───────────────────────
  Widget _photoCard() {
    Widget thumb(List<Color> c) => Container(
          width: 74, height: 74,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Align(
            alignment: Alignment(0, 0.4),
            child: Icon(Icons.pets, size: 22, color: Color(0x66FFFFFF)),
          ),
        );
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('사진', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 4),
        const Text('오늘 우리 아이의 산책 순간을 남겨보세요.',
            style: TextStyle(fontSize: 12, color: Color(0xA8463C64))),
        const SizedBox(height: 14),
        Row(children: [
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('사진 첨부는 곧 지원돼요'), duration: Duration(milliseconds: 1200)),
              );
            },
            child: Container(
              width: 74, height: 74, alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x59836FFF), width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.add_a_photo, size: 22, color: Color(0xFF9B8FC4)),
                SizedBox(height: 3),
                Text('추가', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF9B8FC4))),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          thumb(const [Color(0xFFFFD9C2), Color(0xFFFFC0B0)]),
          const SizedBox(width: 10),
          thumb(const [Color(0xFFD4ECFF), Color(0xFFD9F5EC)]),
        ]),
      ]),
    );
  }

  // ── 메모 ────────────────────────────────────
  Widget _memoCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('오늘의 산책', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 12),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: TextField(
            controller: _memo,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.6, color: T.textPrimary),
            decoration: const InputDecoration(
              hintText: '오늘 산책은 어땠나요? 우리 아이의 컨디션, 만난 친구, 특별했던 순간을 적어보세요...',
              hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x66FF7E8A), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.pets, size: 21, color: Colors.white),
          SizedBox(width: 8),
          Text('산책 기록 저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }
}
