// 홈의 "오늘의 코스" 카드를 눌렀을 때 — 이슈 #723.
//
// 사장님 발견(2026-09-20): 카드를 눌러도 아무 일도 없었다 — 칩 하나만 반응했다. 지도 탭에는
// 장소 시트(`PlaceSheet`: 사진 · 이름 · 거리 · 요약 · 주소 · 동작)가 이미 있었고, 홈에서 그것을
// 못 열 뿐이었다. 카드는 위젯이라 화면을 import 하지 않으므로(`legacy_shell_reachability_test`)
// 홈이 이 함수를 `onOpen` 에 꽂는다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart' show CommunityBoard;
import '../data/pet_places_repository.dart';
import '../data/walk_repository.dart' show WalkPlaceRef;
import '../domain/course_recommender.dart';
import '../domain/walk_destination.dart';
import '../theme/app_tokens.dart';
import '../widgets/place_sheet.dart';
import 'post_write_screen.dart';
import 'start_walk.dart';

/// 카드 본문을 눌렀을 때. [place] 는 카드가 후보를 준 곳(`CourseCandidateSource.placeOf`)에서
/// 받아 온 카탈로그 장소다 — 있으면 시트를 열고, **내 코스는 아직 열 것이 없다**(`null`).
/// 내 코스의 상세(경로 그림 · 기록)는 #723 의 다음 조각이다.
Future<void> openCourse(BuildContext context, CourseCandidate course, PetPlace? place) async {
  final p = place;
  if (p == null) return;
  await PlaceSheet.show(
    context,
    p,
    actions: (sheetCtx, messenger) => [
      // 홈 카드의 칩과 **같은 일**을 한다(#724) — 300m 안이면 바로 추적, 멀면 "떨어져 있어요".
      PlaceSheetAction(
        icon: Icons.directions_walk_rounded,
        label: '이 코스 걷기',
        primary: true,
        onTap: () async {
          Navigator.pop(sheetCtx);
          await startWalk(
            context,
            place: WalkPlaceRef(title: p.title, source: p.source, contentId: p.contentId),
            // 거리는 카드가 잰 값이다 — 시트의 `distM` 은 목록을 받을 때의 원점 기준이라 다를 수 있다.
            destination: WalkDestination(lat: p.lat, lng: p.lng, distanceM: course.distanceM),
          );
        },
      ),
      if (p.tel.isNotEmpty) PlaceActions.call(p, messenger),
      PlaceActions.directions(p, messenger, primary: false),
    ],
    footer: Builder(builder: (sheetCtx) => placeWriteFooter(context, sheetCtx, p)),
  );
}

/// '이 장소로 글쓰기' — 이슈 #172. 지도 탭의 `_writeAboutPlace` 와 같은 것이다(#723 에서 시트를
/// 완전히 공용으로 뺄 때 그쪽도 이리로 옮긴다).
///
/// **장소 단위 UGC 가 차별화 논리다**(`market-competition.md:87`). 나중에 붙이면 이미 쌓인
/// 글에는 영영 장소가 없다. 그래서 처음부터 `contentId` 를 싣는다. `contentId` 가 비어 있으면
/// 안 싣는다 — 서버가 모르는 장소를 글에 묶으면 아무 장소와도 안 이어지는 글이 남는다.
///
/// 시트를 먼저 닫는다. 그리고 `sheetCtx` 가 아니라 화면의 [screenContext] 로 민다 — 닫힌 시트의
/// 컨텍스트는 죽어 있다.
Widget placeWriteFooter(BuildContext screenContext, BuildContext sheetCtx, PetPlace p) {
  final linkable = p.contentId.isNotEmpty;
  return GestureDetector(
    onTap: () {
      Navigator.pop(sheetCtx);
      writePost(
        screenContext,
        initialBoard: CommunityBoard.petPlace,
        loc: p.title,
        contentId: linkable ? p.contentId : null,
      );
    },
    behavior: HitTestBehavior.opaque,
    child: Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: T.surface, borderRadius: BorderRadius.circular(14)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.edit_outlined, size: 16, color: T.textSecondary),
        SizedBox(width: 7),
        Text('이 장소로 글쓰기',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textSecondary)),
      ]),
    ),
  );
}
