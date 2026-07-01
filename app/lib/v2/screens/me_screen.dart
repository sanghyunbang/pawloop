import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import 'edit_screen.dart';
import 'myrecords_screen.dart';

/// 프로필 (me) — 우리 아이(강아지) 프로필 + 산책 활동 요약 + 메뉴.
/// (감정 도메인 제거, 반려/산책 중심)
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

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
                GestureDetector(
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
                ),
                const SizedBox(width: 14),
                const Text('내 프로필', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ValueListenableBuilder<DogProfile>(
                valueListenable: kMyDog,
                builder: (_, dog, __) => ListView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                  children: [
                    _dogHeader(dog),
                    const SizedBox(height: 18),
                    _statsCard(context),
                    const SizedBox(height: 18),
                    _menuCard(context),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ───────────── 우리 아이 프로필 ─────────────
  Widget _dogHeader(DogProfile dog) {
    return Column(children: [
      // 원형 그라데이션 배경 위 강아지 아바타
      Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFFFFE7D2), Color(0xFFFFD0C0)]),
          boxShadow: [BoxShadow(color: Color(0x55FF9E7D), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Image.asset(dog.avatarAsset, width: 62, height: 62, gaplessPlayback: true),
      ),
      const SizedBox(height: 14),
      Text(dog.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: T.textPrimary)),
      const SizedBox(height: 5),
      Text('${dog.breed} · ${dog.ageLabel} · ${dog.size.label}',
          style: const TextStyle(fontSize: 13.5, color: Color(0xBD463C64))),
      if (dog.neutered) ...[
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF57C98A).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF3EA772)),
            SizedBox(width: 5),
            Text('중성화 완료', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3EA772))),
          ]),
        ),
      ],
    ]);
  }

  // ───────────── 산책 활동 요약 ─────────────
  Widget _statsCard(BuildContext context) {
    final totalKm = kWalks.fold<double>(0, (s, w) => s + w.km);
    final weekKm = kWeekKm.fold<double>(0, (s, v) => s + v);

    Widget cell(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
          ]),
        );
    Widget div() => Container(width: 1, height: 34, color: const Color(0x1F8C7BFF));

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRecordsScreen())),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(children: [
          Row(children: [
            cell('${kWalks.length}회', '총 산책'),
            div(),
            cell('${totalKm.toStringAsFixed(1)}km', '총 거리'),
            div(),
            cell('${weekKm.toStringAsFixed(1)}km', '이번주'),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.article_outlined, size: 14, color: Color(0xFFFF8F63)),
            SizedBox(width: 5),
            Text('산책 기록 보기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
            SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 16, color: Color(0xFFE07A4E)),
          ]),
        ]),
      ),
    );
  }

  // ───────────── 메뉴 ─────────────
  Widget _menuCard(BuildContext context) {
    Widget row(IconData icon, String label, {Color? color, bool border = true, VoidCallback? onTap}) {
      final c = color ?? T.textPrimary;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          decoration: BoxDecoration(border: border ? const Border(bottom: BorderSide(color: Color(0x1A8C7BFF))) : null),
          child: Row(children: [
            Icon(icon, size: 21, color: color ?? T.textSecondary),
            const SizedBox(width: 13),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c))),
            Icon(Icons.chevron_right, size: 20, color: color ?? const Color(0xFFBBB3CC)),
          ]),
        ),
      );
    }

    void snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1800)),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(T.radius),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _menuBanner(context),
          row(Icons.pets_outlined, '프로필 편집',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditScreen()))),
          row(Icons.article_outlined, '내 산책 기록',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRecordsScreen()))),
          row(Icons.bookmark_border, '북마크', onTap: () => snack('저장한 장소가 아직 없어요 · 지도에서 마음에 드는 곳을 담아보세요')),
          row(Icons.logout, '로그아웃', color: const Color(0xFFFF6B7E), border: false, onTap: () => snack('로그아웃되었습니다')),
        ]),
      ),
    );
  }

  // 메뉴 상단 따뜻한 배너 (프로필 편집 유도).
  Widget _menuBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditScreen())),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFFFF7E8A).withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(children: const [
          Icon(Icons.pets, size: 22, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('우리 아이 정보 관리', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: 2),
              Text('견종 · 나이 · 크기를 수정할 수 있어요', style: TextStyle(fontSize: 12, color: Color(0xE6FFFFFF))),
            ]),
          ),
          Icon(Icons.chevron_right, size: 20, color: Colors.white),
        ]),
      ),
    );
  }
}
