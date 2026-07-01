import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import 'create_screen.dart';

/// 내 기록 (myRecords) — 산책 기록. 이번 달 요약 + 전체 산책 리스트.
class MyRecordsScreen extends StatelessWidget {
  const MyRecordsScreen({super.key});

  static const _warm = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  Widget build(BuildContext context) {
    // 이번 달 요약 집계
    final totalKm = kWalks.fold<double>(0, (s, w) => s + w.km);
    final totalCount = kWalks.length;
    final totalMinutes = kWalks.fold<int>(0, (s, w) => s + w.minutes);

    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(children: [
                _backBtn(context),
                const SizedBox(width: 14),
                const Text('산책 기록',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _summaryCard(totalKm, totalCount, totalMinutes),
                  const SizedBox(height: 14),
                  _recordButton(context),
                  const SizedBox(height: 22),
                  const Text('전체 산책',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 12),
                  for (final w in kWalks) ...[_walkCard(w), const SizedBox(height: 12)],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _backBtn(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xB3FFFFFF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x80FFFFFF)),
          ),
          child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
        ),
      );

  // ── 이번 달 요약 ──────────────────────────────
  Widget _summaryCard(double totalKm, int totalCount, int totalMinutes) {
    Widget cell(String v, String label) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0x9E463C64))),
          ]),
        );
    Widget div() => Container(width: 1, height: 34, color: const Color(0x1F8C7BFF));

    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _warm,
              borderRadius: BorderRadius.circular(11),
              boxShadow: const [BoxShadow(color: Color(0x55FF7E8A), blurRadius: 12, offset: Offset(0, 5))],
            ),
            child: const Icon(Icons.pets, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('이번 달 산책',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          cell('${totalKm.toStringAsFixed(1)}km', '총 거리'),
          div(),
          cell('$totalCount회', '산책 횟수'),
          div(),
          cell('$totalMinutes분', '총 시간'),
        ]),
      ]),
    );
  }

  // ── 산책 기록하기 버튼 ────────────────────────
  Widget _recordButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateScreen())),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x66FF7E8A), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.add_location_alt_outlined, size: 21, color: Colors.white),
          SizedBox(width: 8),
          Text('산책 기록하기',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ── 산책 기록 카드 ───────────────────────────
  Widget _walkCard(WalkLog w) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _warm,
              boxShadow: const [BoxShadow(color: Color(0x40FF7E8A), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.directions_walk_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.place,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.calendar_today, size: 12.5, color: Color(0xA8463C64)),
                const SizedBox(width: 4),
                Text(w.date, style: const TextStyle(fontSize: 12, color: Color(0xA8463C64))),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          _stat(Icons.straighten, '${w.km.toStringAsFixed(1)}km'),
          const SizedBox(width: 8),
          _stat(Icons.schedule, '${w.minutes}분'),
          const SizedBox(width: 8),
          _stat(Icons.speed, w.pace),
        ]),
        if (w.memo.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(w.memo, style: const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xD13C345A))),
        ],
      ]),
    );
  }

  Widget _stat(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x14FF7E8A),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13.5, color: const Color(0xFFE07A4E)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
        ]),
      );
}
