import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/walk_feed.dart';
import '../data/walk_outbox.dart';
import '../data/walk_repository.dart';
import '../widgets/walk_feed_builder.dart';
import 'create_screen.dart';

/// 내 기록 (myRecords) — 산책 기록. 전체 기간 요약 + 산책 목록.
class MyRecordsScreen extends StatelessWidget {
  /// 자료를 어디서 읽고 무엇으로 지우는가. **테스트만 넘긴다.**
  final WalkFeed? feed;
  final WalkRepository? repository;

  const MyRecordsScreen({super.key, this.feed, this.repository});

  static const _warm = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  Widget build(BuildContext context) => WalkFeedBuilder(
        feed: feed,
        builder: (context, data, loadMore) => _build(context, data, loadMore),
      );

  Widget _build(
    BuildContext context,
    WalkFeedData data,
    Future<void> Function()? loadMore,
  ) {
    // **전체 기간이다.** 예전 주석은 "이번 달 요약 집계" 라고 적혀 있었지만 코드는
    // `kWalks` 전체를 접고 있었다 — 라벨을 코드가 실제로 하는 일에 맞춘다.
    final totalKm = data.stats.allTimeKm;
    final totalCount = data.stats.allTimeCount;
    final totalMinutes = data.stats.allTimeMinutes;

    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(children: [
                _backBtn(context),
                const SizedBox(width: 14),
                const Text('산책 기록',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _summaryCard(totalKm, totalCount, totalMinutes),
                  const SizedBox(height: 14),
                  _recordButton(context),
                  const SizedBox(height: 22),
                  const Text('전체 산책',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 12),
                  // 올리지 못한 것을 **맨 위**에 놓는다. 사용자가 조치해야 하는
                  // 유일한 항목이고, 아래에 묻으면 큐에만 남고 화면에서는 사라진
                  // 것과 같아진다 (#161).
                  if (data.rejected.isNotEmpty) ...[
                    Row(children: const [
                      Icon(Icons.error_outline, size: 15, color: Color(0xFFD9534F)),
                      SizedBox(width: 6),
                      Text('올리지 못한 기록',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD9534F))),
                    ]),
                    const SizedBox(height: 10),
                    for (final d in data.rejected.reversed) ...[
                      _walkCard(context, _RecordView.ofRejected(d)),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 10),
                  ],
                  // 전송 대기 중인 것을 **위에** 놓는다. 방금 걸은 것이고, 사용자가
                  // "안 올라갔나?" 를 먼저 확인할 자리다.
                  for (final d in data.pending.reversed) ...[
                    _walkCard(context, _RecordView.ofDraft(d)),
                    const SizedBox(height: 12),
                  ],
                  for (final w in data.walks) ...[
                    _walkCard(context, _RecordView.ofWalk(w)),
                    const SizedBox(height: 12),
                  ],
                  // 다음 장이 있는데 안 그리면, 요약은 "40회" 인데 목록은 30개가 된다.
                  // 사용자는 10건이 사라졌다고 읽는다 (#161).
                  if (loadMore != null) ...[
                    Center(
                      child: TextButton(
                        onPressed: loadMore,
                        child: const Text('더 보기'),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (!data.hasAnything) ...[
                    Center(
                      child: Text(
                        data.offline ? '기록을 불러오지 못했어요' : '아직 산책 기록이 없어요',
                        style: const TextStyle(fontSize: 13, color: T.textMuted),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // P1: 히스토리 보존 정책 사전 고지(추후 유료 경계 — 처음부터 알리고 시작).
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('무료 플랜은 최근 3개월의 상세 기록을 볼 수 있어요',
                        style: TextStyle(fontSize: 11.5, color: T.textMuted)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _backBtn(BuildContext context) => GestureDetector(
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
      );

  // ── 이번 달 요약 ──────────────────────────────
  Widget _summaryCard(double totalKm, int totalCount, int totalMinutes) {
    Widget cell(String v, String label) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0x9E463C64))),
          ]),
        );
    Widget div() => Container(width: 1, height: 34, color: const Color(0x1F8C7BFF));

    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _warm,
              borderRadius: BorderRadius.circular(11),
              boxShadow: const [BoxShadow(color: Color(0x55FF7E8A), blurRadius: 12, offset: Offset(0, 5))],
            ),
            child: const Icon(Icons.pets, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('전체 산책 요약',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          cell('${totalKm.toStringAsFixed(1)}km', '총 거리'),
          div(),
          cell('$totalCount회', '산책 횟수'),
          div(),
          cell('$totalMinutes분', '총 시간'),
        ]),
      ]),
    );
  }

  // ── 산책 기록하기 버튼 ────────────────────────
  Widget _recordButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateScreen())),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x66FF7E8A), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.add_location_alt_outlined, size: 21, color: Colors.white),
          SizedBox(width: 8),
          Text('산책 기록하기',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ── 산책 기록 카드 ───────────────────────────

  /// 길게 눌러 지운다.
  ///
  /// **스와이프가 아니라 롱프레스**인 이유는 이 카드가 세로 `ListView` 안에 있어
  /// 가로 스와이프가 목록 스크롤과 붙어 오작동하기 쉽고, 실수로 지우면 되돌릴 수
  /// 없기 때문이다(계약과 서버가 하드 삭제다). 확인 다이얼로그는 필수다.
  ///
  /// 지울 수 있는 것은 **서버에 있는 것**과 **거절된 것** 둘뿐이다. 전송 대기 중인
  /// 것은 곧 올라가므로 손대지 않는다 — 올라가는 중에 지우면 서버에 남고 화면에서만
  /// 사라진다.
  Widget _walkCard(BuildContext context, _RecordView w) {
    final card = _cardBody(w);
    if (!w.deletable) return card;
    return GestureDetector(
      onLongPress: () => _confirmDelete(context, w),
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  /// 지우기 전에 반드시 묻는다. 하드 삭제라 되돌릴 수 없다.
  Future<void> _confirmDelete(BuildContext context, _RecordView w) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('이 기록을 지울까요?'),
        content: Text(
          w.rejected
              ? '올리지 못한 기록을 지웁니다. 되돌릴 수 없어요.'
              : '${w.date} · ${w.km.toStringAsFixed(1)}km\n서버에서 지워지고 되돌릴 수 없어요.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('지우기',
                style: TextStyle(color: Color(0xFFD9534F), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final failed = await _delete(w);
    // await 뒤의 context 는 죽어 있을 수 있다 — 미리 잡아 둔 messenger 를 쓴다 (#63).
    messenger.showSnackBar(
      SnackBar(
        content: Text(failed ?? '기록을 지웠어요'),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  /// 실제로 지운다. 성공이면 `null`, 실패면 사용자에게 보일 문구.
  ///
  /// 거절 큐는 **기기 안에만** 있으므로 서버를 부르지 않는다.
  Future<String?> _delete(_RecordView w) async {
    if (w.rejected) {
      final outbox = await WalkOutbox.open();
      await outbox.discardRejected(w.clientWalkId!);
      notifyWalksChanged();
      return null;
    }
    try {
      await (repository ?? WalkRepository()).deleteWalk(w.walkId!);
      // 목록에서 빼는 것으로 끝내지 않는다 — 요약 숫자는 서버 집계라 다시 받아야
      // 줄어든다. 완료 조건 1 이 "요약 숫자가 즉시 줄어든다" 인 이유다.
      notifyWalksChanged();
      return null;
    } on WalkFailure catch (e) {
      return e.message;
    }
  }

  Widget _cardBody(_RecordView w) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _warm,
              boxShadow: const [BoxShadow(color: Color(0x40FF7E8A), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.directions_walk_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(w.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                ),
                // 아직 서버에 없다는 것을 **감추지 않는다.** 감추면 나중에 사라진 것처럼
                // 보이고, 저장된 것처럼 그리면 그건 거짓말이다.
                if (w.rejected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x1AD9534F),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('못 올림',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: Color(0xFFD9534F))),
                  )
                else if (w.pending)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x1AE07A4E),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('전송 대기',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: Color(0xFFE07A4E))),
                  ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.calendar_today, size: 12.5, color: Color(0xA8463C64)),
                const SizedBox(width: 4),
                Text(w.date, style: const TextStyle(fontSize: 12, color: Color(0xA8463C64))),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          _stat(Icons.straighten, '${w.km.toStringAsFixed(1)}km'),
          const SizedBox(width: 8),
          _stat(Icons.schedule, '${w.minutes}분'),
          const SizedBox(width: 8),
          _stat(Icons.speed, w.pace),
        ]),
        if (w.memo.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(w.memo, style: const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xD13C345A))),
        ],
        // 왜 못 올라갔는지 말한다. 사유 없이 "못 올림" 만 보여 주면 사용자는 지울지
        // 다시 시도할지 판단할 근거가 없다.
        if (w.reason != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0x12D9534F),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(w.reason!,
                style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFFB5453F))),
          ),
        ],
        // 지울 수 있다는 것을 화면이 말해야 한다 — 롱프레스는 눌러 보기 전에는
        // 있는지조차 알 수 없다.
        if (w.deletable) ...[
          const SizedBox(height: 9),
          const Text('길게 눌러 지우기',
              style: TextStyle(fontSize: 11.5, color: T.textMuted)),
        ],
      ]),
    );
  }

  /// 카드 하나가 그릴 것. 서버 산책과 전송 대기 초안을 **같은 모양**으로 만든다 —
  /// 화면이 둘을 다르게 다루면 "대기 중인 것은 목록에 없다" 같은 규칙이 조용히 생긴다.
  ///
  /// `place` 축이 없다. 계약의 `Walk` 에 장소가 없어서다 — 통계의 `topPlaces` 가
  /// 빈 배열인 것과 같은 이유다. 대신 **시작 시각**을 제목으로 쓴다(실제 정보다).
  static String _titleOf(DateTime startedAt) {
    final hour = startedAt.hour;
    final part = hour < 6
        ? '새벽'
        : hour < 12
            ? '아침'
            : hour < 18
                ? '오후'
                : '저녁';
    return '$part 산책';
  }

  static String _dateOf(DateTime t) {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    return '${t.month}월 ${t.day}일 (${w[t.weekday - 1]})';
  }

  Widget _stat(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x14FF7E8A),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13.5, color: const Color(0xFFE07A4E)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
        ]),
      );
}

/// 목록 카드 하나의 값. 서버 산책과 초안이 여기로 모인다.
class _RecordView {
  final String title;
  final String date;
  final double km;
  final int minutes;
  final String memo;

  /// 아직 서버에 없다. 카드에 "전송 대기" 뱃지가 붙는다.
  final bool pending;

  /// 서버가 거절했다(다시 보내도 소용없다). 카드에 "못 올림" 과 사유가 붙는다.
  final bool rejected;

  /// 왜 못 올라갔는가. [rejected] 일 때만 있다.
  final String? reason;

  /// 서버 산책의 id. 서버에 있는 것만 값이 있다.
  final int? walkId;

  /// 기기 큐 안의 식별자. 초안(대기·거절)만 값이 있다.
  final String? clientWalkId;

  /// 지울 수 있는가.
  ///
  /// 전송 대기 중인 것은 **제외한다.** 곧 올라가는 중이라, 지우는 순간 서버에는
  /// 남고 화면에서만 사라질 수 있다.
  bool get deletable => walkId != null || rejected;

  const _RecordView({
    required this.title,
    required this.date,
    required this.km,
    required this.minutes,
    required this.memo,
    required this.pending,
    this.rejected = false,
    this.reason,
    this.walkId,
    this.clientWalkId,
  });

  String get pace =>
      minutes == 0 ? '-' : '${(minutes / (km == 0 ? 1 : km)).round()}분/km';

  factory _RecordView.ofWalk(ServerWalk w) => _RecordView(
        title: MyRecordsScreen._titleOf(w.startedAt),
        date: MyRecordsScreen._dateOf(w.startedAt),
        km: w.km,
        minutes: w.minutes,
        memo: w.memo ?? '',
        pending: false,
        walkId: w.id,
      );

  factory _RecordView.ofDraft(WalkDraft d) => _RecordView(
        title: MyRecordsScreen._titleOf(d.startedAt),
        date: MyRecordsScreen._dateOf(d.startedAt),
        km: d.km,
        minutes: d.minutes,
        memo: d.lastError ?? d.memo ?? '',
        pending: true,
        clientWalkId: d.clientWalkId,
      );

  /// 서버가 거절한 초안. **메모는 사용자가 쓴 것을 그대로** 두고, 사유는 따로
  /// 나른다 — 예전에는 `lastError` 를 메모 자리에 넣어 사용자가 쓴 글이 오류
  /// 문자열로 덮여 보였다.
  factory _RecordView.ofRejected(WalkDraft d) => _RecordView(
        title: MyRecordsScreen._titleOf(d.startedAt),
        date: MyRecordsScreen._dateOf(d.startedAt),
        km: d.km,
        minutes: d.minutes,
        memo: d.memo ?? '',
        pending: false,
        rejected: true,
        reason: d.lastError ?? '서버가 이 기록을 받지 않았어요',
        clientWalkId: d.clientWalkId,
      );
}
