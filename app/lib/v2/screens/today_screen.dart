import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../domain/walk_labels.dart';
import '../data/pet_sync.dart';
import '../data/auth_state.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/today_care_card.dart';
import '../widgets/today_course_card.dart';
import '../widgets/today_schedule_line.dart';
import '../widgets/weekly_report_reminder_sync.dart';
import '../widgets/walk_feed_builder.dart';
import '../widgets/emergency_vets_sheet.dart';
import '../widgets/walk_goal_row.dart';
import '../widgets/walk_reminder_sync.dart';
import '../widgets/walk_safety_card.dart';
import '../widgets/pet_registration_sheet.dart';
import '../data/walk_feed.dart';
import 'location_priming_sheet.dart';
import 'main_shell.dart';
import 'start_walk.dart';
import 'family_screen.dart';
import 'insight_screen.dart';
import '../widgets/dog_avatar.dart';
import '../widgets/neighbor_photo_strip.dart';

/// 홈 — 우리 아이 · 오늘 산책 · 근처 동반 장소. (감정 도메인 제거, 강아지 산책 중심)
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, this.feed});

  /// 산책 자료를 어디서 읽는가. **테스트만 넘긴다.**
  ///
  /// 이 자리가 없던 동안 홈의 요약 카드는 위젯 테스트가 불가능했다 — 안에서
  /// `WalkFeed()` 를 직접 만들어 진짜 네트워크를 탔다. `WalkFeedBuilder` 는 이미
  /// 같은 자리를 열어 두고 있었고(#161), 홈만 안 넘기고 있었다.
  final WalkFeed? feed;

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1), end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  String get _dateLabel {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final n = DateTime.now();
    return '${n.year}. ${n.month.toString().padLeft(2, '0')}. ${n.day.toString().padLeft(2, '0')} ${w[n.weekday - 1]}요일';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          // 아이 목록을 **읽어 봤는지**도 함께 듣는다(#568) — `kMyDog` 만 보면
          // "없다" · "아직 모른다" · "못 읽었다" 가 전부 같은 null 이다.
          child: ValueListenableBuilder<PetsLoad>(
            valueListenable: kPetsLoad,
            // 게스트는 목록을 **부른 적이 없다**. 그 사람에게 "불러오지 못했어요" 는
            // 틀린 말이라, 전처럼 "아직 등록된 아이가 없어요" 로 둔다(#324 · #568).
            builder: (_, rawPetsLoad, ___) => ValueListenableBuilder<DogProfile?>(
            valueListenable: kMyDog,
            builder: (_, dog, __) => _fitOrScroll(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // 날짜 줄도 달력의 문이다(#446) — 탭이 있어도 오늘 날짜를 누르면 오늘로 간다.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => openSchedule(context),
                          child: Semantics(
                            button: true,
                            label: '일정표 열기',
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              // Flexible 이 없으면 2.0배 글자에서 날짜가 Row 를 넘친다(셸 테스트가 잡았다).
                              Flexible(
                                child: Text(_dateLabel,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: T.textSecondary)),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.event_note_outlined, size: 15, color: T.textSecondary),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 아이가 없으면 이름을 지어내지 않는다. 예전에는 '보리' 가
                        // 하드코딩돼 있어서 등록도 안 한 사람에게 "보리랑 산책 갈까요?"
                        // 를 물었다 (#159).
                        Text(dog == null ? '오늘\n산책 갈까요?' : '${dog.name}랑\n산책 갈까요?',
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
                            // **셋을 나눈다**(#568). 못 읽은 화면이 등록을 권하면 같은
                            // 아이가 두 마리가 되고 케어 기록이 둘로 갈린다 — #563 이
                            // 막으려던 것이다. 아직 읽는 중이면 아무 말도 안 한다.
                            if (dog == null && petsLoad(rawPetsLoad) == PetsLoad.loading) ...[
                              const SizedBox.shrink(key: Key('pets-loading')),
                            ] else if (dog == null && petsLoad(rawPetsLoad) == PetsLoad.failed) ...[
                              const Text('아이 목록을 불러오지 못했어요',
                                  key: Key('pets-unknown'),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary)),
                              const SizedBox(height: 6),
                              const Text('등록한 아이가 있다면 그대로 있어요',
                                  style: TextStyle(fontSize: 13.5, color: T.textSecondary)),
                              const SizedBox(height: 10),
                              TextButton(
                                key: const Key('pets-retry'),
                                onPressed: () => petRevision.value++,
                                child: const Text('다시 시도'),
                              ),
                            ] else if (dog == null) ...[
                              const Text('아직 등록된 아이가 없어요',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary)),
                              const SizedBox(height: 6),
                              const Text('등록하면 산책이 기록되기 시작해요',
                                  style: TextStyle(fontSize: 13.5, color: T.textSecondary)),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () => showPetRegistrationSheet(context),
                                child: const Text('우리 아이 등록하기'),
                              ),
                            ] else ...[
                              Text(dog.name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: T.textPrimary)),
                              const SizedBox(height: 4),
                              Text(dog.subtitle,
                                  style: const TextStyle(fontSize: 13.5, color: T.textSecondary)),
                              if (kMyPets.value.length > 1) ...[
                                const SizedBox(height: 12),
                                _petSwitcher(),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // **히어로와 아래 카드 사이의 숨**. 히어로가 Expanded 라 남은 공간을 다 먹고,
                  // 그 안의 마지막 줄(아이 고르기 칩)이 카드 테두리에 그대로 붙었다 — 칩이
                  // 카드에 딸린 것처럼 읽힌다(사장님이 실기기에서 보고 알려 주셨다).
                  //
                  // Expanded 위에 두므로 화면이 좁아도 이 간격이 먼저 줄지 않는다 — 줄어드는
                  // 것은 히어로 쪽이고, 그쪽은 FittedBox 가 알아서 줄인다.
                  const SizedBox(height: 14),
                  // 산책 자료는 한 번만 받는다 — 요약과 "오늘의 코스"(#485)가 같은 자료를 쓴다.
                  // 그 사이의 케어 · 일정 · CTA 는 자료가 필요 없지만 순서 때문에 같은 열에 둔다.
                  WalkFeedBuilder(
                    feed: feed,
                    // **고른 아이의 숫자만 센다**(#563). 이게 없으면 목표는 이 아이의 것인데
                    // 채우는 분은 집 전체 산책이라, 히어로가 뭉치인데 "3/225분" 의 3 은 보리와
                    // 걸은 것이 된다. 아이가 하나인 집에서는 지금과 같은 숫자다.
                    dogId: dog?.serverId,
                    builder: (_, data, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightScreen())),
                          behavior: HitTestBehavior.opaque,
                          // 예전에는 `const WalkToday()` 였다 — 무엇을 걷든 영원히 0회 0.0km 0분.
                          child: _walkSummary(data, dog),
                        ),
                        const SizedBox(height: 12),
                        TodayCareCard(
                          onOpenFamily: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const FamilyScreen())),
                          // "만들기" 는 이름 시트까지 한 번에(#329).
                          onCreateFamily: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const FamilyScreen(openCreate: true))),
                        ),
                        // 오늘 할 일 한 줄 — 케어 카드 **아래**다(#420). 케어는 "이미 한 것",
                        // 이 줄은 "앞으로 할 것" 이라 시간 순서가 그렇다. 없으면 줄 자체가 없다.
                        TodayScheduleLine(
                          onOpen: () => openSchedule(context),
                        ),
                        const SizedBox(height: 12),
                        _ctas(context),
                        // 오늘의 코스(#485) — 산책 시작 버튼 바로 아래. 규칙으로 고른 하나와 "다른 코스".
                        TodayCourseCard(
                          dog: dog,
                          data: data,
                          onStart: (context, place, destination) =>
                              startWalk(context, place: place, destination: destination),
                        ),
                      ],
                    ),
                  ),
                  // 이웃의 사진 한 줄 — 홈에서 커뮤니티 사진 벽으로 가는 문(#451 6번). 사진 있는
                  // 글이 없거나 못 불러오면 줄 자체가 없다.
                  NeighborPhotoStrip(onMore: () {
                    RootTab.communityView.value = 'grid';
                    RootTab.index.value = 3;
                  }),
                  // 하드코딩 "맑음 · 24°C" 가 있던 자리(#326). 지금은 기상청·에어코리아 값으로 판정한
                  // 산책 안전 지수 한 줄이고, 키·위치·응답이 없으면 카드 자체가 없다(#336).
                  WalkSafetyCard(onAskLocation: askLocationPermission),
                  // 급할 때 — 페르소나 P1 의 실패비용이 "아플 때 근처 병원을 못 찾음" 이다(#337).
                  // 목록도 지도도 아니고 전화까지 두 번 만에 닿게 둔다.
                  _emergency(context),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// 게스트에게는 늘 "읽었다" 다 — 목록을 부른 적이 없으니 못 읽은 것도 아니다(#568).
  static PetsLoad petsLoad(PetsLoad raw) =>
      AuthState.isAuthenticated ? raw : PetsLoad.loaded;

  /// 들어가면 지금 모양 그대로, 안 들어가면 스크롤로 받는다 — 이슈 #396.
  ///
  /// 홈은 `Column` 하나로 서 있고 히어로가 `Expanded` 로 남는 자리를 먹는다. 그 구조는
  /// 글자 크기가 1.0배일 때만 맞는다 — 사용자가 기기 글자 크기를 키우면 아래 카드들이
  /// 자라는데 줄 자리가 없어 **노란 줄무늬**가 뜬다(360dp 에서 1.5배 13px · 2.0배 312px).
  ///
  /// 그렇다고 통째로 `SingleChildScrollView` 에 넣으면 높이가 무한이 되어 `Expanded` 가
  /// 죽는다. 그래서 **뷰포트만큼을 최소 높이로 걸고** 그 안에서만 `Expanded` 를 살린다 —
  /// 들어갈 때는 예전과 같은 화면이고, 안 들어갈 때만 스크롤이 생긴다.
  ///
  /// 잘라내지 않는 이유: 맨 아래가 "급할 때 · 가까운 동물병원"(#337)이다. 잘리면 아플 때
  /// 닿아야 하는 자리가 화면 밖으로 나간다.
  Widget _fitOrScroll(BuildContext context, {required Widget child}) {
    const top = 14.0;
    final bottom = MediaQuery.of(context).padding.bottom + 118;
    return LayoutBuilder(
      builder: (context, viewport) {
        final room = viewport.maxHeight.isFinite ? viewport.maxHeight - top - bottom : 0.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, top, 22, bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: room > 0 ? room : 0),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }

  /// 여러 마리 키울 때 아이 전환 스위처.
  Widget _petSwitcher() {
    final pets = kMyPets.value;
    final sel = kSelectedPetIdx.value;
    return Row(
        key: const Key('pet-switcher'), mainAxisSize: MainAxisSize.min, children: [
      for (int i = 0; i < pets.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        GestureDetector(
          onTap: () => selectPet(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: i == sel ? T.warmMid.withValues(alpha: 0.16) : T.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: i == sel ? T.warmMid : T.cardBorder,
                width: i == sel ? 1.6 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              DogAvatar(dog: pets[i], size: 18, emojiSize: 18),
              const SizedBox(width: 5),
              Text(pets[i].name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == sel ? FontWeight.w800 : FontWeight.w600,
                    color: i == sel ? T.warmText : T.textSecondary,
                  )),
            ]),
          ),
        ),
      ],
    ]);
  }

  /// 아이가 없으면 발바닥 아이콘을 그린다 — 남의 강아지를 보여 주지 않는다.
  Widget _dogHero(DogProfile? dog) {
    return Container(
      width: 150,
      height: 150,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [T.glowStart, T.glowEnd]),
        boxShadow: [BoxShadow(color: T.sigGlow, blurRadius: 34, offset: Offset(0, 16))],
      ),
      // 사진을 등록한 아이는 사진이 히어로다(#448) — 이모지는 사진이 없을 때만.
      child: DogAvatar(dog: dog, size: 150, emojiSize: 96),
    );
  }

  Widget _walkSummary(WalkFeedData data, DogProfile? dog) {
    final today = data.today;
    final pendingToday = data.pending.length;
    final unknown = data.numbersUnknown;
    Widget cell(String v, String label) => Expanded(
          child: Column(children: [
            Text(v,
                // `—` 는 낭독기가 읽지 않는다 — 눈으로는 "모른다" 인데 귀로는 빈칸이다.
                // 그러면 화면을 못 보는 사람에게는 고치기 전과 똑같이 "0" 과 구별이 안 된다.
                semanticsLabel: v == '—' ? '$label 모름' : null,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
          ]),
        );
    Widget div() => Container(width: 1, height: 30, color: T.line);
    return GlassCard(
      key: const Key('walk-summary'),
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      child: Column(children: [
        Row(children: [
          // 모르는 값은 0 이 아니라 `—` 다(#568). `0회` 는 "안 걸었다" 는 **주장**이고,
          // 바로 아래 "불러오지 못했어요" 와 같은 화면에 있으면 서로 다른 말을 한다.
          cell(unknown ? '—' : '${today.count}회', '오늘 산책'),
          div(),
          cell(unknown ? '—' : '${today.km.toStringAsFixed(1)}km', '거리'),
          div(),
          cell(unknown ? '—' : walkTimeLabel(today.durationS), '시간'),
        ]),
        // 로그인한 적 없는 사람에게는 "불러오지 못했다" 가 아니라 "로그인하면" 이다(#324).
        if (data.guest) ...[
          const SizedBox(height: 8),
          const Text(
            '로그인하면 오늘 산책이 여기 쌓여요',
            style: TextStyle(fontSize: 11.5, color: T.textMuted),
          ),
        ]
        // 대기 중인 것이 있으면 말한다. 감추면 "저장됐는데 안 보인다" 가 된다.
        else if (pendingToday > 0) ...[
          const SizedBox(height: 8),
          Text(
            '전송 대기 $pendingToday건 · 연결되면 올릴게요',
            style: const TextStyle(fontSize: 11.5, color: T.warmText),
          ),
        // **아직 안 읽은 것과 못 읽은 것을 나눈다**(#568). 나누기 전에는 첫 프레임에서
        // 이 문장이 한 번 깜빡였다 — `WalkFeedData.empty` 가 `offline: true` 였다.
        ] else if (data.offline && !data.loading && !data.hasAnything) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Flexible(
              child: Text(
                '기록을 불러오지 못했어요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: T.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            // 지금은 화면을 떠났다 오는 것 말고 다시 읽을 길이 없다.
            GestureDetector(
              key: const Key('walk-feed-retry'),
              behavior: HitTestBehavior.opaque,
              onTap: () => walkFeedRevision.value++,
              child: const Text(
                '다시 시도',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: T.warmText),
              ),
            ),
          ]),
        ],
        // 이번 주 목표와 연속 일수 (#341). 아이가 없거나 개가 아니면 줄 자체가 없다 —
        // 산책 권장량은 개에 대한 자료라 고양이에게 제안하면 근거 없는 숫자가 된다.
        if (!data.guest) WalkGoalRow(dog: dog, data: data),
        // 아무것도 안 그린다 — 저녁 알림 예약을 이 자료에 맞춰 두는 자리다(#341).
        // 홈이 자료를 다시 읽는 순간이 곧 "다시 걸어야 하는 순간" 이라 여기 붙인다.
        WalkReminderSync(data: data, dogName: dog?.name),
        // 일요일 저녁 주간 정리 알림(#486 후속)도 같은 자리 — 앱을 열 때 한 번 건다.
        WeeklyReportReminderSync(guest: data.guest),
      ]),
    );
  }

  /// 글자를 키우면 두 버튼이 **위아래로** 선다 — 이슈 #396.
  ///
  /// 나란히 두면 좁은 쪽("코스 찾기")이 360dp 에서 1.5배부터 넘친다(2.0배 59px). 줄여서
  /// 넣거나 말줄임으로 자르는 길도 있지만, 글자를 키운 사람에게 글자를 다시 줄여 보이는
  /// 것은 설정을 무시하는 것이고 "코스 …" 는 무엇을 누르는지 알 수 없다. 한 줄에 하나씩
  /// 두면 폭이 두 배로 늘어 어떤 배율에서도 온전한 이름이 보인다.
  static const _stackButtonsFrom = 1.3;

  Widget _ctas(BuildContext context) {
    final walk = _btn(
      icon: Icons.pets,
      label: '산책 시작',
      gradient: _warm,
      // 미로그인이면 로그인부터 — 30분 걷고 나서 벽을 만나지 않게 한다.
      onTap: () => startWalk(context),
    );
    final course = _btn(
      icon: Icons.map_outlined,
      label: '코스 찾기',
      gradient: null,
      onTap: () => RootTab.index.value = 1, // 지도 탭
    );

    if (MediaQuery.textScalerOf(context).scale(15) >= 15 * _stackButtonsFrom) {
      return Column(children: [walk, const SizedBox(height: 11), course]);
    }
    return Row(children: [
      Expanded(flex: 3, child: walk),
      const SizedBox(width: 11),
      Expanded(flex: 2, child: course),
    ]);
  }

  /// "급할 때" 한 줄. 눈에 띄되 산책 시작을 가리지 않게 작다.
  Widget _emergency(BuildContext context) {
    const red = Color(0xFFD7263D);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => EmergencyVets.open(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0x0FD7263D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x26D7263D)),
          ),
          child: Row(children: [
            const Icon(Icons.local_hospital_rounded, size: 17, color: red),
            const SizedBox(width: 9),
            const Expanded(
              child: Text('급할 때 · 가까운 동물병원',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: red)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0x66D7263D)),
          ]),
        ),
      ),
    );
  }

  Widget _btn({required IconData icon, required String label, required Gradient? gradient, required VoidCallback onTap}) {
    final filled = gradient != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 높이를 못 박지 않는다 — 글자가 커지면 버튼이 함께 커진다(#396). 54 는 그대로
        // 최소값이라 1.0배 화면은 예전과 같다.
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: gradient,
          color: filled ? null : T.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: filled ? Colors.transparent : T.cardBorder),
          boxShadow: filled
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 8))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: filled ? Colors.white : T.textSecondary),
          const SizedBox(width: 8),
          // 위아래로 서지 않는 배율에서도 마지막 안전장치를 둔다 — 넘치면 줄무늬가 아니라
          // 말줄임이 낫다. 실제로는 _stackButtonsFrom 이 먼저 막는다.
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: filled ? Colors.white : T.textSecondary)),
          ),
        ]),
      ),
    );
  }

}

/// 일정 탭으로 간다. 홈의 날짜 줄과 "오늘 할 일" 줄이 이 문을 쓴다 — 일정은 탭이다(#446,
/// 사장님: "일정 탭은 필수").
void openSchedule(BuildContext context) => RootTab.index.value = 2;
