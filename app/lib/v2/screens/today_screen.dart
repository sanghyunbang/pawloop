import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import 'main_shell.dart';
import 'walk_tracking_screen.dart';
import 'family_screen.dart';
import 'insight_screen.dart';

/// 홈 — 우리 아이 · 오늘 산책 · 근처 동반 장소. (감정 도메인 제거, 강아지 산책 중심)
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1), end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  String get _dateLabel {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final n = DateTime.now();
    return '${n.year}. ${n.month.toString().padLeft(2, '0')}. ${n.day.toString().padLeft(2, '0')} ${w[n.weekday - 1]}요일';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: ValueListenableBuilder<DogProfile>(
            valueListenable: kMyDog,
            builder: (_, dog, __) => Padding(
              padding: EdgeInsets.fromLTRB(22, 14, 22, MediaQuery.of(context).padding.bottom + 118),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_dateLabel,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: Color(0xBD463C69))),
                        const SizedBox(height: 6),
                        Text('${dog.name}랑\n산책 갈까요?',
                            style: const TextStyle(fontSize: 25, height: 1.25, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    const ProfileAvatar(),
                  ]),
                  // 히어로: 우리 아이 + 오늘 산책 요약(0부터)
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _dogHero(dog),
                            const SizedBox(height: 16),
                            Text(dog.name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: T.textPrimary)),
                            const SizedBox(height: 4),
                            Text('${dog.breed} · ${dog.ageLabel} · ${dog.size.label}',
                                style: const TextStyle(fontSize: 13.5, color: Color(0xBD463C64))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightScreen())),
                    behavior: HitTestBehavior.opaque,
                    child: _walkSummary(const WalkToday()),
                  ),
                  const SizedBox(height: 12),
                  const _CareCard(),
                  const SizedBox(height: 12),
                  _ctas(context),
                  const SizedBox(height: 12),
                  _weatherCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dogHero(DogProfile dog) {
    return Container(
      width: 150,
      height: 150,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Color(0xFFFFE7D2), Color(0xFFFFD0C0)]),
        boxShadow: [BoxShadow(color: Color(0x55FF9E7D), blurRadius: 34, offset: Offset(0, 16))],
      ),
      child: Image.asset(dog.avatarAsset, width: 96, height: 96, gaplessPlayback: true),
    );
  }

  Widget _walkSummary(WalkToday w) {
    Widget cell(String v, String label) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0x9E463C64))),
          ]),
        );
    Widget div() => Container(width: 1, height: 30, color: const Color(0x1F8C7BFF));
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      child: Row(children: [
        cell('${w.count}회', '오늘 산책'),
        div(),
        cell('${w.km.toStringAsFixed(1)}km', '거리'),
        div(),
        cell('${w.minutes}분', '시간'),
      ]),
    );
  }

  Widget _ctas(BuildContext context) {
    return Row(children: [
      Expanded(
        flex: 3,
        child: _btn(
          icon: Icons.pets,
          label: '산책 시작',
          gradient: _warm,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalkTrackingScreen())),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        flex: 2,
        child: _btn(
          icon: Icons.map_outlined,
          label: '코스 찾기',
          gradient: null,
          onTap: () => RootTab.index.value = 1, // 지도 탭
        ),
      ),
    ]);
  }

  Widget _btn({required IconData icon, required String label, required Gradient? gradient, required VoidCallback onTap}) {
    final filled = gradient != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: gradient,
          color: filled ? null : const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: filled ? Colors.transparent : const Color(0x80FFFFFF)),
          boxShadow: filled
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 8))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: filled ? Colors.white : T.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: filled ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
  }

  Widget _weatherCard() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0x22FFB74D), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFA726), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('산책하기 좋은 날씨예요', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            SizedBox(height: 3),
            Text('맑음 · 24°C · 미세먼지 보통', style: TextStyle(fontSize: 12, color: Color(0x9E463C64))),
          ]),
        ),
      ]),
    );
  }
}

/// 오늘의 케어 — 가족 공유(물·밥·산책). 탭하면 완료 토글, 헤더로 가족 화면 진입.
class _CareCard extends StatefulWidget {
  const _CareCard();
  @override
  State<_CareCard> createState() => _CareCardState();
}

class _CareCardState extends State<_CareCard> {
  void _toggle(CareTask t) {
    setState(() {
      t.done = !t.done;
      if (t.done) {
        final n = DateTime.now();
        t.by = '나';
        t.time = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
      } else {
        t.by = null;
        t.time = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.diversity_1_rounded, size: 17, color: Color(0xFFFF8F63)),
          const SizedBox(width: 6),
          const Text('오늘의 케어', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
            behavior: HitTestBehavior.opaque,
            child: Row(children: const [
              Text('우리 가족', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
              Icon(Icons.chevron_right, size: 16, color: Color(0xFFE07A4E)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (int i = 0; i < kCareToday.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _item(kCareToday[i])),
          ],
        ]),
      ]),
    );
  }

  Widget _item(CareTask t) {
    final c = careColor(t.type);
    return GestureDetector(
      onTap: () => _toggle(t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: t.done ? c.withValues(alpha: 0.13) : const Color(0xB3FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.done ? c.withValues(alpha: 0.35) : const Color(0x66FFFFFF)),
        ),
        child: Column(children: [
          Icon(t.done ? Icons.check_circle_rounded : careIcon(t.type), size: 19, color: t.done ? c : T.textMuted),
          const SizedBox(height: 4),
          Text(t.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const SizedBox(height: 2),
          Text(t.done ? '${t.by} · ${t.time}' : '아직',
              style: TextStyle(fontSize: 10, color: t.done ? c : T.textMuted)),
        ]),
      ),
    );
  }
}
