import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/walk_feed.dart';
import '../data/walk_outbox.dart';
import '../data/walk_repository.dart';
import '../domain/pet.dart';
import '../domain/walk_labels.dart';
import '../walk/walk_share.dart';
import '../walk/walk_share_card.dart';
import '../widgets/walk_feed_builder.dart';
import 'create_screen.dart';
import 'walk_detail_screen.dart';

/// 내 기록 (myRecords) — 산책 기록. 전체 기간 요약 + 산책 목록.
class MyRecordsScreen extends StatelessWidget {
  /// 자료를 어디서 읽고 무엇으로 지우는가. **테스트만 넘긴다.**
  final WalkFeed? feed;
  final WalkRepository? repository;

  /// 공유 시트를 여는 함수 (#344). **테스트만 넘긴다.**
  final Future<void> Function(WalkShareCard card)? share;

  const MyRecordsScreen({super.key, this.feed, this.repository, this.share});

  static const _warm = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [T.warmStart, T.warmEnd],
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
      backgroundColor: T.bgTop,
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
                  // 아직 안 읽었으면 아무 말도 안 한다(#568) — "불러오지 못했어요" 도
                  // "아직 기록이 없어요" 도 첫 프레임에서는 둘 다 틀린 말이다.
                  if (!data.hasAnything && !data.loading) ...[
                    Center(
                      child: Text(
                        data.offline ? '기록을 불러오지 못했어요' : '아직 산책 기록이 없어요',
                        style: const TextStyle(fontSize: 13, color: T.textMuted),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
            color: T.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: T.cardBorder),
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
            Text(label, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
          ]),
        );
    Widget div() => Container(width: 1, height: 34, color: T.line);

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
          boxShadow: const [BoxShadow(color: T.warmGlow, blurRadius: 24, offset: Offset(0, 12))],
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
    final card = _cardBody(context, w);
    if (!w.deletable) return card;
    return GestureDetector(
      // 서버에 있는 것만 회고를 쓸 수 있다. 거절된 것은 서버에 행이 없어 고칠 대상이
      // 없고, 전송 대기 중인 것은 아직 id 가 없다.
      onTap: w.walkId == null ? null : () => _openDetail(context, w),
      onLongPress: () => _confirmDelete(context, w),
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  void _openDetail(BuildContext context, _RecordView w) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WalkDetailScreen(
        walkId: w.walkId!,
        startedAt: w.startedAt,
        km: w.km,
        durationS: w.durationS,
        initialMemo: w.memo,
        photoUrls: w.photoUrls,
        placeTitle: w.placeTitle,
      ),
    ));
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

  /// 카드 오른쪽 위 "…" — 지우기(와 회고). 길게 누르기는 눌러 보기 전에는 있는지 모른다(#327).
  Future<void> _showActions(BuildContext context, _RecordView w) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.ios_share_rounded, color: T.warmText),
            title: const Text('공유하기'),
            subtitle: const Text('숫자만 담긴 카드 한 장',
                style: TextStyle(fontSize: 11.5, color: T.textMuted)),
            onTap: () => Navigator.pop(sheetCtx, 'share'),
          ),
          if (w.walkId != null)
            ListTile(
              leading: const Icon(Icons.edit_note_rounded, color: T.textSecondary),
              title: const Text('회고 쓰기'),
              onTap: () => Navigator.pop(sheetCtx, 'memo'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD9534F)),
            title: const Text('지우기', style: TextStyle(color: Color(0xFFD9534F))),
            onTap: () => Navigator.pop(sheetCtx, 'delete'),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (action == 'delete') {
      await _confirmDelete(context, w);
    } else if (action == 'memo') {
      _openDetail(context, w);
    } else if (action == 'share') {
      await _share(context, w);
    }
  }

  /// 기록 하나를 카드 한 장으로 (#344).
  ///
  /// **선이 없다.** 서버가 준 기록에는 좌표가 없다 — A안(#235)에서 경로는 기기 밖으로
  /// 나가지 않기 때문이다. 그래서 여기서 나오는 카드는 숫자만 있는 한 장이고, 시트의
  /// 부제가 그것을 미리 말한다("숫자만 담긴 카드 한 장").
  Future<void> _share(BuildContext context, _RecordView w) async {
    final dog = kMyDog.value?.name;
    final messenger = ScaffoldMessenger.of(context);
    if (dog == null || dog.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('아이를 먼저 등록해 주세요'),
        duration: Duration(milliseconds: 1600),
      ));
      return;
    }
    try {
      await (share ?? WalkShare.share)(WalkShareCard(
        dogName: dog,
        accent: T.warmMid,
        dateLabel: '${w.date} ${_timeOf(w.startedAt)} 출발',
        distanceLabel: '${w.km.toStringAsFixed(1)}km',
        timeLabel: w.timeLabel,
        paceLabel: w.pace,
      ));
    } on WalkShareException catch (e) {
      // await 뒤의 context 는 죽어 있을 수 있다 — 미리 잡아 둔 messenger 를 쓴다 (#63).
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(milliseconds: 1600),
      ));
    }
  }

  static String _timeOf(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _cardBody(BuildContext context, _RecordView w) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // 사진이 있으면 아이콘 자리에 첫 장(#450) — 기록 목록도 사진 앱이다.
          if (w.photoUrls.isNotEmpty)
            ClipRRect(
              key: Key('record-photo-${w.walkId}'),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Image.network(w.photoUrls.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(gradient: _warm),
                        child: const Icon(Icons.directions_walk_rounded, size: 20, color: Colors.white))),
              ),
            )
          else
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
                            color: T.warmText)),
                  ),
                if (w.deletable) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _showActions(context, w),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.more_horiz_rounded, size: 20, color: T.textMuted),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.calendar_today, size: 12.5, color: T.textMuted),
                const SizedBox(width: 4),
                Text(w.date, style: const TextStyle(fontSize: 12, color: T.textMuted)),
                // 장소는 **날짜 다음**이다(#547). 줄어들어도 되는 것이 이것 하나뿐이라
                // Flexible 을 여기만 건다 — 둘에 걸면 자리가 남아도 반씩 나눠 말줄임이 된다.
                if (w.placeTitle != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.place_outlined, size: 12.5, color: T.textMuted),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      w.placeTitle!,
                      key: Key('record-place-${w.clientWalkId ?? w.walkId}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: T.textMuted),
                    ),
                  ),
                ],
              ]),
              // 함께 나간 아이들 (#343). **한 마리면 안 적는다** — 한 마리인 사람에게
              // 매 카드마다 자기 아이 이름을 한 번 더 보여 줄 이유가 없다.
              if (_companions(w) != null) ...[
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.pets_rounded, size: 12.5, color: T.warmText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(_companions(w)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          _stat(Icons.straighten, '${w.km.toStringAsFixed(1)}km'),
          const SizedBox(width: 8),
          _stat(Icons.schedule, w.timeLabel),
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
        // 무엇을 할 수 있는지 화면이 말해야 한다 — 탭도 롱프레스도 눌러 보기 전에는
        // 있는지조차 알 수 없다.
        if (w.deletable) ...[
          const SizedBox(height: 9),
          Text(
            w.walkId == null ? '길게 눌러 지우기' : '눌러서 회고 쓰기 · 길게 눌러 지우기',
            style: const TextStyle(fontSize: 11.5, color: T.textMuted),
          ),
        ],
      ]),
    );
  }

  /// 카드 하나가 그릴 것. 서버 산책과 전송 대기 초안을 **같은 모양**으로 만든다 —
  /// 화면이 둘을 다르게 다루면 "대기 중인 것은 목록에 없다" 같은 규칙이 조용히 생긴다.
  ///
  /// 제목은 **시작 시각**이다(`아침 산책`). 장소가 있으면 날짜 줄에 함께 적는다(#547) —
  /// 제목에 붙이지 않는 이유는, 장소가 없는 기록과 있는 기록의 제목 모양이 갈리면
  /// 목록을 훑을 때 줄이 들쭉날쭉해 보이기 때문이다.
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

  /// "보리 · 초코" — 두 마리 이상일 때만 (#343).
  ///
  /// 이름은 등록된 아이 목록에서 찾는다. **못 찾은 id 는 조용히 뺀다** — 지운 아이의
  /// 산책은 계속 세지만(#156) 그 아이의 이름은 더 이상 없다. 거기에 "알 수 없음" 을
  /// 적으면 사용자는 자기가 뭘 잘못한 줄 안다.
  static String? _companions(_RecordView w) {
    if (w.dogIds.length < 2) return null;
    final byId = {for (final p in kMyPets.value) p.serverId: p.name};
    final names = [
      for (final id in w.dogIds)
        if (byId[id] != null) byId[id]!,
    ];
    return names.length < 2 ? null : names.join(' · ');
  }

  Widget _stat(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x14FF7E8A),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13.5, color: T.warmText),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
        ]),
      );
}

/// 목록 카드 하나의 값. 서버 산책과 초안이 여기로 모인다.
class _RecordView {
  final String title;
  final String date;
  final double km;
  /// 걸린 시간 — **초**다. 분으로 들고 있던 것을 초로 바꿨다(#537): 1분이 안 되는 산책이
  /// `0분` 이 되어 통째로 사라졌고, 페이스도 분으로 나누느라 `-` 였다.
  final int durationS;

  /// 화면에 적는 시간 — `44초` · `12분`.
  String get timeLabel => walkTimeLabel(durationS);

  /// 분 단위가 필요한 자리(공유 카드의 옛 서식 등)를 위해 남겨 둔다.
  int get minutes => durationS ~/ 60;
  final String memo;

  /// 함께 나간 아이들의 서버 id (#343). 초안에는 아직 없어서 빈 목록이다 —
  /// 전송 대기 카드에 아이 이름을 적으면, 그것이 곧 서버가 준 사실처럼 읽힌다.
  final List<int> dogIds;

  /// 아직 서버에 없다. 카드에 "전송 대기" 뱃지가 붙는다.
  final bool pending;

  /// 서버가 거절했다(다시 보내도 소용없다). 카드에 "못 올림" 과 사유가 붙는다.
  final bool rejected;

  /// 왜 못 올라갔는가. [rejected] 일 때만 있다.
  final String? reason;

  /// 서버 산책의 id. 서버에 있는 것만 값이 있다.
  final int? walkId;

  /// 기기 큐 안의 식별자. 서버 산책도 들고 있다 — 계약이 required 이고(`openapi.yaml`),
  /// 나중에 경로를 기기에만 두게 되면 이 열쇠로 서버 기록과 짝지어야 한다.
  final String? clientWalkId;

  /// 시작 시각. 상세 화면이 첫 프레임을 이 값으로 그린다.
  final DateTime startedAt;

  /// 지울 수 있는가.
  ///
  /// 전송 대기 중인 것은 **제외한다.** 곧 올라가는 중이라, 지우는 순간 서버에는
  /// 남고 화면에서만 사라질 수 있다.
  bool get deletable => walkId != null || rejected;

  const _RecordView({
    required this.title,
    required this.date,
    required this.startedAt,
    required this.km,
    required this.durationS,
    required this.memo,
    required this.pending,
    this.dogIds = const [],
    this.rejected = false,
    this.reason,
    this.walkId,
    this.clientWalkId,
    this.photoUrls = const [],
    this.placeTitle,
  });

  /// 산책에 붙은 사진 URL(#450) — 있으면 카드의 아이콘 자리에 첫 장이 들어가고 상세에 띠로 보인다.
  final List<String> photoUrls;

  /// 저장할 때 적은 곳의 이름 — 계약의 `Walk.place.title`(#338). 카탈로그에서 고른 것도,
  /// 직접 적은 것도 같은 자리다. 없으면 `null` 이고 그때는 줄에 아무것도 안 붙는다.
  final String? placeTitle;

  /// 1km 에 걸린 시간 — `1'02"`. 못 재면 `-`.
  String get pace => walkPaceLabel(durationS: durationS, km: km) ?? '-';

  factory _RecordView.ofWalk(ServerWalk w) => _RecordView(
        title: MyRecordsScreen._titleOf(w.startedAt),
        date: MyRecordsScreen._dateOf(w.startedAt),
        startedAt: w.startedAt,
        km: w.km,
        durationS: w.durationS,
        memo: w.memo ?? '',
        pending: false,
        dogIds: w.dogIds,
        walkId: w.id,
        clientWalkId: w.clientWalkId,
        photoUrls: [for (final m in w.media) m.url],
        placeTitle: w.place?.title,
      );

  factory _RecordView.ofDraft(WalkDraft d) => _RecordView(
        title: MyRecordsScreen._titleOf(d.startedAt),
        date: MyRecordsScreen._dateOf(d.startedAt),
        startedAt: d.startedAt,
        km: d.km,
        durationS: d.durationS,
        memo: d.lastError ?? d.memo ?? '',
        pending: true,
        clientWalkId: d.clientWalkId,
        placeTitle: d.place?.title,
      );

  /// 서버가 거절한 초안. **메모는 사용자가 쓴 것을 그대로** 두고, 사유는 따로
  /// 나른다 — 예전에는 `lastError` 를 메모 자리에 넣어 사용자가 쓴 글이 오류
  /// 문자열로 덮여 보였다.
  factory _RecordView.ofRejected(WalkDraft d) => _RecordView(
        title: MyRecordsScreen._titleOf(d.startedAt),
        date: MyRecordsScreen._dateOf(d.startedAt),
        startedAt: d.startedAt,
        km: d.km,
        durationS: d.durationS,
        memo: d.memo ?? '',
        pending: false,
        rejected: true,
        reason: d.lastError ?? '서버가 이 기록을 받지 않았어요',
        clientWalkId: d.clientWalkId,
        placeTitle: d.place?.title,
      );
}
