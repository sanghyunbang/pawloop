// lib/v2/screens/walk_detail_screen.dart
//
// 산책 하나를 열어 회고를 쓴다 — 이슈 #187.
//
// ## 왜 만들었나
//
// 메모는 `create_screen` 의 저장 시점에 한 번 쓰는 것이 전부였다. 산책이 끝난 직후에
// 쓰는 글과 나중에 돌아보며 쓰는 글은 다른데, 잘못 쓰면 **지우고 다시 만드는 수밖에**
// 없었다. 목록 카드를 눌러도 아무 일이 없었다(길게 누르면 삭제만).
//
// ## 여기서 바꿀 수 있는 것은 글뿐이다
//
// 거리·시간은 실측값이거나 사용자가 저장 시점에 정한 값이다. 여기서 열면 "회고를
// 쓴다" 가 "기록을 고친다" 로 번진다. 손입력 오타를 고치고 싶다는 요구가 실제로 나오면
// 그때 따로 정한다.
library;

import 'package:flutter/material.dart';

import '../data/walk_feed.dart';
import '../data/course_repository.dart';
import '../data/location_upload_policy.dart';
import '../data/walk_repository.dart';
import '../domain/walk_labels.dart';
import '../widgets/course_save_sheet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

class WalkDetailScreen extends StatefulWidget {
  final int walkId;

  /// 목록이 이미 알고 있는 값. **첫 프레임을 이걸로 그린다** — 상세 응답을 기다리는
  /// 동안 빈 화면을 보여 주면 사용자는 기록이 사라진 줄 안다.
  final DateTime startedAt;
  final double km;

  /// 걸린 시간 — **초**다(#537). 분으로 받으면 1분이 안 되는 산책이 `0분` 이 된다.
  final int durationS;
  final String initialMemo;

  /// 붙은 사진 URL(#450) — 목록이 이미 알고 있어 다시 조회하지 않는다.
  final List<String> photoUrls;

  /// 저장할 때 적은 곳의 이름(#547). 목록과 같은 값이고, 없으면 그 줄이 안 생긴다.
  final String? placeTitle;

  /// 서버를 어디로 부르는가. **테스트만 넘긴다.**
  final WalkRepository? repository;

  /// 코스 저장소. 테스트가 꽂는 자리다 (#339).
  final CourseRepository? courses;

  const WalkDetailScreen({
    super.key,
    required this.walkId,
    required this.startedAt,
    required this.km,
    required this.durationS,
    required this.initialMemo,
    this.photoUrls = const [],
    this.placeTitle,
    this.repository,
    this.courses,
  });

  @override
  State<WalkDetailScreen> createState() => _WalkDetailScreenState();
}

class _WalkDetailScreenState extends State<WalkDetailScreen> {
  late final TextEditingController _memo =
      TextEditingController(text: widget.initialMemo);
  late final WalkRepository _repo = widget.repository ?? WalkRepository();

  /// 마지막으로 서버에 올라간 글. '저장' 을 켤지 끌지가 이것과의 차이로 정해진다.
  late String _saved = widget.initialMemo;

  bool _sending = false;

  bool get _dirty => _memo.text != _saved;

  @override
  void initState() {
    super.initState();
    _memo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_sending || !_dirty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);

    try {
      final walk = await _repo.rewriteMemo(widget.walkId, _memo.text);
      if (!mounted) return;
      setState(() {
        // 서버가 눕힌 값을 그대로 받는다 — 빈 문자열은 null 로 돌아온다. 앱이 짐작하면
        // '저장' 버튼이 영원히 켜져 있는 상태가 된다.
        _saved = walk.memo ?? '';
        _memo.text = _saved;
        _sending = false;
      });
      // 목록의 카드도 이 글을 그린다. 알리지 않으면 뒤로 갔을 때 옛 글이 남는다.
      notifyWalksChanged();
      messenger.showSnackBar(const SnackBar(
        content: Text('기록했어요'),
        duration: Duration(milliseconds: 1400),
      ));
    } on WalkFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      // 실패했는데 화면의 글은 그대로 둔다 — 사용자가 쓴 것을 되돌리면 그게 더 나쁘다.
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(milliseconds: 2000),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  // 산책 중 찍은 사진 (#450) — 기록을 열면 사진이 먼저다.
                  if (widget.photoUrls.isNotEmpty) ...[
                    _photosCard(),
                    const SizedBox(height: 16),
                  ],
                  _summaryCard(),
                  const SizedBox(height: 16),
                  // 걸은 길을 남기는 자리 (#339). 회고 위에 둔다 — 기록을 열어 처음 드는
                  // 생각이 "이 길 좋았다" 이고, 그 다음이 "무슨 일이 있었더라" 다.
                  // 좌표가 안 올라가는 빌드에서는 서버에 벨 선이 없다 — 자리를 안 만든다.
                  if (LocationUploadPolicy.sharesRoutes) ...[
                    _saveAsCourseCard(),
                    const SizedBox(height: 16),
                  ],
                  _memoCard(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('산책 회고',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const Spacer(),
          // 안 바뀌었으면 누를 것이 없다. 항상 켜 두면 "눌렀는데 아무 일도 안 난다" 가 된다.
          TextButton(
            onPressed: _dirty && !_sending ? _save : null,
            child: Text(
              _sending ? '저장 중…' : '저장',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _dirty && !_sending ? T.warmText : T.textMuted,
              ),
            ),
          ),
        ]),
      );

  Widget _saveAsCourseCard() => GestureDetector(
        onTap: () async {
          final course = await CourseSaveSheet.open(
            context,
            walkId: widget.walkId,
            km: widget.km,
            // 코스 저장은 분 단위다(코스 카드가 "약 N분" 으로 읽는다) — 여기서 내린다.
            durationS: widget.durationS,
            walks: widget.repository,
            courses: widget.courses,
          );
          if (course == null || !mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${course.name}" 코스로 남겼어요')),
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: T.line),
          ),
          child: Row(children: [
            const Icon(Icons.route_rounded, size: 18, color: T.warmText),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('이 길을 코스로 남기기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
                SizedBox(height: 3),
                Text('시작·끝 100m 는 빼고 저장해요',
                    style: TextStyle(fontSize: 12, color: T.textMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: T.textFaint),
          ]),
        ),
      );

  /// 산책 중 찍은 사진(#450) — 4:5 타일을 한 줄로. 첫 장이 크게, 나머지는 옆으로 넘긴다.
  Widget _photosCard() => SizedBox(
        key: const Key('detail-photos'),
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: widget.photoUrls.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 160,
              height: 200,
              child: Image.network(widget.photoUrls[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: T.surface,
                      child: const Icon(Icons.broken_image_outlined, color: T.textMuted))),
            ),
          ),
        ),
      );

  Widget _summaryCard() {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    final t = widget.startedAt;
    final label =
        '${t.year}. ${t.month.toString().padLeft(2, '0')}. ${t.day.toString().padLeft(2, '0')} '
        '(${week[t.weekday - 1]}) ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    Widget cell(String v, String l) => Expanded(
          child: Column(children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(l, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
          ]),
        );

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // 날짜는 길이가 정해져 있다 — 줄어들어도 되는 것은 장소뿐이라 Flexible 을 거기만 건다.
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
          // 어디를 걸었는지는 저장할 때 적은 것이다(#547). 예전에는 그 값이 화면까지 와 있는데
          // 그리는 자리가 없어서, 적은 사람이 다시 볼 수 없었다.
          if (widget.placeTitle != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.place_outlined, size: 13, color: T.textMuted),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                widget.placeTitle!,
                key: const Key('detail-place'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textMuted),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        Row(children: [
          cell('${widget.km.toStringAsFixed(1)}km', '거리'),
          Container(width: 1, height: 30, color: T.line),
          cell(walkTimeLabel(widget.durationS), '시간'),
        ]),
      ]),
    );
  }

  Widget _memoCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('오늘의 산책',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 4),
        const Text('나중에 언제든 고칠 수 있어요',
            style: TextStyle(fontSize: 12, color: T.textMuted)),
        const SizedBox(height: 12),
        TextField(
          controller: _memo,
          maxLines: 10,
          minLines: 6,
          // 서버가 @Size(max=500) 이다. 여기서 막지 않으면 저장을 누른 뒤에 400 을 받는다.
          maxLength: WalkRepository.maxMemoLength,
          style: const TextStyle(fontSize: 14, height: 1.65, color: T.textPrimary),
          decoration: const InputDecoration(
            hintText: '우리 아이의 컨디션, 만난 친구, 특별했던 순간을 적어보세요...',
            hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ]),
    );
  }
}
