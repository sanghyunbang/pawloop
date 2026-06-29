import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/records_data.dart';
import '../widgets/aurora.dart';
import 'create_screen.dart';

/// 내 기록 (myRecords) — 감정 캘린더 + 전체 기록.
class MyRecordsScreen extends StatelessWidget {
  const MyRecordsScreen({super.key});

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
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
                const Text('내 기록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _calendarCard(),
                  const SizedBox(height: 14),
                  _writeButton(context),
                  const SizedBox(height: 20),
                  const Text('전체 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 12),
                  for (final r in kMyRecords) ...[_recordCard(r), const SizedBox(height: 14)],
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
          width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xB3FFFFFF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x80FFFFFF)),
          ),
          child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
        ),
      );

  // ── 감정 캘린더 ──────────────────────────────
  Widget _calendarCard() {
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text(kCalTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0x21FF7A59), borderRadius: BorderRadius.circular(11)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department, size: 15, color: Color(0xFFFF7A59)),
              const SizedBox(width: 3),
              Text('연속 $kCalStreak일', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFFF7A59))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        // 요일 헤더
        Row(children: [
          for (int i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(_weekdays[i],
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600,
                        color: i == 0 ? const Color(0xFFFF8A6E) : T.textMuted)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        _grid(),
      ]),
    );
  }

  Widget _grid() {
    // 앞 빈칸 + 1~30일
    final cells = <Widget>[];
    for (int i = 0; i < kCalLeadBlanks; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= kCalDays; d++) {
      cells.add(_dayCell(d));
    }
    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final week = cells.sublist(i, (i + 7).clamp(0, cells.length));
      while (week.length < 7) {
        week.add(const SizedBox());
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [for (final c in week) Expanded(child: Center(child: c))]),
      ));
    }
    return Column(children: rows);
  }

  Widget _dayCell(int d) {
    final emoIdx = kCalEmotions[d];
    final isToday = d == kCalToday;
    if (emoIdx != null) {
      final e = kEmotions[emoIdx];
      return Container(
        width: 34, height: 34, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: e.grad,
          shape: BoxShape.circle,
          border: isToday ? Border.all(color: const Color(0xFFFF7A59), width: 2.5) : null,
          boxShadow: [BoxShadow(color: e.c2.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Text('$d', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
      );
    }
    return Container(
      width: 34, height: 34, alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFF7A59), width: 2))
          : null,
      child: Text('$d', style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
    );
  }

  // ── 새 기록 쓰기 ─────────────────────────────
  Widget _writeButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateScreen())),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.7, 1), colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x73D89BFF), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.edit, size: 20, color: Colors.white),
          SizedBox(width: 8),
          Text('새 기록 쓰기', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ── 전체 기록 카드 ───────────────────────────
  Widget _recordCard(MyRecord r) {
    final from = kEmotions[r.from], to = kEmotions[r.to];
    final sunny = r.weather.contains('맑');
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: to.grad,
                boxShadow: [BoxShadow(color: to.c2.withOpacity(0.33), blurRadius: 10, offset: const Offset(0, 4))]),
            child: to.icon(22.4),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(r.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary))),
          const Icon(Icons.more_horiz, size: 20, color: Color(0xFFBBB3CC)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.calendar_today, size: 14, color: Color(0xA8463C64)),
          const SizedBox(width: 4),
          Text(r.date, style: const TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
          const SizedBox(width: 14),
          const Icon(Icons.place, size: 14, color: Color(0xA8463C64)),
          const SizedBox(width: 4),
          Text(r.loc, style: const TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _dot(from),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 15, color: Color(0xFFBBB3CC)),
          const SizedBox(width: 6),
          _dot(to),
          const SizedBox(width: 8),
          Text(r.from == r.to ? '${to.label} 유지' : '${from.label} → ${to.label}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A3550))),
          const Spacer(),
          Icon(sunny ? Icons.wb_sunny : Icons.cloud, size: 15, color: const Color(0xFFFF9E7D)),
          const SizedBox(width: 4),
          Text(r.weather, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: T.textSecondary)),
        ]),
        const SizedBox(height: 13),
        Text(r.story, style: const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xD13C345A))),
      ]),
    );
  }

  Widget _dot(Emotion e) => Container(
        width: 26, height: 26, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad,
            boxShadow: [BoxShadow(color: e.c2.withOpacity(0.33), blurRadius: 8, offset: const Offset(0, 3))]),
        child: e.icon(16.8),
      );
}
