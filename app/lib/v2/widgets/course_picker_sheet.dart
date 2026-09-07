// 글에 붙일 코스 고르기 — 이슈 #339.
//
// ## 왜 비공개를 그냥 못 붙이나
//
// 비공개 코스를 붙이면 **남들에게는 빈 자리로 보인다.** 서버가 몰래 공개로 바꾸지도 않는다 —
// 공개는 사용자가 하는 일이다. 그래서 여기서 "공개하고 붙이기" 를 한 번 묻는다. 누르면
// 그때 공개로 바뀐다(`PUT /api/courses/{id}/visibility`).
import 'package:flutter/material.dart';

import '../data/course_repository.dart';
import '../theme/app_tokens.dart';
import '../walk/route_image.dart';

class CoursePickerSheet {
  const CoursePickerSheet._();

  /// 고른 코스를 준다. 아무것도 안 고르면 `null`.
  static Future<Course?> open(BuildContext context, {CourseRepository? courses}) =>
      showModalBottomSheet<Course>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => _Body(courses: courses ?? CourseRepository()),
      );
}

class _Body extends StatefulWidget {
  const _Body({required this.courses});

  final CourseRepository courses;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  List<Course>? _mine;
  String? _error;
  int? _publishing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mine = await widget.courses.mine();
      if (!mounted) return;
      setState(() => _mine = mine);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '코스를 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    }
  }

  Future<void> _pick(Course course) async {
    if (course.isPublic) {
      Navigator.pop(context, course);
      return;
    }
    // 비공개다 — 공개로 바꾼 **뒤에** 붙인다. 순서를 뒤집으면 글에 빈 자리가 남는다.
    setState(() => _publishing = course.id);
    try {
      final published = await widget.courses.setVisibility(course.id, isPublic: true);
      if (!mounted) return;
      Navigator.pop(context, published);
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공개로 바꾸지 못했어요 · 잠시 뒤 다시')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFAFCFAFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
          ),
        ),
        const SizedBox(height: 18),
        const Text('어느 코스를 붙일까요',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 6),
        const Text('공개한 코스만 글에 보여요. 비공개는 누르면 공개로 바꿔서 붙여요.',
            style: TextStyle(fontSize: 13, color: T.textSecondary)),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 13, color: T.textMuted))
        else if (mine == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (mine.isEmpty)
          const Text('아직 만든 코스가 없어요 · 산책 회고에서 "이 길을 코스로 남기기" 로 만들 수 있어요',
              style: TextStyle(fontSize: 13, color: T.textMuted))
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: mine.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _row(mine[i]),
            ),
          ),
      ]),
    );
  }

  Widget _row(Course course) {
    final busy = _publishing == course.id;
    return GestureDetector(
      onTap: busy ? null : () => _pick(course),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          SizedBox(
            width: 64,
            height: 44,
            child: course.path.length >= 2
                ? CustomPaint(
                    painter: RouteCanvasPainter(
                      RouteArt(
                        lngLat: course.path,
                        distanceLabel: '',
                        timeLabel: '',
                        dateLabel: '',
                      ),
                      withCaption: false,
                    ),
                  )
                : const Icon(Icons.route_rounded, size: 20, color: Color(0xFFBBB3CC)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 3),
              Text('${course.km.toStringAsFixed(2)}km · ${course.isPublic ? '공개' : '나만 봄'}',
                  style: const TextStyle(fontSize: 12, color: T.textMuted)),
            ]),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Text(course.isPublic ? '붙이기' : '공개하고 붙이기',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFE07A4E))),
        ]),
      ),
    );
  }
}
