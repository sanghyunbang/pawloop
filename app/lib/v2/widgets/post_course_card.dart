// 글에 붙은 코스 — 카드와 상세에 같은 모양으로 그린다 (#339).
//
// 선은 서버가 이미 **양 끝 100m 를 자르고 40점 이하로 줄여** 보낸 것이다. 여기서 다시
// 자르거나 줄이지 않는다 — 그리는 쪽이 규칙을 하나 더 갖게 되면 두 곳이 어긋난다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import '../walk/route_image.dart';

class PostCourseCard extends StatelessWidget {
  const PostCourseCard({super.key, required this.course, this.onTap});

  final PostCourse course;

  /// 누르면 어디로 갈지. 없으면 누를 수 없다 — 카드에서는 글로 들어가는 것이 먼저다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x0AFF8F63),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1FFF8F63)),
          ),
          child: Row(children: [
            SizedBox(
              width: 76,
              height: 52,
              child: course.drawable
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
                  : const Icon(Icons.route_rounded, size: 20, color: T.textFaint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.route_rounded, size: 14, color: T.warmText),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(course.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text('${course.km.toStringAsFixed(2)}km · 시작·끝은 빼고 그려요',
                    style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
              ]),
            ),
          ]),
        ),
      );
}
