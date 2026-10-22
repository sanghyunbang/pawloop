import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../data/pet_sync.dart';
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
import 'display_name_screen.dart';
import 'edit_screen.dart';
import 'myrecords_screen.dart';
import 'login_screen.dart';
import 'main_shell.dart' show RootTab;
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
  /// 로그인 전이거나, 아직 한 마리도 등록하지 않았거나, **서버를 못 불렀을 때**다.
  ///
  /// 셋 중 앞의 둘은 할 일이 같다(로그인하고 등록하기). **셋째는 다르다**(#568) — 아이는
  /// 이미 있고 목록만 못 읽은 것이라, 여기서 등록을 권하면 같은 아이가 두 마리가 되고
  /// 케어 기록이 둘로 갈린다. #563 이 막으려던 것이 정확히 그것이라 따로 가른다.
  Widget _emptyState(BuildContext context) => ValueListenableBuilder<PetsLoad>(
      valueListenable: kPetsLoad,
      builder: (_, __, ___) => ValueListenableBuilder<AuthStatus>(
        valueListenable: AuthState.status,
        builder: (_, status, __) {
          // 로그인 전에는 "등록" 이 아니라 "로그인" 이 주 동작이다 — 등록은 로그인 없이는
          // 안 되는데 그걸 주 버튼으로 두면 사용자가 벽에 부딪힌다(#324).
          final guest = status == AuthStatus.unauthenticated;
          // "없다" 와 "못 읽었다" 를 나눈다(#568). 못 읽은 화면이 등록을 권하면 같은 아이가
          // 두 마리가 되고 케어 기록이 둘로 갈린다 — #563 이 막으려던 것이다.
          final unknown = !guest && kPetsLoad.value == PetsLoad.failed;
          // 아직 읽는 중이면 아무 말도 안 한다 — "없어요" 도 "못 읽었어요" 도 틀리다.
          final quiet = !guest && kPetsLoad.value == PetsLoad.loading;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 40, 22, 28),
            children: [
              Center(
                child: Image.asset('assets/emoji/paw.png',
                    width: 72, height: 72, gaplessPlayback: true),
              ),
              const SizedBox(height: 18),
              if (quiet)
                const SizedBox.shrink(key: Key('me-empty-quiet'))
              else ...[
              Text(
                guest
                    ? '로그인하면 우리 아이가 여기 있어요'
                    : (unknown ? '아이 목록을 불러오지 못했어요' : '아직 등록된 아이가 없어요'),
                key: const Key('me-empty-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                guest
                    // 로그인 제공자를 여기서 세지 않는다. 카카오·구글·Apple 셋인데 둘만 적혀
                    // 있었고(#544 로 Apple 이 들어온 뒤에도), 버튼은 어차피 하나다. 제공자가
                    // 늘거나 줄 때마다 고쳐야 하는 문장은 반드시 낡는다 — 실제로 낡아 있었다.
                    ? '아이를 등록하면 산책과 케어가 함께 남아요'
                    : (unknown
                        ? '등록한 아이가 있다면 그대로 있어요'
                        : '우리 아이를 등록하면 산책이 기록되기 시작해요'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: guest
                    ? () => loginThenHome(context)
                    : (unknown
                        ? () => petRevision.value++
                        : () => showPetRegistrationSheet(context)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(guest
                    ? '로그인 / 회원가입'
                    : (unknown ? '다시 시도' : '우리 아이 등록하기')),
              ),
              ],
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
      ));

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
    // 이름을 바꿔도 **상태는 그대로 authenticated** 라 status 만 들으면 이 줄이 옛
    // 이름에 멈춘다. 내용이 바뀌었다는 신호를 함께 듣는다(#665).
    return ListenableBuilder(
      listenable: Listenable.merge([AuthState.status, AuthState.userRev]),
      builder: (_, __) => _accountText(AuthState.status.value),
    );
  }

  Widget _accountText(AuthStatus status) {
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
          // 아직 안 읽은 것과 못 읽은 것은 다른 말을 한다(#568).
          if (data.offline && !data.loading && !data.hasAnything) ...[
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

  /// "내 정보 수정" 한 줄 — 이슈 #665.
  ///
  /// **로그인한 사람에게만 보인다.** 표시 이름은 계정에 붙은 값이라 게스트에게는 바꿀
  /// 것이 없고, 눌러도 401 로 끝난다. 아이가 있든 없든 닿아야 해서 [_menuCard] 와
  /// [_accountCard] 가 같은 줄을 쓴다.
  ///
  /// 바로 위의 배너(아이 프로필 편집)와 헷갈리지 않게 **사람 아이콘**을 쓴다 — 그 배너는
  /// 우리 아이를, 이 줄은 나를 고친다.
  Widget _editMeRow(BuildContext context) => ValueListenableBuilder<AuthStatus>(
        valueListenable: AuthState.status,
        builder: (_, status, __) => status == AuthStatus.authenticated ||
                status == AuthStatus.onboarding
            ? _row(Icons.badge_outlined, '내 정보 수정',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DisplayNameScreen())))
            : const SizedBox.shrink(),
      );

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
            _editMeRow(context),
            _row(Icons.settings_outlined, '설정',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            _row(Icons.logout, '로그아웃', color: const Color(0xFFFF6B7E), border: false,
                onTap: () => _logout(context)),
          ]),
        ),
      );

  /// messenger 와 navigator 를 await 전에 잡는다 — 로그아웃은 네트워크를 타고,
  /// 그 사이 이 화면이 사라져 있을 수 있다.
  Future<void> _logout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await AuthState.logout();
    messenger.showSnackBar(const SnackBar(
      content: Text('로그아웃되었습니다'),
      duration: Duration(milliseconds: 1800),
    ));
    // **얹힌 화면을 걷는다.** 이 화면은 go_router 의 라우트가 아니라 셸 위에
    // `Navigator.push` 로 얹혀 있어서, 라우터가 자기 스택을 `/auth/login` 으로
    // 바꿔도 그 위에 그대로 선다 — 로그아웃을 눌렀는데 내 정보 화면이 남는다.
    // 어디로 갈지는 정하지 않는다. 길만 터 주면 라우터가 바꿔 둔 화면이 드러난다.
    // 탈퇴(`AccountDeleteScreen`)가 같은 이유로 같은 줄을 쓴다(#513).
    navigator.popUntil((route) => route.isFirst);
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
          _editMeRow(context),
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
                    onTap: () => loginThenHome(context)),
          ),
        ]),
      ),
    );
  }

  /// 메뉴 상단 배너.
  ///
  /// **남이 등록한 아이면 고치기로 안 간다**(#563). 가족이 아이를 함께 돌보기 시작하면서
  /// 이 자리에 남의 아이가 올 수 있게 됐는데, 그대로 두면 눌렀을 때 **편집 화면까지 갔다가
  /// 저장에서 404** 를 만난다. 누르기 전에 말해 주는 편이 낫다.
  ///
  /// 숨기지 않고 **이유를 적는 이유**는, 아이를 바꿀 때마다 메뉴 항목이 나타났다 사라지면
  /// 화면이 흔들리고 "왜 없지" 를 묻게 되기 때문이다. 대신 누를 수 없다는 것이 보이게
  /// 코랄 배너가 아니라 **조용한 줄**로 그린다 — 이 화면에서 코랄은 "누를 수 있다" 다.
  Widget _menuBanner(BuildContext context, DogProfile dog) {
    if (!dog.mine) return _notMyDogBanner(dog);
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
              // 등록 시트와 같은 말 — '견종' 은 강아지 말이라 고양이 집에는 틀린다(#719).
              Text('품종 · 나이 · 몸집을 수정할 수 있어요', style: TextStyle(fontSize: 12, color: T.cardBg)),
            ]),
          ),
          Icon(Icons.chevron_right, size: 20, color: Colors.white),
        ]),
      ),
    );
  }

  /// 남이 등록한 아이 — 돌볼 수는 있고 고칠 수는 없다(#563).
  ///
  /// 누가 등록했는지는 **안 적는다.** 계약이 주는 것은 "내 것인가" 하나이고(`Dog.mine`),
  /// 주인 id 를 싣지 않은 것이 그 결정이다 — 화면이 이름을 말하려면 서버가 답하지 않은
  /// 질문에 답해야 한다.
  Widget _notMyDogBanner(DogProfile dog) {
    return Container(
      key: const Key('not-my-dog-banner'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: T.line),
      ),
      child: Row(children: [
        const Icon(Icons.pets, size: 22, color: T.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dog.name}는 가족이 등록한 아이예요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textSecondary)),
            const SizedBox(height: 2),
            const Text('같이 돌볼 수 있어요. 정보 수정은 등록한 사람이 해요',
                style: TextStyle(fontSize: 12, color: T.textMuted)),
          ]),
        ),
      ]),
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

/// 프로필에서 시작한 로그인의 끝은 **홈**이다 (2026-09-21 — "로그인하면 또 프로필로 시작하냐").
///
/// 로그인 화면은 열었던 자리로 돌아온다. 산책 시작·글쓰기처럼 **하던 일을 이어야 하는** 자리에서는
/// 그게 맞다. 그런데 게스트 프로필은 로그인 말고 할 것이 없는 화면이라 돌아올 이유가 없다 —
/// "둘러보기" 가 홈으로 가는 것(#324)과 같은 이유다. 로그인을 안 하고 돌아왔으면 그대로 둔다.
Future<void> loginThenHome(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  // 로그인 화면은 pop 을 먼저 하고 completeLogin 을 부른다 — 여기서 바로 물으면 아직 authenticating 이다.
  await AuthState.settle();
  if (!context.mounted || !AuthState.isAuthenticated) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
  RootTab.index.value = 0;
}
