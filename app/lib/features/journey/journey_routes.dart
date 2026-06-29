import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/app/navigator_keys.dart';
import 'package:heat_trip_flutter/features/journey/domain/models.dart';
import 'package:heat_trip_flutter/features/journey/presentation/screens/diary_detail_screen.dart';
import 'package:heat_trip_flutter/features/journey/presentation/screens/journey_detail_screen.dart';
import 'package:heat_trip_flutter/features/journey/presentation/screens/new_diary_screen.dart';
import 'package:heat_trip_flutter/features/feed/presentation/feed_screen.dart';

/// Journey(저니/라이브러리) 기능 라우트 모음
/// 중앙 라우터에서: `StatefulShellBranch(routes: journeyRoutes)` 형태로 끼워 넣습니다.
final List<RouteBase> journeyRoutes = [
  GoRoute(
    path: '/journey',
    name: 'journey',
    builder: (context, state) => const FeedScreen(),
    routes: [
      GoRoute(
        path: 'journey/:id',
        name: 'journeyDetail',
        builder: (context, state) {
          final idStr = state.pathParameters['id']!;
          final id = int.parse(idStr); // String → int 변환
          final schedule = state.extra as Schedule?; // (선택) 초기 렌더용
          return JourneyDetailScreen(id: id, initial: schedule);
        },
        routes: [
          // ✅ 스케줄 연동 새 일기
          GoRoute(
            path: 'diary/new',
            name: 'newDiaryForSchedule',
            builder: (context, state) => NewDiaryForScheduleRoute(state: state),
          ),
          GoRoute(
            path: 'diary/:entryId',
            name: 'diaryDetail',
            builder: (context, state) {
              final entryIdStr = state.pathParameters['entryId'];

              // entryId가 없거나 숫자가 아니면 null
              final entryId = int.tryParse(entryIdStr ?? '');

              // extra로 전달된 diaryEntry
              final diaryEntry = state.extra as DiaryEntry?;

              if (diaryEntry == null) {
                // diaryEntry 없으면 빈 화면, 또는 다른 안내 문구, 혹은 기본 화면
                return DiaryDetailScreen(entry: null);
              }

              return DiaryDetailScreen(entry: diaryEntry);
            },
          ),
        ],
      ),
      // ✅ Diary 탭에서 진입 (스케줄 미연동) — 추천 장소 연동 시 extra로 장소 전달
      // 루트 내비게이터로 풀스크린 표시(바텀네비 위) → 브랜치 스택에 끼지 않음.
      GoRoute(
        path: 'diary/new',
        name: 'newDiary',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map) {
            return NewDiaryScreen(
              placeId: extra['placeId'] as int?,
              placeName: extra['placeName'] as String?,
              placeLocation: extra['placeLocation'] as String?,
            );
          }
          return const NewDiaryScreen();
        },
      ),
    ],
  ),
];
