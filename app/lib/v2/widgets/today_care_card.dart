// lib/v2/widgets/today_care_card.dart
//
// "오늘의 케어" 카드 — 이슈 #76. 홈(`today_screen`)과 `family_screen` 이 같은 위젯을 쓴다.
//
// ## 이 카드가 막으려는 것
//
// 이중 급여(엄마가 밥을 줬는데 아빠가 또 준다)와 산책 누락(서로 상대가 다녀왔겠거니
// 한다). 둘 다 "오늘 누가 무엇을 했는지" 를 한 화면에 놓으면 사라진다 — 그래서 칸마다
// **누가·언제**를 함께 그린다. 체크 표시만 있으면 "내가 했나?" 를 지우지 못한다.
//
// ## 묻는 말은 앱이 만든다 (완료 조건 2)
//
// 서버는 같은 종류를 하루에 두 번 찍어도 **막지 않는다** — 두 번째가 실수인지 사실인지
// 서버는 모르고, 막으면 실제로 한 일이 기록에서 사라진다. 대신 여기서 한 장 묻는다.
//
// **"그래도 기록할까요?" 가 아니다** — 물은 하루에 몇 번이고 갈고, 밥은 두세 끼, 배변은
// 세는 값이다. 두 번째를 "중복" 이라 부르면 정상인 날마다 경고를 읽게 되고, 그러면
// 진짜 실수(아침 8시에 세 번째 밥)도 안 읽는다. 그래서 **사실 두 가지**를 놓고 묻는다:
// 마지막 기록이 누구·언제인지, 이번이 오늘 **몇 번째**인지 — "오늘 08:50 엄마가 물을
// 갈아줬어요. 이번이 오늘 2번째예요. 다음 기록을 남길까요?" (2026-09-20).
//
// 왜 앱인가: 확인 문구는 **쓰기 전에** 떠야 하므로 결국 읽기에서 나오고, 그 읽기는 이
// 카드가 이미 하고 있다(누가·언제를 그리려고). 응답에 "오늘 이미 있음" 필드를 더하면
// 같은 사실의 출처가 둘이 되고 둘이 어긋나는 날이 온다.
//
// ## 로딩·실패
//
// 네트워크가 없을 때 빈 카드를 그리면 "아무도 아무것도 안 했다" 로 읽힌다. 그건 이 화면이
// 낼 수 있는 가장 나쁜 거짓말이다 — 그걸 보고 밥을 한 번 더 준다. 그래서 로딩·실패·
// "가족 없음" 을 각각 다른 문구로 그린다.
//
// ## 일정과의 연결 (#741 · A 안)
//
// 산책·병원·투약은 일정 탭에도 있다. 카드에서 "병원 다녀왔다" 를 누르는데 오늘 같은 종류의
// 열린 일정이 있으면, 기록하기 **전에** "일정을 완료로 할까요?" 를 한 장 묻는다. 완료로 하면
// 일정을 PATCH 하고 **케어 기록은 안 보낸다** — 서버가 그 일정의 기록을 스스로 남기므로
// (`ScheduleService.syncCareLog`, 아이까지 #743) 여기서 또 보내면 두 번 남는다.
//
// 묻지 않고 자동으로 완료하지 않는 이유: 같은 날 같은 종류가 둘이면(아침 산책 · 저녁 산책)
// 어느 것을 끝낸 것인지 앱이 모른다. 시각이 빠른 것 하나를 놓고 묻는다 — 사용자가 안다.
// 일정을 못 읽은 날은 묻지 않고 기록만 한다. 일정은 이 카드의 곁다리라 케어를 막으면 안 된다.

import '../screens/care_log_screen.dart';
import '../screens/login_screen.dart';
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/family_repository.dart';
import '../data/schedule_repository.dart';
import '../domain/pet.dart' show kMyDog, kMyPets, kPetCategories;
import '../domain/schedule.dart';
import '../screens/main_shell.dart' show RootTab;
import '../theme/app_tokens.dart';
import 'care_glyph.dart';
import 'care_log_line.dart';
import 'aurora.dart';

/// 한 화면에서 기록하면 다른 화면의 카드도 다시 읽게 하는 신호.
///
/// 홈과 `family_screen` 이 같은 데이터를 그리는데 서로를 모른다. 값이 바뀌면 살아 있는
/// 카드가 전부 다시 읽는다 — `pet.dart` 의 `kCareRev` 가 로컬 더미에 대해 하던 일을
/// 서버 데이터에 대해 한다.
final ValueNotifier<int> kServerCareRev = ValueNotifier<int>(0);

/// 홈과 가족 화면이 함께 쓰는 "오늘의 케어" 카드.
class TodayCareCard extends StatefulWidget {
  /// 헤더 오른쪽의 "우리 가족 →" 을 눌렀을 때. 가족 화면 안에서는 null 이다.
  final VoidCallback? onOpenFamily;

  /// 테스트가 가짜 저장소를 꽂는 자리. 운영 경로에서는 null 이다.
  final FamilyRepository? repository;

  /// "내 기록인가" 를 가르는 id. 운영 경로에서는 null 이고 [AuthState.user] 를 읽는다 —
  /// 테스트가 로그인 상태를 만들지 않고도 본인/남 두 경우를 그리게 하려는 자리다.
  final int? myUserId;

  /// 가족이 없을 때 "만들기" 가 부른다. 없으면 [onOpenFamily] 로 간다 — 가족 화면에서
  /// 한 번 더 "가족 그룹 만들기" 를 눌러야 하는 두 단계였다(#329).
  final VoidCallback? onCreateFamily;

  /// 오늘 일정을 읽는 저장소(#741). 테스트가 갈아 끼우고, 운영 경로에서는 null 이다.
  final ScheduleRepository? scheduleRepository;

  /// "오늘" — 일정을 오늘 하루치만 묻는 데 쓴다. 테스트가 고정하지 않으면 기기 시계다.
  final DateTime? today;

  const TodayCareCard({
    super.key,
    this.onOpenFamily,
    this.repository,
    this.myUserId,
    this.onCreateFamily,
    this.scheduleRepository,
    this.today,
  });

  @override
  State<TodayCareCard> createState() => _TodayCareCardState();
}

class _TodayCareCardState extends State<TodayCareCard> {
  late final FamilyRepository _repo = widget.repository ?? FamilyRepository();
  late final ScheduleRepository _scheduleRepo =
      widget.scheduleRepository ?? ScheduleRepository();

  FamilyGroupSummary? _group;
  List<CareLogEntry> _logs = const [];

  /// 오늘 일정(#741). 산책·병원·투약 칸을 누를 때 "완료로 할까요?" 를 물을지 여기서 가른다.
  /// 못 읽었으면 빈 목록이고, 그때는 묻지 않는다.
  List<Schedule> _schedules = const [];

  /// 그 집이 챙기는 일 — **카드의 칸이 이 목록이다**(#560). 접힌 것은 빼고 순서대로다.
  List<CareItemEntry> _items = const [];

  FamilyFailureKind? _failure;
  bool _loading = true;

  /// 아직 토큰이 없는 사람. 서버를 부르지 않는다(#324·#673).
  ///
  /// 로그인한 적 없는 사람이 대부분이지만 **소셜 왕복 중**도 여기 들어온다. 그 사람은
  /// 지금 이 카드가 아니라 로그인 화면을 보고 있으므로, 뒤에 게스트 문구가 그려져 있어도
  /// 눈에 닿지 않는다. 왕복이 끝나면 상태 알림을 듣고 다시 읽는다.
  bool _guest = false;

  /// 기록을 보내는 중인 **항목 id**. 같은 칸을 두 번 눌러 두 번 보내는 것을 막는다.
  int? _sending;

  @override
  void initState() {
    super.initState();
    kServerCareRev.addListener(_reload);
    AuthState.status.addListener(_reload);
    // 고른 아이가 바뀌면 다시 읽는다(#563). 이 카드는 props 가 안 바뀌므로 홈이 다시
    // 그려도 State 가 그대로 살아 있다 — 신호를 직접 안 들으면 **앞 아이의 기록이 남는다.**
    kMyDog.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    kServerCareRev.removeListener(_reload);
    AuthState.status.removeListener(_reload);
    kMyDog.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    if (AuthState.hasNoToken) {
      // 게스트는 가족이 없는 게 아니라 아직 계정이 없다. 401 을 받아 "다시 로그인" 이라고
      // 말하는 대신 여기서 멈춘다(#324).
      //
      // **소셜 왕복 중에도 토큰은 없다**(#673). 이 카드는 상태 알림을 듣고 다시 읽으므로
      // `isGuest` 로 재면 소셜 버튼을 누른 그 순간 토큰 없는 요청이 나갔다. 그 401 이
      // 세션 만료로 번역되면서 로그인 화면이 통째로 사라졌다.
      setState(() {
        _guest = true;
        _loading = false;
      });
      return;
    }
    _guest = false;
    try {
      final group = _group ?? await _repo.myGroup();
      // **고른 아이의 기록만 센다**(#563). 이게 없으면 아이가 둘인 집에서 보리 이름 아래
      // 카드가 누리 밥까지 세고, "밥 2회" 가 보리한테 두 번인지 둘이 한 번씩인지 모르게 된다.
      final logs = await _repo.careLogs(group.id, dogId: kMyDog.value?.serverId);
      final items = await _itemsOf(group.id);
      final schedules = await _todaySchedules();
      if (!mounted) return;
      setState(() {
        _group = group;
        _logs = logs;
        _items = items;
        _schedules = schedules;
        _loading = false;
      });
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.kind;
        _loading = false;
      });
    }
  }

  /// 목록을 못 읽었을 때 그리는 기본 일곱.
  ///
  /// 서버가 어느 집에나 심어 두는 것과 같은 일곱이다(마이그레이션 50). id 를 음수로 두는
  /// 이유는 **진짜 항목과 절대 안 겹치게** 하려는 것이다 — 겹치면 `_belongsTo` 가 남의
  /// 기록을 이 칸에 붙인다. 이 항목들은 종류를 들고 있어서 옛 기록이 제 칸으로 간다.
  static final List<CareItemEntry> _fallbackItems = [
    for (final (index, type) in [
      (0, ServerCareType.water),
      (1, ServerCareType.meal),
      (2, ServerCareType.walk),
      (3, ServerCareType.med),
      (4, ServerCareType.vet),
      (5, ServerCareType.poop),
      (6, ServerCareType.pee),
    ])
      CareItemEntry(
        id: -1 - index,
        dogId: null,
        name: const ['물', '밥', '산책', '투약', '병원', '배변', '마킹'][index],
        icon: type.wire,
        systemType: type,
        dailyTarget: null,
        sortOrder: index,
        archivedAt: null,
      ),
  ];

  /// 그 집의 항목 — **못 읽으면 기본 일곱으로 그린다.**
  ///
  /// 목록을 못 읽었다고 카드를 비우면, 서버가 잠깐 흔들린 날 사용자는 "오늘 아무것도 안
  /// 했다" 가 아니라 **"케어라는 기능이 사라졌다"** 를 본다. 기본 일곱은 어느 집에나 있는
  /// 목록이라(마이그레이션 50 이 심었다) 그것으로 그리는 쪽이 덜 틀린다.
  ///
  /// 접힌 항목은 뺀다 — 그게 "접기" 의 뜻이다. 고치기 화면만 접힌 것을 본다.
  Future<List<CareItemEntry>> _itemsOf(int groupId) async {
    try {
      final items = await _repo.careItems(groupId);
      final live = items.where((item) => !item.archived).toList();
      return live.isEmpty ? _fallbackItems : live;
    } on FamilyFailure {
      return _fallbackItems;
    }
  }

  /// 오늘 일정 — **못 읽으면 빈 목록**이다(#741).
  ///
  /// 일정은 이 카드의 곁다리다. 일정 서버가 흔들린다고 케어 카드를 실패로 그리면 사용자는
  /// 물·밥을 못 적는다 — 홈의 할 일 줄이 같은 이유로 조용하다(`today_schedule_line.dart`).
  ///
  /// **아이로 거르지 않는다.** 아이 없는 가족 일정("병원" 만 적어 둔 것)도 물어야 하고, 어느
  /// 아이 것인지는 누를 때 [openScheduleFor] 가 가른다. 서버에 `dogId` 를 보내면 그 일정이
  /// 빠진다.
  Future<List<Schedule>> _todaySchedules() async {
    final now = widget.today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    try {
      return await _scheduleRepo.range(from: day, to: day);
    } on ScheduleFailure {
      return const [];
    }
  }

  /// 이 기록이 그 칸의 것인가 — **규칙은 서버가 이미 풀었다**(#560 조각 2).
  ///
  /// `careItemId` 가 있으면 그것 하나로 끝난다. 없는 경우는 둘뿐이다 — 조각 2 이전 서버와
  /// 얘기하고 있거나, 목록을 못 읽어 기본 일곱으로 그리는 중이다. 그때만 종류로 붙인다.
  /// <b>평상시에는 이 두 번째 갈래를 타지 않는다</b> — 타기 시작하면 세는 규칙이 서버와 앱
  /// 두 곳에 사는 것이라, 그 사실을 여기 적어 둔다.
  bool _belongsTo(CareLogEntry log, CareItemEntry item) => log.belongsTo(item);

  /// 그 칸의 **가장 최근** 기록. 없으면 null.
  ///
  /// 목록은 이른 것부터라 마지막이 최근이다. "오늘 이미 했다" 를 물을 때도, 칸에
  /// "누가·언제" 를 그릴 때도 이 하나를 쓴다 — 둘이 다른 행을 보면 확인 문구와 화면이
  /// 서로 다른 말을 한다.
  CareLogEntry? _latestOf(CareItemEntry item) {
    CareLogEntry? found;
    for (final log in _logs) {
      if (_belongsTo(log, item)) found = log;
    }
    return found;
  }

  /// 오늘 그 칸이 몇 번인가.
  int _countOf(CareItemEntry item) =>
      _logs.where((log) => _belongsTo(log, item)).length;

  /// 칸의 둘째 줄 — **한 줄에 하나만** 적는다. 셋 중 무엇을 적을지는 순서가 있다.
  ///
  /// 1. **아직 안 했으면** `아직`.
  /// 2. **두 번 이상이면 `N회`.** 하루 한 번이 아닌 것이 정상이다 — 밥 두 끼, 물 여러 번,
  ///    배변·마킹은 원래 세는 값이다(#549). 예전에는 배변·마킹만 횟수를 적어서, 밥을 두 번
  ///    준 날에도 칸은 마지막 사람 이름만 말했다. **두 번째를 막으려고 보는 자리인데 두 번
  ///    줬다는 사실이 화면에 없었다.**
  /// 3. **산책이고 거리가 있으면 거리.** 이름을 지우는 것이 아니다 — 남이 걸었으면 바로 위
  ///    한 줄이 "엄마가 아침에 1.2km 걸었어요" 로 이름을 말하고, 내가 걸었으면 이름이 나다.
  ///    거리는 이 칸 말고는 홈에 적을 자리가 없다.
  /// 4. 나머지는 **누가**. 물·밥은 두 번 주지 않으려고 보는 자리다.
  /// 5. **하루 목표가 있으면 `1/2`.** 목표를 적어 둔 집은 "몇 번 중 몇 번" 이 답이다 —
  ///    횟수만 적으면 두 번 줘야 하는 집에서 `1회` 가 끝난 것처럼 보인다. 못 채워도 아무
  ///    말도 안 한다: 이 카드는 누락을 보이게 하려는 것이지 혼내려는 것이 아니다.
  String _firstLine(CareItemEntry item, CareLogEntry? done) {
    final count = _countOf(item);
    final target = item.dailyTarget;
    if (target != null) return '$count/$target';
    if (done == null) return '아직';
    if (count >= 2) return '$count회';
    if (item.systemType == ServerCareType.walk && (done.memo ?? '').isNotEmpty) {
      return done.memo!;
    }
    return done.doneByName;
  }

  /// 칸의 **셋째 줄**. 한 번이면 시각, 두 번 이상이면 **한 사람들**이다 — 이슈 #570.
  ///
  /// `2회` 만 있으면 둘이 한 번씩인지 한 사람이 두 번인지 화면이 구별을 못 한다. 이 앱의
  /// 목적이 업무 분담이라 그 구별이 곧 화면의 값어치다(#76). 두 번 이상일 때 시각을 빼는
  /// 이유는, 어느 시각을 적어도 나머지를 숨기기 때문이다 — 시각 전부는 "오늘 한 일" 이 적는다.
  ///
  /// 이름이 길면 `아빠 외 1` 로 접는다. 칸 폭이 좁아서(#326) 두 이름이 다 안 들어간다.
  String _secondLine(CareItemEntry item, CareLogEntry? done) {
    if (done == null) return '';
    // **횟수로 가른다, 사람 수가 아니라.** 한 사람이 두 번 한 날도 첫 줄은 `2회` 인데,
    // 그때 시각 하나를 적으면 "누가" 가 화면에서 통째로 사라진다. `2회 · 아빠` 와
    // `2회 · 아빠·엄마` 가 달라 보여야 분담이 보인다.
    if (_countOf(item) < 2) return done.timeLabel;
    final names = _doersOf(item);
    if (names.length == 1) return names.first;
    // 둘을 다 적을 수 있으면 다 적는다. 칸이 좁아서(#326) 다섯 자가 한계다 —
    // `아빠·엄마` 는 들어가고 `아버지·할머니` 는 안 들어간다.
    final joined = names.join('·');
    return names.length == 2 && joined.characters.length <= 5
        ? joined
        : '${names.first} 외 ${names.length - 1}';
  }

  /// 기본 배지에서 가는 **주변 장소** 한 줄 — 이슈 #560 에서 나온 요청.
  ///
  /// <h2>왜 기본 배지에만 붙나</h2>
  ///
  /// "기본으로 주는 일에는 그거에 따라 주변 동물병원이든 애견샵이든 볼 수 있게 하고, 직접
  /// 만든 건 **부가 기능 없이 단순 투두**로" (2026-09-16). 그래서 갈래를 아는 것은
  /// [CareItemEntry.systemType] 이 있는 칸뿐이다. 접은 칸은 여기에도 안 나온다.
  ///
  /// <h2>왜 칸 안이 아니라 카드 아래 한 줄인가</h2>
  ///
  /// 칸은 손가락을 이미 둘 쓴다 — 짧게 누르면 기록, 길게 누르면 지우기(#209·#329). 셋째를
  /// 얹으면 무엇이 일어날지 손끝으로 못 가른다. 한 줄로 빼면 **눈에 보이고**, 그 집이 병원을
  /// 접으면 그 자리도 같이 사라진다.
  ///
  /// <h2>홈의 "급할 때 · 가까운 동물병원" 과 겹치지 않나</h2>
  ///
  /// 뜻이 다르다. 그 줄은 <b>급할 때</b>(#337)라 빨갛고 전화까지 두 번이다. 이 줄은
  /// <b>가는 김에</b>다 — 사료가 떨어졌거나 오늘 산책로를 고르는 자리.
  List<Widget> _nearby() {
    final chips = _nearbyChips();
    if (chips.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Row(children: [
        const Text('주변',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: T.textMuted)),
        const SizedBox(width: 8),
        // Expanded 안의 가로 스크롤이다 — 칸이 늘어 칩이 셋을 넘겨도 줄이 안 넘친다
        // (Flexible 로 나누면 보통 배율에서도 말줄임이 된다).
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final chip in chips) ...[
                if (chip != chips.first) const SizedBox(width: 6),
                chip,
              ],
            ]),
          ),
        ),
      ]),
    ];
  }

  /// 지금 목록이 가리키는 장소 갈래. **겹치면 하나만**, 카드 순서대로.
  List<Widget> _nearbyChips() {
    final seen = <String>{};
    final chips = <Widget>[];
    for (final item in _items) {
      final key = nearbyCategoryOf(item.systemType);
      if (key == null || !seen.add(key)) continue;
      chips.add(_nearbyChip(key));
    }
    return chips;
  }

  Widget _nearbyChip(String categoryKey) {
    final category =
        kPetCategories.firstWhere((c) => c.key == categoryKey);
    return GestureDetector(
      key: Key('care-nearby-$categoryKey'),
      behavior: HitTestBehavior.opaque,
      // 탭을 바꾼다 — 화면을 직접 밀면 탭 바 없는 지도가 열려 돌아올 길이 없다.
      onTap: () {
        RootTab.exploreCategory.value = categoryKey;
        RootTab.index.value = 1;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: T.cardBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 지도 범례와 같은 색·그림이다. 색 예외로 허용된 것이 지도 카테고리색이다.
          Icon(category.icon, size: 12, color: category.color),
          const SizedBox(width: 4),
          Text(category.label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
        ]),
      ),
    );
  }

  /// 이 기록이 **어느 칸의 것인지** 그 칸의 이름으로 적는다 — 이슈 #560.
  ///
  /// 종류에서 뽑으면 직접 만든 항목에 쓸 말이 없다. 에뮬레이터에서 "Bathtime" 을 누르고
  /// "오늘 한 일" 을 봤더니 **`케어`** 라고 적혀 있었다 — 무엇을 했는지가 그 줄의 전부인데
  /// 그것만 빠진 셈이다.
  String _nameOf(CareLogEntry log) => log.nameAmong(_items);

  /// 오늘 이 칸을 누른 사람들. **중복 없이, 최근 순으로.**
  ///
  /// 최근 순인 이유: 한 번일 때 첫 줄이 **마지막에 한 사람**을 적는다. 둘 이상일 때
  /// 앞에 오는 이름이 달라지면 같은 칸이 상황에 따라 다른 기준으로 읽힌다.
  List<String> _doersOf(CareItemEntry item) {
    final seen = <int>{};
    final names = <String>[];
    for (final log in _logs.reversed) {
      if (!_belongsTo(log, item)) continue;
      if (!seen.add(log.doneByUserId)) continue;
      names.add(log.doneByName.isEmpty ? '누군가' : log.doneByName);
    }
    return names;
  }

  Future<void> _tap(CareItemEntry item) async {
    final group = _group;
    if (group == null || _sending != null) return;

    // 일정 물음이 **먼저**다(#741). 오늘 같은 종류의 열린 일정이 있으면 "완료로 할까요?" —
    // 완료로 하면 서버가 케어 기록을 스스로 남기므로 아래 "다음 기록" 물음까지 갈 일이 없다.
    // "아니요 · 기록만" 이면 지금까지의 흐름 그대로다.
    final linked = openScheduleFor(item.systemType, _schedules, dogId: kMyDog.value?.serverId);
    if (linked != null) {
      final answer = await _askScheduleDone(linked);
      if (!mounted) return;
      switch (answer) {
        case _ScheduleAnswer.done:
          await _completeSchedule(item, linked);
          return;
        case _ScheduleAnswer.dismissed:
          return;
        case _ScheduleAnswer.recordOnly:
          break;
      }
    }

    final already = _latestOf(item);
    if (already != null) {
      // 이번이 오늘 몇 번째인가 — 물 세 번째는 정상이고 밥 세 번째는 볼 일이다. 숫자를
      // 주면 사용자가 칸마다 다른 "정상 횟수" 를 스스로 안다(앱이 항목별 상한을 안 가진다).
      final nth = _countOf(item) + 1;
      final me = widget.myUserId ?? AuthState.user?.id;
      if (me != null && already.doneByUserId == me) {
        // 내 기록이 있는 칸을 다시 누른 것 — 다음 기록이 보통이고, 잘못 눌렀으면 지운다
        // (#329). 둘 다 같은 자리에서 고른다.
        final choice = await _askRetap(already, item.name, nth);
        if (!mounted) return;
        switch (choice) {
          case _Retap.undo:
            await _delete(group, item, already);
            return;
          case _Retap.cancel:
            return;
          case _Retap.again:
            break;
        }
      } else {
        final ok = await _confirmNext(already, item.name, nth);
        // await 뒤의 첫 문장에서 가른다 — 이 State 가 사라졌으면 아무것도 하지 않는다.
        if (!mounted) return;
        if (!ok) return;
      }
    }

    setState(() => _sending = item.id);
    try {
      // **기본 항목은 종류로, 직접 만든 것은 항목 번호로 보낸다**(계약: 정확히 하나).
      // 기본 항목을 종류로 보내면 서버가 항목까지 붙여 주므로, 옛 집계와 산책 화면의
      // `type='walk'` 조회가 그대로 돈다.
      await _repo.recordCare(group.id, item.systemType,
          careItemId: item.systemType == null ? item.id : null,
          dogId: kMyDog.value?.serverId);
      if (!mounted) return;
      setState(() => _sending = null);
      // 다른 화면의 카드도 함께 다시 읽는다. 이 콜백이 자기 자신의 _load 도 부른다.
      kServerCareRev.value++;
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = null);
      _showMessage(e.message);
    }
  }

  /// "오늘 14:20 에 내가 밥을 줬어요. 이번이 오늘 2번째예요." — 취소 / 지우기 / 2번째로 기록.
  ///
  /// 으뜸 버튼은 **다음 기록**이다 — 하루 여러 번이 보통이라서. 지우기는 잘못 누른 것을 무르는
  /// 문이라 곁에 둔다(길게 눌러도 지운다).
  Future<_Retap> _askRetap(CareLogEntry mine, String what, int nth) async {
    final answer = await showDialog<_Retap>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '다음 기록을 남길까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          retapWarning(mine, what, nth),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, _Retap.cancel),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, _Retap.undo),
            child: const Text('지우기',
                style: TextStyle(fontWeight: FontWeight.w700, color: T.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, _Retap.again),
            child: Text(
              nextRecordLabel(nth),
              style: const TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? _Retap.cancel;
  }

  /// "오늘 14:20 아빠가 밥을 줬어요. 이번이 오늘 2번째예요." — 취소 / 2번째로 기록.
  Future<bool> _confirmNext(CareLogEntry already, String what, int nth) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '다음 기록을 남길까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          nextRecordQuestion(already, what, nth),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              nextRecordLabel(nth),
              style: const TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// "오늘 10:30 뭉치 병원 — 광견병 접종 일정이 있어요." — 아니요 · 기록만 / 완료로.
  ///
  /// 으뜸 버튼은 **완료로**다 — 카드에서 병원을 누르는 사람은 대개 그 일정을 다녀온 것이다.
  /// 바깥을 눌러 닫으면 아무것도 안 한다: 기록도 완료도 사용자가 고른 것이어야 한다.
  Future<_ScheduleAnswer> _askScheduleDone(Schedule schedule) async {
    final answer = await showDialog<_ScheduleAnswer>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '일정을 완료로 할까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          scheduleDoneQuestion(schedule, dogName: _petNameOf(schedule.dogId)),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            key: const Key('care-schedule-record-only'),
            onPressed: () => Navigator.pop(dialogCtx, _ScheduleAnswer.recordOnly),
            child: const Text('아니요 · 기록만', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            key: const Key('care-schedule-done'),
            onPressed: () => Navigator.pop(dialogCtx, _ScheduleAnswer.done),
            child: const Text(
              '완료로',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? _ScheduleAnswer.dismissed;
  }

  /// 일정을 완료로 — `PATCH /api/schedules/{id}?version=N` 하나뿐이다(#741).
  ///
  /// **케어 기록은 보내지 않는다.** 서버가 그 일정의 기록을 스스로 남긴다
  /// (`ScheduleService.syncCareLog`). 그 뒤 카드와 홈의 할 일 줄이 다시 읽는다 — 그 기록이
  /// 칸에 보여야 사용자가 "됐다" 를 안다.
  ///
  /// 409 는 남이 먼저 고친 것이다. 최신 값이 함께 오면 그것으로 바꾸고, 어느 쪽이든 다시
  /// 읽는다 — 남이 완료했으면 서버가 케어 기록도 남겼으므로 칸도 바뀌어야 한다.
  Future<void> _completeSchedule(CareItemEntry item, Schedule schedule) async {
    setState(() => _sending = item.id);
    try {
      final updated = await _scheduleRepo.mark(schedule, ScheduleStatus.done);
      if (!mounted) return;
      setState(() {
        _sending = null;
        _schedules = _replaceSchedule(_schedules, updated);
      });
      kScheduleRev.value++;
      kServerCareRev.value++;
    } on ScheduleFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = null;
        final current = e.current;
        if (current != null) _schedules = _replaceSchedule(_schedules, current);
      });
      _showMessage(e.userMessage);
      if (e.kind == ScheduleFailureKind.conflict) {
        kScheduleRev.value++;
        kServerCareRev.value++;
      }
    }
  }

  /// 바뀐 일정 하나를 갈아 끼운다. 키는 `(id, 날짜)` 다 — 펼친 하루들이 id 를 나눠 쓴다.
  static List<Schedule> _replaceSchedule(List<Schedule> list, Schedule updated) =>
      [for (final s in list) s.key == updated.key ? updated : s];

  /// 일정에 적힌 아이의 이름. 아이가 없거나 내 목록에 없으면 null — 문구에서 이름을 뺀다.
  static String? _petNameOf(int? dogId) {
    if (dogId == null) return null;
    for (final p in kMyPets.value) {
      if (p.serverId == dogId) return p.name;
    }
    return null;
  }

  /// 칸을 길게 누르면 그 종류의 가장 최근 기록을 지운다 — **내 기록일 때만**(#209).
  ///
  /// 잘못 찍은 "밥 줌" 을 되돌리는 문이다. 서버는 두 번째 기록을 막지 않으므로(위 주석)
  /// 되돌릴 길이 없으면 사용자는 이 카드를 안 믿는다. 남의 기록은 서버도 403 으로 거절하지만
  /// 여기서 먼저 안내한다 — 지울 수 있으면 엄마가 실제로 다녀온 산책을 아빠가 "실수겠지"
  /// 하고 지우는, 이 카드가 막으려던 산책 누락이 그 자리에서 생긴다.
  Future<void> _deleteLatest(CareItemEntry item) async {
    final group = _group;
    if (group == null || _sending != null) return;
    final latest = _latestOf(item);
    if (latest == null) return;

    final me = widget.myUserId ?? AuthState.user?.id;
    if (me == null || latest.doneByUserId != me) {
      _showMessage('내가 남긴 기록만 지울 수 있어요');
      return;
    }

    final ok = await _confirmDelete(latest, item.name);
    if (!mounted || !ok) return;
    await _delete(group, item, latest);
  }

  /// 확인은 끝난 뒤다 — 서버로 지우고 살아 있는 카드가 전부 다시 읽게 한다.
  Future<void> _delete(
      FamilyGroupSummary group, CareItemEntry item, CareLogEntry latest) async {
    setState(() => _sending = item.id);
    try {
      await _repo.deleteCareLog(group.id, latest.id);
      if (!mounted) return;
      setState(() => _sending = null);
      kServerCareRev.value++;
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = null);
      _showMessage(e.message);
      // 벌써 지워진 기록이면 화면이 낡은 것이다 — 다시 읽으면 칸이 맞아진다.
      if (e.kind == FamilyFailureKind.gone) kServerCareRev.value++;
    }
  }

  /// "14:20 에 남긴 밥 기록을 지웁니다. 가족 화면에서도 사라져요."
  Future<bool> _confirmDelete(CareLogEntry entry, String what) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '기록을 지울까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          deleteWarning(entry, what),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              '지우기',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 그리기 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.diversity_1_rounded, size: 17, color: T.warmMid),
          const SizedBox(width: 6),
          // Spacer 대신 Expanded 다 — 글자를 키우면 제목이 자라는데 Spacer 는 0 아래로
          // 못 줄어들어 줄이 통째로 넘쳤다(360dp · 2.0배에서 38px, #396).
          const Expanded(
            child: Text('오늘의 케어',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
          ),
          if (widget.onOpenFamily != null)
            GestureDetector(
              onTap: widget.onOpenFamily,
              behavior: HitTestBehavior.opaque,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text('우리 가족',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
                ),
                Icon(Icons.chevron_right, size: 16, color: T.warmText),
              ]),
            ),
        ]),
        const SizedBox(height: 10),
        _body(),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: T.warmText)),
          SizedBox(width: 8),
          // 아래 두 줄(게스트 · 실패)은 `Expanded` 인데 이 줄만 아니었다. 글자 2.0배 ·
          // 390dp 에서 16px 넘쳐 노란 줄무늬가 떴다 — 데이터가 오기 전 잠깐이라 아무도
          // 못 봤을 뿐이다(#561). `Flexible` 이라 가운데 정렬은 그대로다.
          Flexible(
            child: Text('오늘의 케어를 불러오는 중',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          ),
        ]),
      );
    }

    if (_guest) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Icon(Icons.login_rounded, size: 16, color: T.textMuted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('로그인하면 가족과 오늘의 케어를 나눠요',
                style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
            behavior: HitTestBehavior.opaque,
            child: const Text('로그인',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
          ),
        ]),
      );
    }
    final failure = _failure;
    if (failure != null) {
      // 빈 카드로 그리지 않는다 — "아무도 아무것도 안 했다" 로 읽히고, 그걸 보고
      // 밥을 한 번 더 준다.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(
            failure == FamilyFailureKind.noGroup
                ? Icons.group_add_rounded
                : Icons.cloud_off_rounded,
            size: 16,
            color: T.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(FamilyFailure.messageFor(failure),
                style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
          ),
          // 가족이 없는 것은 오류가 아니라 **할 일**이다. 다시 시도는 아무것도 바꾸지
          // 않고, 그렇다고 아무 버튼도 안 주면 여기서 길이 끊긴다 — #196 이 그 상태였다.
          // 만들기 자체는 가족 화면이 한다. 여기서는 거기로 보낸다.
          if (failure == FamilyFailureKind.noGroup && widget.onOpenFamily != null)
            GestureDetector(
              onTap: widget.onCreateFamily ?? widget.onOpenFamily,
              behavior: HitTestBehavior.opaque,
              child: const Text('만들기',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
            )
          else if (failure != FamilyFailureKind.noGroup)
            GestureDetector(
              onTap: _load,
              behavior: HitTestBehavior.opaque,
              child: const Text('다시 시도',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
            ),
        ]),
      );
    }

    final alreadyWalked = _familyWalkLine();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 가족이 오늘 이미 걸었으면 한 줄로 말한다 (#343). **막지 않는다** — 하루 두 번
      // 걷는 집도 있다. 몰라서 두 번 나가는 것과 알고 두 번 나가는 것은 다르다.
      if (alreadyWalked != null) ...[
        Row(children: [
          const Icon(Icons.directions_walk_rounded, size: 15, color: T.warmText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(alreadyWalked,
                maxLines: 2,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: T.warmText)),
          ),
        ]),
        const SizedBox(height: 9),
      ],
      for (int start = 0; start < _items.length; start += _perRow) ...[
        if (start > 0) const SizedBox(height: 6),
        Row(children: [
          for (int i = 0; i < _perRow; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: start + i < _items.length
                  ? _cell(_items[start + i])
                  // 마지막 줄의 빈 자리. 칸 폭을 줄마다 같게 두려고 자리만 잡는다.
                  : const SizedBox.shrink(),
            ),
          ],
        ]),
      ],
      ..._nearby(),
      ..._todayLog(),
    ]);
  }

  /// 홈이 보여 줄 "오늘 한 일" 줄 수. 나머지는 헤더의 "우리 가족 →" 이 받는다.
  static const int homeLogLines = 3;

  /// **오늘 한 일** — 이슈 #570.
  ///
  /// 위의 칸 일곱은 "할 일" 이다. 각 칸은 **가장 최근 하나**만 말하므로, 아빠와 엄마가
  /// 밥을 한 번씩 준 날 그 칸은 `2회` 하나로 접힌다 — 둘이 한 번씩인지 한 사람이 두
  /// 번인지 알 수 없다. 이 앱의 목적이 업무 분담과 누락 방지라(#76) 그 구별이 곧 화면의
  /// 값어치다. 이 줄이 "한 일" 을 시간까지 펼친다.
  ///
  /// **누락은 위 칸이, 분담은 이 줄이 말한다.** 아무도 안 한 칸은 여기 안 나온다.
  ///
  /// 홈에서는 [homeLogLines] 줄까지만 보이고 나머지는 "그 밖 N개" 한 줄로 접힌다.
  /// 우리 가족 화면(`onOpenFamily == null`)에서는 전부 편다 — 그 화면이 "더 보기" 의
  /// 목적지라, 거기서도 접으면 갈 곳이 없다.
  List<Widget> _todayLog() {
    if (_logs.isEmpty) return const [];
    // **최근 순이다.** 목록은 이른 것부터 오는데(계약), 홈은 세 줄만 보이므로 이른 것부터
    // 자르면 **방금 누른 것이 안 보인다** — 누르고 나서 "기록됐나?" 를 확인할 수 없다.
    final newestFirst = _logs.reversed.toList();
    final full = widget.onOpenFamily == null;
    final shown = full ? newestFirst : newestFirst.take(homeLogLines).toList();
    final rest = newestFirst.length - shown.length;

    return [
      const SizedBox(height: 10),
      Container(height: 1, color: T.line),
      const SizedBox(height: 8),
      // 머리를 누르면 날짜별 기록 화면이 열린다(#737) — 오늘만 보이는 이 줄의 "더" 다.
      // 기록이 하나도 없는 날은 이 줄 자체가 없으니 문도 없다 — 그날은 우리 가족 화면의
      // "케어 기록" 줄로 간다.
      GestureDetector(
        key: const Key('care-log-open'),
        behavior: HitTestBehavior.opaque,
        onTap: _openLog,
        child: Row(children: [
          const Text('오늘 한 일',
              key: Key('care-log-title'),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: T.textMuted)),
          const SizedBox(width: 6),
          // Expanded 다 — Spacer 는 0 아래로 못 줄어들어 큰 글자에서 줄이 넘친다(#396).
          Expanded(
            child: Text('${_logs.length}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: T.textFaint)),
          ),
          const Text('날짜별',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textMuted)),
          const Icon(Icons.chevron_right_rounded, size: 14, color: T.textMuted),
        ]),
      ),
      for (final log in shown) ...[
        const SizedBox(height: 5),
        _logLine(log),
      ],
      if (rest > 0) ...[
        const SizedBox(height: 5),
        Text('그 전에 $rest개',
            key: const Key('care-log-rest'),
            style: const TextStyle(fontSize: 11, color: T.textFaint)),
      ],
    ];
  }

  /// `10:39  아빠  물` — 날짜별 기록 화면과 같은 줄(`widgets/care_log_line.dart`, #737).
  Widget _logLine(CareLogEntry log) =>
      CareLogLine(key: Key('care-log-${log.id}'), log: log, name: _nameOf(log));

  /// 날짜별 기록 화면(#737). 그룹을 아직 못 읽었으면 아무것도 안 한다 — 이 줄은 기록이 있을
  /// 때만 그려지므로 그때는 그룹이 있다.
  void _openLog() {
    final group = _group;
    if (group == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CareLogScreen(groupId: group.id, repository: _repo)));
  }

  /// "아빠가 아침에 1.2km 걸었어요" — 이슈 #343.
  ///
  /// **남이 걸었을 때만이다.** 내가 걸은 것은 내가 안다 — 그 줄은 방금 한 일을 다시
  /// 읽어 주는 것이라 자리만 차지한다.
  ///
  /// 거리는 케어 로그의 메모에 실려 온다([WalkCareLink.kmLabel]). 없으면 거리 없이
  /// 적는다 — 옛 기록과 손으로 누른 산책 칸에는 메모가 없다.
  String? _familyWalkLine() {
    final walk = _items.where((item) => item.systemType == ServerCareType.walk).firstOrNull;
    final latest = walk == null ? null : _latestOf(walk);
    if (latest == null) return null;
    final me = widget.myUserId ?? AuthState.user?.id;
    if (me != null && latest.doneByUserId == me) return null;

    final name = latest.doneByName.isEmpty ? '누군가' : latest.doneByName;
    final distance = latest.memo == null || latest.memo!.isEmpty ? '' : '${latest.memo} ';
    return '$name${subjectParticle(name)} ${_partOfDay(latest.occurredAt)}에 $distance걸었어요';
  }

  static String _partOfDay(DateTime at) {
    if (at.hour < 6) return '새벽';
    if (at.hour < 12) return '아침';
    if (at.hour < 18) return '오후';
    return '저녁';
  }

  Widget _cell(CareItemEntry item) {
    final done = _latestOf(item);
    final busy = _sending == item.id;
    final slug = cellSlug(item);

    return GestureDetector(
      onTap: busy ? null : () => _tap(item),
      // 길게 누르면 내 기록을 지운다(#209). 짧게 누르는 기록과 같은 칸이라 화면이 안 늘어난다.
      onLongPress: busy ? null : () => _deleteLatest(item),
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: Key('care-cell-$slug'),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        // 완료한 칸은 **코랄 하나**다(#546). 종류마다 다른 색을 쓰던 자리인데, 칸마다
        // 아이콘과 이름이 이미 있어 색으로 가를 필요가 없고 — 색이 말하는 것은 종류가
        // 아니라 "했다" 다. 토큰 머리말이 정한 색 예외는 지도 카테고리색과 상태색뿐이다.
        decoration: BoxDecoration(
          color: done != null ? T.accentSoft : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done != null ? T.accentLine : T.surface),
        ),
        // **칸 일곱은 언제나 같은 크기다**(#561). 아이콘 한 줄 + 글 세 줄 — 상태가 무엇이든
        // 줄 수가 같아서, 한 번 누를 때마다 칸이 자라거나 이웃이 따라 움직이지 않는다.
        //
        // 예전에는 "아직"(세 줄) · 완료(네 줄) · 거리 붙은 산책(다섯 줄)이 섞여서 한 줄 안의
        // 칸들이 서로 다른 높이로 앉았다. 실측 [89, 75, 103, 89, 75, 89, 89] — 글자 2.0배에서는
        // 58px 이 벌어졌다.
        child: Column(children: [
          done != null
              ? const Icon(Icons.check_circle_rounded, size: 19, color: T.accent)
              : CareGlyph(iconKey: item.icon, size: 19, color: T.textMuted),
          const SizedBox(height: 4),
          // 이름은 그 집이 적은 것이다 — 스무 자까지 받으므로 좁은 칸에서는 접는다.
          Text(item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const SizedBox(height: 2),
          // 한 줄 "walker · 15:40" 은 다섯 칸 폭에서 "walker · 1…" 로 잘렸다(#326).
          // 둘째 줄과 셋째 줄로 나눈다 — 시각은 잘리지 않는다.
          Text(
            _firstLine(item, done),
            key: Key('care-line1-$slug'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: done == null ? T.textMuted : T.accent),
          ),
          // 아직 안 한 칸도 **빈 줄로 자리를 지킨다.** 이 줄을 없애면 누르는 순간 칸이
          // 한 줄만큼 자라고, 같은 줄의 이웃들이 통째로 밀린다.
          Text(
            _secondLine(item, done),
            key: Key('care-line2-$slug'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: T.accent),
          ),
        ]),
      ),
    );
  }

  /// 한 줄에 몇 칸인가 — **값에 따라 정해진다**(#560).
  ///
  /// 상한은 넷이다. 390dp 에서 <b>다섯은 이미 라벨이 잘렸다</b>(#326 의 실측) — 목록이
  /// 길어졌다고 한 줄을 늘리면 그 집만 글자가 안 보인다. 대신 **셋 이하면 그만큼만** 둔다:
  /// 넷으로 고정하면 두 칸짜리 집의 카드에 빈 자리 둘이 남아 폭이 괜히 좁다.
  ///
  /// <b>칸 크기는 그래도 전부 같다</b>(#561). 한 줄이 언제나 [_perRow] 개의 자리로
  /// 나뉘고 남는 자리는 빈 채로 두기 때문이다.
  int get _perRow => _items.length < kCareCardColumnsPerRow
      ? _items.length
      : kCareCardColumnsPerRow;
}

/// 기본 배지 → 지도의 장소 갈래. 짝이 없으면 {@code null}.
///
/// <b>투약도 동물병원이다.</b> 약은 대개 병원에서 받는다 — 동물약국만 따로 찾는 레이어가
/// 없기도 하다. 병원과 투약이 함께 있는 집에서는 칩이 하나만 뜬다({@code _nearbyChips}).
///
/// 물 · 배변 · 마킹에는 짝이 없다. 갈 곳이 없는데 칩을 만들면 눌러 보고 실망한다.
String? nearbyCategoryOf(ServerCareType? type) => switch (type) {
      ServerCareType.vet || ServerCareType.med => 'vet',
      ServerCareType.meal => 'shop',
      ServerCareType.walk => 'trail',
      _ => null,
    };

/// 칸을 가리키는 열쇠말 — 테스트와 화면이 같은 말을 쓰게 한다.
///
/// 기본 항목은 <b>종류 그대로</b>다(`care-cell-meal`). 목록이 표로 내려오기 전부터 그
/// 이름으로 잠가 둔 테스트가 여럿이고, 그 칸은 어느 집에서나 같은 칸이라 이름을 바꿀
/// 이유가 없다. 직접 만든 항목만 번호로 가른다 — 이름은 집집마다 다르고 바뀐다.
String cellSlug(CareItemEntry item) =>
    item.systemType?.wire ?? 'item-${item.id}';

/// 이 카드가 그리는 칸. **서버의 종류 전부가 아니다** — 목록을 여기 적는다(#340).
///
/// 예전에는 `ServerCareType.values` 를 그대로 돌렸다. 그러다 배변·마킹이 계약에 생기자
/// 칸이 다섯에서 일곱으로 **저절로** 늘었다. 화면에 무엇을 보일지는 계약이 아니라 이 화면이
/// 정할 일이라, 그때 목록을 여기로 옮기고 배변·마킹은 뺐다.
///
/// **2026-09-15 에 다시 넣었다**(#549 · A 안). 빼 두는 동안 그 기록은 `care_log` 에
/// 쌓이기만 하고 앱 어디에서도 볼 수 없었다 — 산책 끝내기 시트가 "배변 1회" 라고 말해 놓고
/// 저장하면 사라졌다. 배변은 건강 신호라 "오늘 몇 번" 이 실제로 세는 값이다.
///
/// 순서는 그대로 두고 뒤에 붙였다. 한 줄에 일곱은 라벨이 잘리므로([kCareCardColumnsPerRow])
/// **넷에서 접는다** — 접는 자리를 옮기면 익숙한 순서가 바뀐다.
const List<ServerCareType> kCareCardColumns = [
  ServerCareType.water,
  ServerCareType.meal,
  ServerCareType.walk,
  ServerCareType.med,
  ServerCareType.vet,
  ServerCareType.poop,
  ServerCareType.pee,
];

/// 한 줄에 몇 칸인가. 390dp 에서 다섯도 이미 좁아 라벨이 잘렸다(#326) — 일곱은 두 줄이다.
/// 마지막 줄의 빈 자리는 **비워 둔다**: 줄마다 칸 폭이 달라지면 같은 카드가 두 벌처럼 보인다.
const int kCareCardColumnsPerRow = 4;

/// "14:20 에 남긴 밥 기록을 지웁니다. 가족 화면에서도 사라져요."
///
/// 무엇을 지우는지(종류·시각)를 문구에 넣는다 — 칸에는 가장 최근 하나만 보이므로 사용자가
/// 어느 기록인지 확인할 수 있어야 한다.
String deleteWarning(CareLogEntry entry, String what) =>
    '${entry.timeLabel} 에 남긴 $what 기록을 지웁니다. 가족 화면에서도 사라져요.';

/// "오늘 14:20 아빠가 밥을 줬어요. 이번이 오늘 2번째예요."
///
/// 위젯 밖에 두는 이유: 이 문구가 완료 조건 2 그 자체라 **테스트가 직접 부를 수 있어야**
/// 한다. 위젯 안에 있으면 문구를 확인하는 방법이 화면을 띄우는 것뿐이다.
///
/// [nth] 는 이번 기록이 오늘 몇 번째인지다. **"그래도" 라고 묻지 않는다** — 물·밥·배변은
/// 하루 여러 번이 보통이라 두 번째가 중복이 아니다. 마지막이 누구·언제였고 이번이 몇 번째인지를
/// 말해 주면, 몇 번이 정상인지는 사용자가 안다(2026-09-20).
String nextRecordQuestion(CareLogEntry already, String what, int nth) {
  // 직접 만든 항목에는 종류가 없다(#560) — 그때는 칸 이름을 그대로 넣는다.
  // "양치를 했어요" 가 "양치 기록을 남겼어요" 보다 읽히지만, 이름이 무엇일지 모르므로
  // 조사를 붙이지 않는 쪽을 고른다 — '약' 과 '양치' 는 붙는 조사가 다르다.
  if (already.type == null) {
    return '오늘 ${already.timeLabel} 에 ${already.doneByName}님이 $what 기록을 남겼어요. '
        '${nthToday(nth)}';
  }
  final phrase = switch (already.type!) {
    ServerCareType.water => '물을 갈아줬어요',
    ServerCareType.meal => '밥을 줬어요',
    ServerCareType.walk => '산책을 다녀왔어요',
    ServerCareType.med => '약을 줬어요',
    ServerCareType.vet => '병원에 다녀왔어요',
    // 산책 중 한 탭으로 들어오는 것들(#340). 배변·마킹은 원래 세는 값이라 "몇 번째" 가
    // 곧 답이다 — 값이 빠지면 화면이 죽으므로 문장을 만들어 둔다.
    ServerCareType.poop => '배변을 기록했어요',
    ServerCareType.pee => '마킹을 기록했어요',
  };
  final name = already.doneByName.isEmpty ? '누군가' : already.doneByName;
  return '오늘 ${already.timeLabel} $name${subjectParticle(name)} $phrase. ${nthToday(nth)}';
}

/// "이번이 오늘 2번째예요." — 묻는 말의 뒷문장. 첫 기록에는 안 묻으므로 2 부터 온다.
String nthToday(int nth) => '이번이 오늘 $nth번째예요.';

/// 으뜸 버튼 — "2번째로 기록". "그래도 기록" 이 아니다.
String nextRecordLabel(int nth) => '$nth번째로 기록';

/// 주격 조사 — 받침이 있으면 `이`, 없으면 `가`.
///
/// "아빠가" 와 "지훈이가" 를 한 문장 틀로 만들려면 이게 필요하다. 늘 `가` 로 쓰면
/// "지훈가" 가 되고, 늘 `님이` 로 피하면 가족끼리 부르는 말투가 아니게 된다.
///
/// 한글 음절은 `0xAC00 + (초성×588) + (중성×28) + 종성` 이라 종성 유무가
/// `(code - 0xAC00) % 28` 로 나온다. 한글이 아닌 이름(영문·이모지)은 `가` 로 둔다.
String subjectParticle(String name) {
  if (name.isEmpty) return '가';
  final code = name.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) return '가';
  return (code - 0xAC00) % 28 == 0 ? '가' : '이';
}

/// 칸의 이름 — 문구와 로그 줄이 같은 말을 쓰게 한다.
///

/// 내 기록이 있는 칸을 다시 눌렀을 때의 선택(#329).
enum _Retap { undo, again, cancel }

String retapWarning(CareLogEntry mine, String what, int nth) =>
    '오늘 ${mine.timeLabel} 에 내가 $what 기록을 남겼어요. ${nthToday(nth)} 잘못 눌렀다면 지울 수 있어요.';

// ─────────────────────── 일정과의 연결 (#741) ───────────────────────

/// "일정을 완료로 할까요?" 의 답.
enum _ScheduleAnswer {
  /// 완료로 — 일정을 PATCH 하고 케어 기록은 안 보낸다.
  done,

  /// 아니요 · 기록만 — 지금까지의 흐름 그대로.
  recordOnly,

  /// 바깥을 눌러 닫았다 — 아무것도 안 한다.
  dismissed,
}

/// 케어 종류 → 일정 종류. **서버의 `ScheduleKind.careWire` 와 같은 짝**이다 — 산책·병원·투약뿐.
///
/// 물·밥·배변·마킹에는 짝이 없다(`null`). 미용·목욕·사료·그 밖은 케어가 아니라 반대쪽에서
/// 짝이 없다. 짝을 여기서 늘리면 서버가 안 남기는 종류를 앱이 "완료로" 묻게 된다.
ScheduleKind? scheduleKindOf(ServerCareType? type) => switch (type) {
      ServerCareType.walk => ScheduleKind.walk,
      ServerCareType.vet => ScheduleKind.vet,
      ServerCareType.med => ScheduleKind.med,
      _ => null,
    };

/// 이 칸을 누를 때 물을 오늘 일정 — 없으면 `null` 이고 그때는 묻지 않는다(#741).
///
/// 셋을 본다. **같은 종류**이고, **열려 있고**(완료·건너뜀은 아니다), **고른 아이 것이거나
/// 아이 없는 것**이다 — 다른 아이의 병원 일정을 뭉치 카드에서 완료하면 안 된다. 같은 종류가
/// 둘 이상이면 **시각이 빠른 것 하나**다([Schedule.compare], 하루 종일은 뒤).
///
/// [dogId] 가 null 이면(아이를 한 마리도 안 등록한 집) 아이 없는 일정만 짝이 된다.
Schedule? openScheduleFor(ServerCareType? type, List<Schedule> today, {int? dogId}) {
  final kind = scheduleKindOf(type);
  if (kind == null) return null;
  Schedule? first;
  for (final s in today) {
    if (s.kind != kind || !s.status.isOpen) continue;
    if (s.dogId != null && s.dogId != dogId) continue;
    if (first == null || Schedule.compare(s, first) < 0) first = s;
  }
  return first;
}

/// "오늘 10:30 뭉치 병원 — 광견병 접종 일정이 있어요."
///
/// 시각은 있을 때만(하루 종일이면 뺀다), 아이 이름도 있을 때만, 그다음이 **종류**다 — 제목이
/// 아니라 종류를 앞세우는 이유는 제목이 사람이 쓴 문장이라 "병원" 이라는 사실이 그 안에 없을
/// 수 있어서다. 제목은 그 뒤에 붙인다. 위젯 밖에 두는 이유는 `nextRecordQuestion` 과 같다 —
/// 문구를 재는 테스트가 화면을 띄우지 않고도 부를 수 있어야 한다.
String scheduleDoneQuestion(Schedule schedule, {String? dogName}) {
  final head = [
    '오늘',
    if (schedule.atTime != null) Schedule.formatTime(schedule.atTime!),
    if (dogName != null && dogName.isNotEmpty) dogName,
    schedule.kind.label,
  ].join(' ');
  final title = schedule.title.trim();
  return title.isEmpty ? '$head 일정이 있어요.' : '$head — $title 일정이 있어요.';
}
