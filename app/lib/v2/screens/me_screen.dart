import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/pet_registration_sheet.dart';
import 'settings_screen.dart';
import 'saved_posts_screen.dart';
import 'dog_gallery_screen.dart';
import '../widgets/dog_avatar.dart';
import '../data/walk_feed.dart';
import '../widgets/walk_feed_builder.dart';
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
  /// 테스트에서 갈아 끼운다 — 로그인 상태의 화면을 서버 없이 세우기 위해서다(#332).
  final WalkFeed? feed;

  const MeScreen({super.key, this.feed});

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
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
                      color: T.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: T.cardBorder),
                    ),
                    child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('내 프로필', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ValueListenableBuilder<DogProfile?>(
                valueListenable: kMyDog,
                // 아이가 없으면 지어내지 않는다. 예전에는 '보리' 가 하드코딩돼 있어서
                // 서버에 0마리인 사람에게도 프로필이 있는 것처럼 보였다 (#159).
                builder: (_, dog, __) => dog == null
                    ? _emptyState(context)
                    : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                  children: [
                    _dogHeader(dog),
                    const SizedBox(height: 10),
                    _accountLine(),
                    const SizedBox(height: 16),
                    _petsRow(context, dog),
                    const SizedBox(height: 16),
                    _statsCard(context),
                    const SizedBox(height: 16),
                    _locationCard(),
                    const SizedBox(height: 16),
                    _menuCard(context, dog),
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
  /// 등록된 아이가 없을 때. **지어낸 프로필을 보여 주지 않는다.**
  ///
  /// 로그인 전이거나, 아직 한 마리도 등록하지 않았거나, 서버를 못 불렀을 때다.
  /// 셋을 구분하지 않는 이유: 사용자가 할 일은 셋 다 같다 — 로그인하고 등록하는 것이다.
  Widget _emptyState(BuildContext context) => ValueListenableBuilder<AuthStatus>(
        valueListenable: AuthState.status,
        builder: (_, status, __) {
          // 로그인 전에는 "등록" 이 아니라 "로그인" 이 주 동작이다 — 등록은 로그인 없이는
          // 안 되는데 그걸 주 버튼으로 두면 사용자가 벽에 부딪힌다(#324).
          final guest = status == AuthStatus.unauthenticated;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 40, 22, 28),
            children: [
              Center(
                child: Image.asset('assets/emoji/paw.png',
                    width: 72, height: 72, gaplessPlayback: true),
              ),
              const SizedBox(height: 18),
              Text(
                guest ? '로그인하면 우리 아이가 여기 있어요' : '아직 등록된 아이가 없어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                guest
                    ? '카카오나 Google 로 시작하고 우리 아이를 등록해요'
                    : '우리 아이를 등록하면 산책이 기록되기 시작해요',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: guest
                    ? () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const LoginScreen()))
                    : () => showPetRegistrationSheet(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(guest ? '로그인 / 회원가입' : '우리 아이 등록하기'),
              ),
              const SizedBox(height: 16),
              _accountLine(),
              // 아이가 없어도 설정·로그아웃은 닿아야 한다(#371).
              // **게스트도 설정에는 닿아야 한다**(#404) — 약관은 스토어가 앱 안에서 볼 수
              // 있기를 요구하고(#165), 내 동네(#342)와 저녁 알림(#341)은 기기에만 사는
              // 값이라 계정과 상관이 없다. 로그아웃만 뺀다 — 로그인한 적이 없다.
              const SizedBox(height: 22),
              guest ? _settingsOnlyCard(context) : _accountCard(context),
            ],
          );
        },
      );

  Widget _dogHeader(DogProfile dog) {
    return Column(children: [
      // 원형 그라데이션 배경 위 강아지 아바타
      Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [T.glowStart, T.glowEnd]),
          boxShadow: [BoxShadow(color: T.sigGlow, blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: DogAvatar(dog: dog, size: 96, emojiSize: 62),
      ),
      const SizedBox(height: 14),
      Text(dog.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: T.textPrimary)),
      const SizedBox(height: 5),
      Text(dog.subtitle,
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary)),
      // 아이 사진첩 (#451 5번) — 이 아이가 찍힌 커뮤니티 글. 서버에 있는 아이만.
      if (dog.serverId != null) ...[
        const SizedBox(height: 10),
        Builder(
          builder: (context) => GestureDetector(
          key: const Key('dog-gallery-open'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => DogGalleryScreen(dog: dog))),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: T.accentLine),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.photo_library_outlined, size: 15, color: T.accent),
              const SizedBox(width: 5),
              Text('${dog.name}의 사진첩',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ]),
          ),
          ),
        ),
      ],
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
          // 'local' 같은 내부 제공자 이름이 그대로 보였다(#332). 사람 말로 바꾼다.
          final provider = providerLabel(user.provider);
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
  Widget _petsRow(BuildContext context, DogProfile dog) {
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
                          gradient: const RadialGradient(colors: [T.glowStart, T.glowEnd]),
                          border: Border.all(
                            color: i == kSelectedPetIdx.value ? T.warmMid : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: DogAvatar(dog: pets[i], size: 54, emojiSize: 32),
                      ),
                      const SizedBox(height: 6),
                      Text(pets[i].name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: i == kSelectedPetIdx.value ? FontWeight.w800 : FontWeight.w600,
                            color: i == kSelectedPetIdx.value ? T.warmText : T.textSecondary,
                          )),
                    ]),
                  ),
                ),
              // 새 아이 추가
              GestureDetector(
                // 예전에는 '새 친구' 라는 가짜 프로필을 로컬에 만들고 편집 화면을 열었다.
                // 그 아이는 서버에 없으므로 산책을 붙일 수 없었다 (#159).
                onTap: () => showPetRegistrationSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Column(children: [
                  Container(
                    width: 54, height: 54, alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: T.surface,
                      border: Border.all(color: T.warmStart.withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: const Icon(Icons.add, size: 24, color: T.warmText),
                  ),
                  const SizedBox(height: 6),
                  const Text('추가', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ───────────── 산책 활동 요약 ─────────────
  Widget _statsCard(BuildContext context) => WalkFeedBuilder(
      feed: feed,
        builder: (context, data, _) => _statsCardOf(context, data),
      );

  /// 총 산책 · 총 거리 · 이번주. **셋 다 한 번의 호출로 온다** — 계약의 `WalkStats` 가
  /// `allTime*` 과 `week*` 를 함께 싣는 이유가 이 카드다.
  Widget _statsCardOf(BuildContext context, WalkFeedData data) {
    final totalKm = data.stats.allTimeKm;
    final weekKm = data.stats.totalKm;
    final totalCount = data.stats.allTimeCount;

    Widget cell(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 12, color: T.textMuted)),
          ]),
        );
    Widget div() => Container(width: 1, height: 34, color: T.line);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRecordsScreen())),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(children: [
          Row(children: [
            cell('$totalCount회', '총 산책'),
            div(),
            cell('${totalKm.toStringAsFixed(1)}km', '총 거리'),
            div(),
            cell('${weekKm.toStringAsFixed(1)}km', '이번주'),
          ]),
          // 서버를 못 불렀는데 0 을 그냥 보여 주면 "한 번도 안 걸었다" 로 읽힌다 (#161).
          if (data.offline && !data.hasAnything) ...[
            const SizedBox(height: 10),
            const Text('기록을 불러오지 못했어요',
                style: TextStyle(fontSize: 11.5, color: T.textMuted)),
          ],
          const SizedBox(height: 12),
          Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.article_outlined, size: 14, color: T.warmMid),
            SizedBox(width: 5),
            Text('산책 기록 보기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
            SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 16, color: T.warmText),
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
                  style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
            ]),
          ),
          GestureDetector(
            // setPaused 는 디스크에 남긴다. 예전처럼 `paused.value` 에 직접 대입하면
            // 앱을 껐다 켤 때 중단이 풀렸다 — 사용자는 껐다고 믿는데 다시 켜진다.
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await LocationService.setPaused(!paused);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(!ok
                      ? '설정을 저장하지 못했어요'
                      : (!paused ? '위치 정보 이용을 일시 중단했어요' : '위치 정보 이용을 다시 시작했어요')),
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
                color: paused ? const Color(0xFFFF6B7E) : T.line,
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
  /// 메뉴 한 행 — [_menuCard] 와 아이가 없을 때의 [_accountCard] 가 같이 쓴다(#371).
  Widget _row(IconData icon, String label, {Color? color, bool border = true, VoidCallback? onTap}) {
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
          Icon(Icons.chevron_right, size: 20, color: color ?? T.textFaint),
        ]),
      ),
    );
  }

  /// 게스트의 설정 한 줄 — 로그아웃이 없다(#404).
  ///
  /// 전에는 게스트 프로필에 "로그인 / 회원가입" 버튼뿐이라 **약관도 내 동네도 알림도
  /// 열 방법이 없었다.** 셋 다 로그인과 상관없는 값이다.
  Widget _settingsOnlyCard(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(T.radius),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _row(Icons.settings_outlined, '설정', border: false,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ]),
        ),
      );

  /// 아이가 없어도 로그인한 계정에는 설정과 로그아웃이 있어야 한다(#371). 전에는 등록 안내뿐이라
  /// 로그아웃할 길이 없었다 — 한 기기를 가족이 나눠 쓰면 앱 데이터를 지워야 계정을 바꿀 수 있었다.
  Widget _accountCard(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(T.radius),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _row(Icons.settings_outlined, '설정',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            _row(Icons.logout, '로그아웃', color: const Color(0xFFFF6B7E), border: false,
                onTap: () => _logout(context)),
          ]),
        ),
      );

  /// messenger 를 await 전에 잡는다 — 로그아웃은 네트워크를 타고, 그 사이 이 화면이 사라져 있을 수 있다.
  Future<void> _logout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await AuthState.logout();
    messenger.showSnackBar(const SnackBar(
      content: Text('로그아웃되었습니다'),
      duration: Duration(milliseconds: 1800),
    ));
  }

  Widget _menuCard(BuildContext context, DogProfile dog) {
    Widget row(IconData icon, String label, {Color? color, bool border = true, VoidCallback? onTap}) =>
        _row(icon, label, color: color, border: border, onTap: onTap);

    return ClipRRect(
      borderRadius: BorderRadius.circular(T.radius),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          // "프로필 편집" 행은 뺐다 — 바로 위 배너와 같은 화면으로 갔다(#332).
          _menuBanner(context, dog),
          row(Icons.article_outlined, '내 산책 기록',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRecordsScreen()))),
          row(Icons.diversity_1_rounded, '우리 가족',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen()))),
          row(Icons.bar_chart_rounded, '산책 통계',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightScreen()))),
          // 저장한 글 — "내 사진첩" (#451 4번). #332 가 뺀 죽은 북마크 행의 자리에 진짜 기능이 들어왔다.
          row(Icons.bookmark_border_rounded, '저장한 글',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SavedPostsScreen()))),
          // 스토어 요건 셋이 이 줄 뒤에 있다 — 인앱 계정 삭제(Apple 5.1.1(v)),
          // 공개 연락처(1.2 · 채팅이 이미 UGC 다), 인앱 처리방침 링크(Play).
          // 화면은 예전부터 있었는데 여는 곳이 없었다 (#165).
          row(Icons.settings_outlined, '설정',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ValueListenableBuilder<AuthStatus>(
            valueListenable: AuthState.status,
            builder: (_, status, __) => status == AuthStatus.authenticated ||
                    status == AuthStatus.onboarding
                ? row(Icons.logout, '로그아웃', color: const Color(0xFFFF6B7E), border: false,
                    onTap: () => _logout(context))
                : row(Icons.login, '로그인 / 회원가입', color: const Color(0xFF5B8DEF), border: false,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()))),
          ),
        ]),
      ),
    );
  }

  // 메뉴 상단 따뜻한 배너 (프로필 편집 유도).
  Widget _menuBanner(BuildContext context, DogProfile dog) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditScreen(pet: dog))),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: T.warmEnd.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(children: const [
          Icon(Icons.pets, size: 22, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('우리 아이 정보 관리', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: 2),
              Text('견종 · 나이 · 크기를 수정할 수 있어요', style: TextStyle(fontSize: 12, color: T.cardBg)),
            ]),
          ),
          Icon(Icons.chevron_right, size: 20, color: Colors.white),
        ]),
      ),
    );
  }
}

/// 로그인 제공자 이름을 사람 말로. 모르는 값은 보여 주지 않는다(null) — 내부 이름을 그대로
/// 노출하던 것이 #332 의 "walker · local" 이다.
String? providerLabel(String? provider) => switch (provider) {
      'kakao' => '카카오로 로그인',
      'google' => 'Google 로 로그인',
      'apple' => 'Apple 로 로그인',
      'local' || 'email' => '이메일로 로그인',
      _ => null,
    };
