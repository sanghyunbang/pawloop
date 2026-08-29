import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../data/auth_state.dart';
import '../data/location_service.dart';
import 'edit_screen.dart';
import 'myrecords_screen.dart';
import 'login_screen.dart';
import 'family_screen.dart';
import 'insight_screen.dart';

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
                    const SizedBox(height: 10),
                    _accountLine(),
                    const SizedBox(height: 16),
                    _petsRow(context),
                    const SizedBox(height: 16),
                    _statsCard(context),
                    const SizedBox(height: 16),
                    _locationCard(),
                    const SizedBox(height: 16),
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

  // ───────────── 로그인한 계정 ─────────────

  /// 서버(`GET /auth/me`)가 알려준 닉네임을 띄운다 — 이슈 #12 완료 조건 1.
  ///
  /// 예전에는 앱이 "토큰이 있다" 는 것만 알았지 그 토큰이 누구 것인지 몰랐다.
  /// 그래서 로그인해도 이 자리에 보여 줄 것이 없었다.
  Widget _accountLine() {
    return ValueListenableBuilder<AuthStatus>(
      valueListenable: AuthState.status,
      builder: (_, status, __) {
        final user = AuthState.user;
        final String text;
        if (status == AuthStatus.unknown) {
          text = '계정 확인 중…';
        } else if (user != null) {
          final provider = user.provider;
          text = provider == null
              ? user.displayName
              : '${user.displayName} · $provider';
        } else if (status == AuthStatus.authenticated) {
          // 토큰은 있는데 프로필을 못 받은 상태(오프라인 시작).
          text = '로그인됨 · 프로필을 불러오지 못했어요';
        } else {
          text = '로그인하지 않았어요';
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle_outlined,
                size: 15, color: T.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: T.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────── 우리 아이들 (여러 마리 전환/추가) ─────────────
  Widget _petsRow(BuildContext context) {
    return ValueListenableBuilder<List<DogProfile>>(
      valueListenable: kMyPets,
      builder: (_, pets, __) => GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('우리 아이들', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(width: 6),
            Text('${pets.length}마리', style: const TextStyle(fontSize: 12, color: T.textMuted)),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (int i = 0; i < pets.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: () => selectPet(i),
                    child: Column(children: [
                      Container(
                        width: 54, height: 54, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(colors: [Color(0xFFFFE7D2), Color(0xFFFFD0C0)]),
                          border: Border.all(
                            color: i == kSelectedPetIdx.value ? const Color(0xFFFF8F63) : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Image.asset(pets[i].avatarAsset, width: 32, height: 32, gaplessPlayback: true),
                      ),
                      const SizedBox(height: 6),
                      Text(pets[i].name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: i == kSelectedPetIdx.value ? FontWeight.w800 : FontWeight.w600,
                            color: i == kSelectedPetIdx.value ? const Color(0xFFE07A4E) : T.textSecondary,
                          )),
                    ]),
                  ),
                ),
              // 새 아이 추가
              GestureDetector(
                onTap: () {
                  addPet(const DogProfile(name: '새 친구', breed: '', size: DogSize.small, ageMonths: 12));
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditScreen()));
                },
                behavior: HitTestBehavior.opaque,
                child: Column(children: [
                  Container(
                    width: 54, height: 54, alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x66FFFFFF),
                      border: Border.all(color: const Color(0xFFFFA96B).withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: const Icon(Icons.add, size: 24, color: Color(0xFFE07A4E)),
                  ),
                  const SizedBox(height: 6),
                  const Text('추가', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
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

  // ───────────── 위치 정보 설정 (위치정보법: 일시적 이용중지 기능) ─────────────
  Widget _locationCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: LocationService.paused,
      builder: (context, paused, __) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (paused ? const Color(0xFFFF6B7E) : const Color(0xFF57C98A)).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(paused ? Icons.location_off_rounded : Icons.location_on_rounded,
                size: 21, color: paused ? const Color(0xFFFF6B7E) : const Color(0xFF3EA772)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('위치 정보 수집 일시 중단',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
              const SizedBox(height: 3),
              Text(paused ? '중단됨 — 지도·산책 기록이 현위치를 쓰지 않아요' : '켜면 언제든 위치 이용을 멈출 수 있어요',
                  style: const TextStyle(fontSize: 11.5, color: Color(0x9E463C64))),
            ]),
          ),
          GestureDetector(
            onTap: () {
              LocationService.paused.value = !paused;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(!paused ? '위치 정보 이용을 일시 중단했어요' : '위치 정보 이용을 다시 시작했어요'),
                  duration: const Duration(milliseconds: 1600),
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 50, height: 30,
              padding: const EdgeInsets.all(3),
              alignment: paused ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: paused ? const Color(0xFFFF6B7E) : const Color(0x1F8C7BFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 24, height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white,
                  boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
              ),
            ),
          ),
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
          row(Icons.diversity_1_rounded, '우리 가족',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen()))),
          row(Icons.bar_chart_rounded, '산책 통계',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightScreen()))),
          row(Icons.bookmark_border, '북마크', onTap: () => snack('저장한 장소가 아직 없어요 · 지도에서 마음에 드는 곳을 담아보세요')),
          ValueListenableBuilder<AuthStatus>(
            valueListenable: AuthState.status,
            builder: (_, status, __) => status == AuthStatus.authenticated ||
                    status == AuthStatus.onboarding
                ? row(Icons.logout, '로그아웃', color: const Color(0xFFFF6B7E), border: false,
                    // messenger 를 await 전에 잡는다 — 로그아웃은 네트워크를 타고,
                    // 그 사이 이 화면이 사라져 있을 수 있다.
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await AuthState.logout();
                      messenger.showSnackBar(const SnackBar(
                        content: Text('로그아웃되었습니다'),
                        duration: Duration(milliseconds: 1800),
                      ));
                    })
                : row(Icons.login, '로그인 / 회원가입', color: const Color(0xFF5B8DEF), border: false,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()))),
          ),
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
