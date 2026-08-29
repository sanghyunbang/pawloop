import 'package:flutter/material.dart';
import 'package:heat_trip_flutter/core/analytics/analytics.dart';
import 'package:heat_trip_flutter/core/mood/mood.dart';
import '../../domain/models.dart';
import '../../state/foryou_vm.dart';
import 'input_screen.dart';

/// "오늘" 홈 — 1탭 무드 체크인 (F0-3).
///
/// 6개 무드 칩 중 하나 + 강도(1~5)만으로 위로/추천을 요청합니다.
/// PAD/에너지/사교 슬라이더는 "더 정확히(심화)" 경로([InputScreen])로 강등.
class TodayCheckIn extends StatefulWidget {
  final ForYouVM vm;
  const TodayCheckIn({super.key, required this.vm});

  @override
  State<TodayCheckIn> createState() => _TodayCheckInState();
}

class _TodayCheckInState extends State<TodayCheckIn> {
  static const _accent = Color(0xFFFB6A3E);
  static const _accentSoft = Color(0xFFFFE7E0);
  static const _ink = Color(0xFF342D2A);
  static const _sub = Color(0xFF7B6E67);
  static const _border = Color(0xFFEBD9D2);

  Mood? _mood;
  int _intensity = 3;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    // 직전 입력이 있으면 무드 복원.
    _mood = Moods.byKey(widget.vm.request.moodKey);
    _startedAt = DateTime.now();
    Analytics.log(Analytics.evMoodCheckinStarted);
  }

  bool get _canSubmit => _mood != null;

  void _submit() {
    final mood = _mood;
    if (mood == null) return;

    final (p, a, d) = mood.padFor(_intensity);
    final req = widget.vm.request.copyWith(
      pad: Pad(pleasure: p, arousal: a, dominance: d),
      energy: mood.energy,
      socialNeed: mood.social,
      moodKey: mood.key,
      moodEmoji: mood.emoji,
    );

    final elapsedMs = _startedAt == null
        ? null
        : DateTime.now().difference(_startedAt!).inMilliseconds;
    Analytics.log(Analytics.evMoodCheckinCompleted, {
      'mood': mood.key,
      'intensity': _intensity,
      'elapsed_ms': elapsedMs,
      'path': 'quick',
    });

    widget.vm.submit(req);
  }

  Future<void> _openAdvanced() async {
    Analytics.log(Analytics.evMoodCheckinAdvanced);
    // 빠른 선택값을 심화 입력의 초기값으로 넘김.
    var initial = widget.vm.request;
    final mood = _mood;
    if (mood != null) {
      final (p, a, d) = mood.padFor(_intensity);
      initial = initial.copyWith(
        pad: Pad(pleasure: p, arousal: a, dominance: d),
        energy: mood.energy,
        socialNeed: mood.social,
        moodKey: mood.key,
        moodEmoji: mood.emoji,
      );
    }
    final updated = await Navigator.of(context).push<RankRequest>(
      MaterialPageRoute(builder: (_) => InputScreen(initial: initial)),
    );
    if (updated != null) await widget.vm.submit(updated);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewPadding;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + pad.bottom),
        children: [
          const SizedBox(height: 4),
          const Text(
            '오늘의 마음',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '지금 가장 가까운 감정을 하나 골라주세요.\n작은 위로와 지금 갈 만한 곳을 찾아드릴게요.',
            style: TextStyle(fontSize: 13.5, color: _sub, height: 1.4),
          ),
          const SizedBox(height: 20),
          _moodGrid(),
          const SizedBox(height: 24),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _canSubmit ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !_canSubmit,
              child: _intensitySection(),
            ),
          ),
          const SizedBox(height: 28),
          _submitButton(),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _openAdvanced,
              child: const Text(
                '더 정확히 입력하기  →',
                style: TextStyle(
                  color: _sub,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moodGrid() {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.92,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: Moods.all.map((m) {
        final selected = _mood?.key == m.key;
        return GestureDetector(
          onTap: () => setState(() => _mood = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: selected ? _accentSoft : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? _accent : _border,
                width: selected ? 1.8 : 1.0,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(m.emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 8),
                Text(
                  m.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? _accent : _ink,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _intensitySection() {
    const labels = ['아주 약함', '약함', '보통', '강함', '아주 강함'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '감정의 세기',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                labels[_intensity - 1],
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(5, (i) {
            final level = i + 1;
            final on = level <= _intensity;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _intensity = level),
                child: Container(
                  margin: EdgeInsets.only(right: i == 4 ? 0 : 8),
                  height: 44,
                  decoration: BoxDecoration(
                    color: on ? _accent : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? _accent : _border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.white : _sub,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _canSubmit ? _accent : Colors.grey.shade300,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _canSubmit ? _submit : null,
        child: const Text(
          '오늘의 마음, 위로받기',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
        ),
      ),
    );
  }
}
