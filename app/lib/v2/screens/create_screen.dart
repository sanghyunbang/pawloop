import 'myrecords_screen.dart';
import '../data/walk_care_link.dart';
import '../domain/walk_moment.dart';
import 'package:heat_trip_flutter/app/navigator_keys.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/pet_places_repository.dart';
import '../data/place_catalog_repository.dart';
import '../data/walk_outbox.dart';
import '../data/walk_repository.dart';
import '../data/walk_sync.dart';
import '../widgets/pet_registration_sheet.dart';

/// 산책 기록 작성 (create) — 장소·거리·시간·메모·사진.
///
/// ## 초안은 **선택**이다
///
/// 이 화면에 오는 길이 둘이다.
///
///  1. 트래킹을 끝내고 온다 — [draft] 에 실제 경로·거리·시간이 들어 있다.
///  2. `myrecords_screen` 의 "산책 기록하기" 로 바로 온다 — 초안이 없고 손으로 적는다.
///
/// 그래서 [draft] 를 필수로 만들 수 없다. 필수로 두면 두 번째 경로가 컴파일 단계에서
/// 깨진다.
///
/// ## 예전에는 거리가 하드코딩 2.0 이었다
///
/// 트래킹 화면이 실제 거리를 쌓아 놓고도 이 화면으로 넘기지 않아서, 3km 를 걸어도
/// 저장 화면은 2.0km 부터 시작했다. 그리고 저장 버튼은 스낵바만 띄웠다.
class CreateScreen extends StatefulWidget {
  final String? prefillPlace; // 장소 상세 "여기서 산책 기록 쓰기"에서 prefill

  /// 트래킹이 만든 초안. **없으면 손입력이다.**
  final WalkDraft? draft;

  /// 테스트에서 갈아 끼운다. 화면은 평소 기본 생성자를 쓴다.
  final WalkRepository? repository;
  final WalkCareLink? careLink;

  /// 이름 검색을 어디서 하나. 기본은 기기 안 카탈로그다 — 검색어가 서버로 안 나간다(#338).
  final PlaceCatalogRepository? catalog;

  const CreateScreen({
    super.key,
    this.prefillPlace,
    this.draft,
    this.repository,
    this.careLink,
    this.catalog,
  });
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _place = TextEditingController();
  final _memo = TextEditingController();

  /// 카탈로그에서 **고른** 장소. 손으로 이름만 적으면 `null` 이고, 그때는 통계의
  /// "자주 가는 곳" 에 안 들어간다(서버가 `PlaceRef` 를 못 만든다) — 시트에 그렇게 적혀 있다.
  WalkPlaceRef? _placeRef;

  /// 지금 이름 칸 아래 떠 있는 후보들. 기기 안 카탈로그에서 찾는다.
  List<PetPlace> _suggestions = const [];
  int _searchSeq = 0;

  late final PlaceCatalogRepository _catalog = widget.catalog ?? PlaceCatalogRepository.instance;

  /// 초안이 있으면 그 값에서 시작한다. 없을 때만 손입력 기본값이다.
  late double km = widget.draft?.km ?? 2.0;
  late int minutes = widget.draft?.minutes ?? 30;

  /// 사용자가 거리·시간을 **직접 만졌는가.**
  ///
  /// 안 만졌으면 초안의 실측값을 그대로 보낸다. 이게 없으면 화면의 값으로 되돌려
  /// 보내게 되는데, 그 값은 분 단위라 **1분 미만이 통째로 사라진다** — 74초를 걷고
  /// 저장했더니 서버에 `duration_s = 0` 이 들어갔다(실측).
  bool _distanceEdited = false;
  bool _minutesEdited = false;

  bool _saving = false;

  static const _warm = LinearGradient(
    begin: Alignment(-0.7, -1), end: Alignment(0.7, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  @override
  void initState() {
    super.initState();
    // 초안이 장소를 들고 왔으면(지도에서 "여기서 산책 시작") 그것이 이긴다 — 식별자까지 있다.
    final fromDraft = widget.draft?.place;
    if (fromDraft != null) {
      _placeRef = fromDraft;
      _place.text = fromDraft.title;
    } else if (widget.prefillPlace != null) {
      _place.text = widget.prefillPlace!;
    }
    _place.addListener(_onPlaceTyped);
  }

  @override
  void dispose() {
    _place.removeListener(_onPlaceTyped);
    _place.dispose();
    _memo.dispose();
    super.dispose();
  }

  String get _dateLabel {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final n = DateTime.now();
    return '${n.month}월 ${n.day}일 (${w[n.weekday - 1]})';
  }

  /// 저장할 장소. 고른 것이 있으면 식별자까지, 손으로 적었으면 이름만, 비었으면 없다.
  WalkPlaceRef? _placeToSave() {
    final text = _place.text.trim();
    if (text.isEmpty) return null;
    final picked = _placeRef;
    if (picked != null && picked.title == text) return picked;
    return WalkPlaceRef(title: text);
  }

  /// 이름을 고치면 고른 장소는 풀린다 — 이름만 바꿔 놓고 남의 식별자를 달고 가지 않는다.
  void _onPlaceTyped() {
    final text = _place.text.trim();
    if (_placeRef != null && text != _placeRef!.title) {
      setState(() => _placeRef = null);
    }
    _search(text);
  }

  /// 기기 안 카탈로그에서 이름으로 찾는다. **검색어는 서버로 안 나간다**(#235·#338).
  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    if (query.length < 2 || _placeRef != null) {
      if (_suggestions.isNotEmpty && mounted) setState(() => _suggestions = const []);
      return;
    }
    final found = await _catalog.search(query);
    // 늦게 돌아온 옛 검색은 버린다 — 안 그러면 지운 글자의 결과가 다시 뜬다.
    if (!mounted || seq != _searchSeq) return;
    setState(() => _suggestions = found);
  }

  void _pickPlace(PetPlace place) {
    setState(() {
      _placeRef = WalkPlaceRef(
        title: place.title,
        source: place.source,
        contentId: place.contentId,
      );
      _suggestions = const [];
    });
    _place.text = place.title;
    FocusScope.of(context).unfocus();
  }

  /// 저장. **여기서 처음으로 기록이 서버로 나간다.**
  ///
  /// 화면은 결과를 있는 그대로 말한다 — 큐에 남았으면 "저장됐어요" 라고 하지 않는다.
  /// 그게 "저장은 됐는데 아무 데도 안 보인다" 를 만드는 자리다.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final memo = _memo.text.trim();
    final base = widget.draft ??
        // 손입력이다. 경로가 없고 시각은 지금 기준으로 만든다 — 지어낸 좌표를 넣지
        // 않는 것이 요점이다.
        WalkDraft.fresh(
          startedAt: DateTime.now().subtract(Duration(minutes: minutes)),
          endedAt: DateTime.now(),
          distanceM: (km * 1000).round(),
          durationS: minutes * 60,
          path: const [],
        );

    final draft = base.copyWith(
      // **만진 것만 이긴다.** 사용자가 손으로 정한 값은 실측값을 이기지만, 안 만졌으면
      // 초안의 초 단위 값을 그대로 둔다 — 화면의 분 단위로 되돌리면 1분 미만이 사라진다.
      distanceM: _distanceEdited || widget.draft == null ? (km * 1000).round() : null,
      durationS: _minutesEdited || widget.draft == null ? minutes * 60 : null,
      memo: memo.isEmpty ? null : memo,
      // 이름이 비면 장소도 없다 — 초안이 들고 온 것까지 버린다(dropPlace).
      place: _placeToSave(),
      dropPlace: _placeToSave() == null,
    );

    final WalkSyncResult result;
    try {
      final sync = await WalkSync.open(repository: widget.repository);
      result = await sync.push(draft);
    } catch (_) {
      // 저장소를 열지 못했다(디스크 문제 등). 기록을 잃지 않았다고 말할 수 없다.
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('기록을 저장하지 못했어요');
      return;
    }

    if (!mounted) return;

    // 반려동물이 없어서 못 올린 경우다. **스낵바로 끝내지 않는다** — 사용자는 안내를
    // 받고도 등록할 곳을 찾을 수 없었다(#159). 지금 그 자리에서 등록하게 하고, 성공하면
    // 방금 그 산책을 바로 올린다.
    if (result.outcome == WalkSyncOutcome.queued && result.needsPet) {
      final registered = await showPetRegistrationSheet(
        context,
        reason: '산책을 저장하려면 어느 아이의 산책인지 알아야 해요',
      );
      if (!mounted) return;
      if (registered != null) {
        final retried = await WalkSync.open(repository: widget.repository).then((s) => s.flush());
        if (!mounted) return;
        setState(() => _saving = false);
        if (retried > 0) _afterSaved(draft.moments);
        _toast(
          retried > 0 ? '산책이 기록됐어요' : '기록을 보관했어요 · 연결되면 올릴게요',
          seeRecords: retried > 0,
        );
        Navigator.of(context).maybePop();
        return;
      }
    }

    setState(() => _saving = false);
    final saved = result.outcome == WalkSyncOutcome.saved;
    if (saved) _afterSaved(draft.moments);
    _toast(
      switch (result.outcome) {
        WalkSyncOutcome.saved => '산책이 기록됐어요',
        // 사라지지 않았다는 것과, 아직 서버에 없다는 것을 둘 다 말한다.
        WalkSyncOutcome.queued =>
          result.reason ?? '기록을 보관했어요 · 연결되면 올릴게요',
        WalkSyncOutcome.rejected => result.reason ?? '기록을 저장할 수 없어요',
      },
      seeRecords: saved,
    );
    Navigator.of(context).maybePop();
  }

  /// 서버에 저장된 뒤 — 오늘의 케어 "산책" 칸에도 남긴다(#326). 기다리지 않는다:
  /// 케어가 늦거나 실패해도 산책은 이미 저장됐고, 홈은 그 결과를 따로 다시 읽는다.
  ///
  /// [moments] 는 산책 중에 누른 배변·마킹·물이다(#340). 같은 자리로 보내는 이유는
  /// 하루치를 세는 단위가 같아서다 — 가족이 없으면 셋 다 조용히 안 간다.
  void _afterSaved([List<WalkMoment> moments = const []]) {
    unawaited((widget.careLink ?? WalkCareLink())
        .recordWalk(moments: moments, km: km));
  }

  /// [seeRecords] 면 "보기" 가 붙는다 — 저장한 산책이 어디로 갔는지 홈이 말하지 않았다(#326).
  void _toast(String message, {bool seeRecords = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(milliseconds: seeRecords ? 3200 : 1800),
        action: seeRecords ? SnackBarAction(label: '보기', onPressed: _openRecords) : null,
      ),
    );
  }

  /// 스낵바가 살아 있을 때 이 화면은 이미 닫혀 있다 — 루트 내비게이터로 연다.
  static void _openRecords() {
    rootNavigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => const MyRecordsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _placeCard(),
                  const SizedBox(height: 14),
                  _metricsCard(),
                  const SizedBox(height: 14),
                  _memoCard(),
                  const SizedBox(height: 18),
                  _saveButton(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: T.cardBorder),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('산책 기록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: _save,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Text('저장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.warmEnd)),
            ),
          ),
        ]),
      );

  // 라벨 + 입력박스 헬퍼
  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary));

  BoxDecoration get _fieldDeco => BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2E8C7BFF)),
      );

  // ── 장소 + 날짜 ─────────────────────────────
  Widget _placeCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('어디를 걸었나요?'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(children: [
            const Icon(Icons.place, size: 18, color: T.sigStart),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _place,
                style: const TextStyle(fontSize: 14, color: T.textPrimary),
                decoration: const InputDecoration(
                  hintText: '예: 서울숲, 한강공원, 동네 한 바퀴',
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            if (_placeRef?.isCatalog ?? false)
              const Icon(Icons.check_circle, size: 18, color: Color(0xFF3DBE6C)),
          ]),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 7),
          // 기기 안 카탈로그에서 찾은 것들. 고르면 식별자가 붙어 "자주 가는 곳" 에 쌓인다.
          Container(
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: T.line),
            ),
            child: Column(
              children: [
                for (final place in _suggestions)
                  GestureDetector(
                    onTap: () => _pickPlace(place),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      child: Row(children: [
                        Icon(place.petCategory.icon, size: 15, color: place.petCategory.color),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(place.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, color: T.textPrimary)),
                        ),
                        Text(place.petCategory.label,
                            style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_place.text.trim().isNotEmpty && !(_placeRef?.isCatalog ?? false)) ...[
          const SizedBox(height: 6),
          const Text('목록에서 고르면 "자주 가는 곳" 에 쌓여요. 직접 적은 이름은 이 기록에만 남아요.',
              style: TextStyle(fontSize: 11.5, color: T.textMuted)),
        ],
        const SizedBox(height: 14),
        _label('날짜'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
          child: Row(children: [
            Text(_dateLabel, style: const TextStyle(fontSize: 14, color: T.textPrimary)),
            const Spacer(),
            const Icon(Icons.calendar_month, size: 18, color: T.textMuted),
          ]),
        ),
      ]),
    );
  }

  // ── 거리 · 시간 스텝퍼 ────────────────────────
  Widget _metricsCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('얼마나 걸었나요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        // 초안이 없으면 아래 2.0km/30분은 **측정값이 아니라 출발점**이다. 그 말을 안
        // 하면 사용자가 앱이 재어 준 값인 줄 알고 그대로 저장하고, 걷지 않은 2km 가
        // 통계에 계속 세진다. (이슈 #160)
        //
        // 지우는 것은 가능하다 — 내 기록 화면(myrecords_screen)에서 길게 눌러 지운다.
        // 하드 삭제라 되돌릴 수 없어서 그 화면이 반드시 한 번 묻는다.
        if (widget.draft != null) ...[
          const SizedBox(height: 5),
          const Row(children: [
            Icon(Icons.gps_fixed, size: 13, color: T.textMuted),
            SizedBox(width: 5),
            Expanded(
              child: Text('GPS 로 잰 값이에요 · 여기서는 고칠 수 없어요',
                  style: TextStyle(fontSize: 12, color: T.textMuted)),
            ),
          ]),
          // 산책 중에 누른 것들 (#340). 저장하면 오늘의 케어에도 같이 남는다.
          if (!WalkMomentTally.of(widget.draft?.moments ?? const []).isEmpty) ...[
            const SizedBox(height: 7),
            Row(children: [
              const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF4CAF88)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${WalkMomentTally.of(widget.draft!.moments).summary} · 오늘의 케어에도 남겨요',
                  style: const TextStyle(fontSize: 12, color: T.textSecondary),
                ),
              ),
            ]),
          ],
        ],
        if (widget.draft == null) ...[
          const SizedBox(height: 5),
          const Row(children: [
            Icon(Icons.edit_outlined, size: 13, color: T.textMuted),
            SizedBox(width: 5),
            Expanded(
              child: Text('직접 입력하는 값이에요 · 아래 숫자는 기본값입니다',
                  style: TextStyle(fontSize: 12, color: T.textMuted)),
            ),
          ]),
        ],
        const SizedBox(height: 14),
        _stepperRow(
          icon: Icons.straighten,
          label: '거리',
          readOnly: widget.draft != null,
          // 잰 값은 둘째 자리까지 — 0.15km 를 0.1 로 보여 주면 잰 값이 아니다.
          value: widget.draft != null ? '${km.toStringAsFixed(2)} km' : '${km.toStringAsFixed(1)} km',
          onMinus: () => setState(() {
            km = (km - 0.1).clamp(0.0, 99.0);
            _distanceEdited = true;
          }),
          onPlus: () => setState(() {
            km = (km + 0.1).clamp(0.0, 99.0);
            _distanceEdited = true;
          }),
        ),
        const SizedBox(height: 12),
        _stepperRow(
          icon: Icons.schedule,
          label: '시간',
          readOnly: widget.draft != null,
          value: '$minutes 분',
          onMinus: () => setState(() {
            minutes = (minutes - 5).clamp(0, 600);
            _minutesEdited = true;
          }),
          onPlus: () => setState(() {
            minutes = (minutes + 5).clamp(0, 600);
            _minutesEdited = true;
          }),
        ),
      ]),
    );
  }

  Widget _stepperRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    bool readOnly = false,
  }) {
    Widget btn(IconData i, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x2E8C7BFF)),
            ),
            child: Icon(i, size: 20, color: T.textSecondary),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x8CFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x298C7BFF)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0x22FF9E7D), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 18, color: T.warmMid),
        ),
        const SizedBox(width: 10),
        _label(label),
        const Spacer(),
        // GPS 로 잰 값은 고칠 수 없다 — ±가 있으면 잰 값이 믿을 수 없게 된다(#327).
        if (!readOnly) btn(Icons.remove, onMinus),
        SizedBox(
          width: 78,
          child: Text(value, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ),
        if (!readOnly) btn(Icons.add, onPlus),
      ]),
    );
  }

  // ── 메모 ────────────────────────────────────
  Widget _memoCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('오늘의 산책', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 12),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: TextField(
            controller: _memo,
            maxLines: 4,
            // 서버가 @Size(max=500) 이다. 여기서 막지 않으면 501자를 쓴 사람이
            // '저장' 을 누른 뒤에야 400 을 받고, 그 기록은 거절 큐로 간다 —
            // 되돌릴 수 없는 실패를 입력 단계에서 막는다. (#161)
            //
            // 숫자를 여기 적지 않는다. 저장소가 계약·컬럼 폭과 함께 들고 있는
            // 상수를 쓴다 — 두 곳에 적으면 한쪽만 바뀌는 날이 온다.
            maxLength: WalkRepository.maxMemoLength,
            style: const TextStyle(fontSize: 14, height: 1.6, color: T.textPrimary),
            decoration: const InputDecoration(
              hintText: '오늘 산책은 어땠나요? 우리 아이의 컨디션, 만난 친구, 특별했던 순간을 적어보세요...',
              hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: T.warmGlow, blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.pets, size: 21, color: Colors.white),
          SizedBox(width: 8),
          Text('산책 기록 저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }
}
