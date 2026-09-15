// 산책 하나를 코스로 남기는 시트 — 이슈 #339.
//
// ## 무엇을 미리 보여 주는가
//
// **잘려 나갈 부분을 먼저 보여 준다.** 코스로 남기는 일은 "이 길 좋아요" 를 남기는 일이지
// 사는 곳을 알리는 일이 아니다. 그래서 저장을 누르기 전에 양 끝 100m 가 빠진 선을 그려 주고,
// 그 아래 한 줄로 그 사실을 말한다.
//
// 자르는 것은 서버다(`walk.course.CoursePath`). 여기 그림은 같은 규칙의 사본이라
// **예고**이고, 저장 뒤에는 서버가 돌려준 선을 그린다.
import 'package:flutter/material.dart';

import '../data/course_repository.dart';
import '../data/walk_repository.dart';
import '../domain/course_path.dart';
import '../domain/walk_labels.dart';
import '../theme/app_tokens.dart';
import '../walk/route_image.dart';

/// 태그 셋 — 서버의 `leash`·`poopbag`·`shade` 와 같은 값이다.
const Map<String, String> kCourseTagLabels = {
  'leash': '목줄 규정 있음',
  'poopbag': '배변봉투통 있음',
  'shade': '그늘·물 있음',
};

class CourseSaveSheet {
  const CourseSaveSheet._();

  /// 시트를 연다. 저장했으면 그 코스를, 아니면 `null` 을 준다.
  static Future<Course?> open(
    BuildContext context, {
    required int walkId,
    required double km,
    required int durationS,
    WalkRepository? walks,
    CourseRepository? courses,
  }) =>
      showModalBottomSheet<Course>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => _Body(
          walkId: walkId,
          km: km,
          durationS: durationS,
          walks: walks ?? WalkRepository(),
          courses: courses ?? CourseRepository(),
        ),
      );
}

class _Body extends StatefulWidget {
  const _Body({
    required this.walkId,
    required this.km,
    required this.durationS,
    required this.walks,
    required this.courses,
  });

  final int walkId;
  final double km;
  /// 걸린 시간 — 초다(#537). 분으로 받으면 1분이 안 되는 산책이 `0분` 이 된다.
  final int durationS;
  final WalkRepository walks;
  final CourseRepository courses;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final Set<String> _tags = {};

  bool _loading = true;
  bool _saving = false;
  bool _isPublic = false;

  /// 잘라 낸 뒤의 선. `null` 이면 코스로 만들 수 없다 — 이유를 [_reason] 이 말한다.
  List<List<double>>? _preview;
  String? _reason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final walk = await widget.walks.walk(widget.walkId);
      final path = walk.path;
      if (!mounted) return;
      if (path == null || path.length < 2) {
        setState(() {
          _loading = false;
          _reason = '경로가 없는 기록이라 코스로 남길 수 없어요.';
        });
        return;
      }
      final trimmed = trimCourseEnds(path);
      setState(() {
        _loading = false;
        _preview = trimmed;
        _reason = trimmed == null
            ? '시작·끝 $kCourseTrimMeters' 'm 를 빼면 남는 길이 없어요. 300m 쯤은 걸어야 코스가 돼요.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _reason = '기록을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _preview == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코스 이름을 적어 주세요')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final course = await widget.courses.create(
        walkId: widget.walkId,
        name: name,
        note: _note.text.trim(),
        tags: _tags.toList(),
        isPublic: _isPublic,
      );
      if (!mounted) return;
      Navigator.pop(context, course);
    } on CourseFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (failure.kind) {
          CourseFailureKind.tooShort => failure.message ?? '이 기록으로는 코스를 만들 수 없어요',
          CourseFailureKind.notFound => '그 기록을 찾을 수 없어요',
          CourseFailureKind.network => '지금은 저장하지 못했어요 · 잠시 뒤 다시',
        }),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.of(context).padding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                      color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 18),
              const Text('코스로 남기기',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 6),
              const Text('시작·끝 100m 는 저장하지 않아요 — 집 앞이 남지 않게요.',
                  style: TextStyle(fontSize: 13, color: T.textSecondary)),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_reason != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(_reason!, style: const TextStyle(fontSize: 13.5, color: T.textMuted)),
                )
              else ...[
                _previewCard(),
                const SizedBox(height: 16),
                _field(_name, '코스 이름', '예: 서울숲 한 바퀴', 60),
                const SizedBox(height: 12),
                _field(_note, '한 줄 소개', '예: 그늘이 많고 물 마실 곳이 있어요', 200),
                const SizedBox(height: 16),
                const Text('이 길은',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in kCourseTagLabels.entries) _tagChip(entry.key, entry.value),
                  ],
                ),
                const SizedBox(height: 16),
                _visibilityRow(),
                const SizedBox(height: 18),
                _saveButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewCard() {
    final preview = _preview!;
    final meters = coursePathLengthMeters(preview).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 150,
        child: CustomPaint(
          painter: RouteCanvasPainter(
            RouteArt(
              lngLat: preview,
              distanceLabel: '${(meters / 1000).toStringAsFixed(2)}km',
              timeLabel: walkTimeLabel(widget.durationS),
              dateLabel: '코스로 남길 구간',
            ),
            withCaption: false,
          ),
          size: Size.infinite,
        ),
      ),
      const SizedBox(height: 8),
      Text('${widget.km.toStringAsFixed(2)}km 중 ${(meters / 1000).toStringAsFixed(2)}km 가 코스가 돼요',
          style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
    ]);
  }

  Widget _field(TextEditingController controller, String label, String hint, int max) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const SizedBox(height: 7),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: T.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: controller,
              maxLength: max,
              style: const TextStyle(fontSize: 14, color: T.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 14, color: T.textMuted),
                border: InputBorder.none,
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      );

  Widget _tagChip(String key, String label) {
    final on = _tags.contains(key);
    return GestureDetector(
      onTap: () => setState(() => on ? _tags.remove(key) : _tags.add(key)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: on ? T.warmMid : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? Colors.transparent : T.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : T.textSecondary)),
      ),
    );
  }

  Widget _visibilityRow() => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('이웃에게 보이기',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(
              _isPublic
                  ? '지도의 "이웃 코스" 에 나와요 — 잘라 낸 선만 보여요'
                  : '나만 봐요. 나중에 언제든 공개할 수 있어요',
              style: const TextStyle(fontSize: 12, color: T.textMuted),
            ),
          ]),
        ),
        Switch(
          value: _isPublic,
          activeThumbColor: T.warmMid,
          onChanged: (next) => setState(() => _isPublic = next),
        ),
      ]);

  Widget _saveButton() => GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [T.warmStart, T.warmEnd],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(_saving ? '저장 중…' : '코스로 저장',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      );
}
