import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/today_care_card.dart';
import '../widgets/walk_feed_builder.dart';
import '../data/walk_feed.dart';
import 'main_shell.dart';
import 'start_walk.dart';
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
                            Text('${dog.species.label} · ${dog.breed} · ${dog.ageLabel} · ${dog.size.label}',
                                style: const TextStyle(fontSize: 13.5, color: Color(0xBD463C64))),
                            if (kMyPets.value.length > 1) ...[
                              const SizedBox(height: 12),
                              _petSwitcher(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightScreen())),
                    behavior: HitTestBehavior.opaque,
                    // 예전에는 `const WalkToday()` 였다 — 무엇을 걷든 영원히 0회 0.0km 0분.
                    child: WalkFeedBuilder(
                      builder: (_, data) => _walkSummary(data),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TodayCareCard(
                    onOpenFamily: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FamilyScreen())),
                  ),
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

  /// 여러 마리 키울 때 아이 전환 스위처.
  Widget _petSwitcher() {
    final pets = kMyPets.value;
    final sel = kSelectedPetIdx.value;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (int i = 0; i < pets.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        GestureDetector(
          onTap: () => selectPet(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: i == sel ? const Color(0xFFFF8F63).withValues(alpha: 0.16) : const Color(0x80FFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: i == sel ? const Color(0xFFFF8F63) : const Color(0x66FFFFFF),
                width: i == sel ? 1.6 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset(pets[i].avatarAsset, width: 18, height: 18, gaplessPlayback: true),
              const SizedBox(width: 5),
              Text(pets[i].name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == sel ? FontWeight.w800 : FontWeight.w600,
                    color: i == sel ? const Color(0xFFE07A4E) : T.textSecondary,
                  )),
            ]),
          ),
        ),
      ],
    ]);
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

  Widget _walkSummary(WalkFeedData data) {
    final today = data.today;
    final pendingToday = data.pending.length;
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
      child: Column(children: [
        Row(children: [
          cell('${today.count}회', '오늘 산책'),
          div(),
          cell('${today.km.toStringAsFixed(1)}km', '거리'),
          div(),
          cell('${today.minutes}분', '시간'),
        ]),
        // 대기 중인 것이 있으면 말한다. 감추면 "저장됐는데 안 보인다" 가 된다.
        if (pendingToday > 0) ...[
          const SizedBox(height: 8),
          Text(
            '전송 대기 $pendingToday건 · 연결되면 올릴게요',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFE07A4E)),
          ),
        ] else if (data.offline && !data.hasAnything) ...[
          const SizedBox(height: 8),
          const Text(
            '기록을 불러오지 못했어요',
            style: TextStyle(fontSize: 11.5, color: Color(0x9E463C64)),
          ),
        ],
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
          // 미로그인이면 로그인부터 — 30분 걷고 나서 벽을 만나지 않게 한다.
          onTap: () => startWalk(context),
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
