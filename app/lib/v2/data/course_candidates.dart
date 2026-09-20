// 오늘의 코스 후보 모으기 (#485) — 기기 안 카탈로그와 내 코스를 한 목록으로.
//
// 좌표는 **인자로 받아 기기 안에서** 거리를 재는 데만 쓴다. 이 파일은 네트워크 클라이언트를
// 모르고(`http` · `AuthedClient` import 없음), 부르는 저장소 둘도 좌표를 요청에 싣지 않는다 —
// 카탈로그는 전국 한 벌을 통째로 받고(#276), 내 코스는 `GET /api/courses/me` 다. 소스 잠금은
// `course_recommender_no_network_test`.
import '../domain/course_recommender.dart';
import 'course_repository.dart';
import 'pet_places_repository.dart';
import 'place_catalog_repository.dart';

/// 후보를 주는 자리 — 위젯 테스트가 가짜를 꽂는다.
abstract class CourseCandidateSource {
  Future<List<CourseCandidate>> around({required double lat, required double lng});

  /// 후보의 **카탈로그 장소 그 자체** — 카드를 누르면 여는 장소 시트의 재료(#723). 내 코스는
  /// `null`. 후보(`CourseCandidate`)는 domain 이라 data 의 `PetPlace` 를 들 수 없어서 여기서
  /// 잇는다 — `course_recommender_no_network_test` 가 그 선을 잠근다.
  PetPlace? placeOf(CourseCandidate course);
}

class CourseCandidates implements CourseCandidateSource {
  CourseCandidates({
    PlaceCatalogRepository? catalog,
    CourseRepository? courses,
    this.includeMine = true,
  })  : _catalog = catalog ?? PlaceCatalogRepository.instance,
        _courses = courses ?? CourseRepository();

  /// 걸어서 가는 거리 — 추천기의 [CourseRecommender.maxDistanceM] 과 같다.
  static const int radiusM = 2000;

  /// 걷는 곳만. 병원 · 펫샵 · 카페는 목적지가 아니라 코스가 아니다.
  static const Set<String> walkableKeys = {'trail', 'playground', '12'};

  final PlaceCatalogRepository _catalog;
  final CourseRepository _courses;

  /// [around] 가 채운다 — 후보 id(= `contentId`) → 장소.
  final Map<String, PetPlace> _places = {};

  @override
  PetPlace? placeOf(CourseCandidate course) => _places[course.id];

  /// 로그인 전 · 오프라인이면 내 코스 없이 간다.
  final bool includeMine;

  @override
  Future<List<CourseCandidate>> around({required double lat, required double lng}) async {
    final out = <CourseCandidate>[];
    final places = await _catalog.nearby(lat: lat, lng: lng, radius: radiusM, limit: 200);
    for (final p in places) {
      if (!walkableKeys.contains(p.categoryKey)) continue;
      _places[p.contentId] = p;
      out.add(CourseCandidate(
        id: p.contentId,
        title: p.title,
        kind: kindOf(p),
        distanceM: p.distM,
        // 산책로만 길이를 안다(#539). 모르는 후보는 `null` 그대로 둔다 — 0 으로 눕히면
        // "길이가 0인 코스" 가 되어 목표가 짧을수록 공원이 산책로를 이긴다.
        lengthM: p.courseM?.toDouble(),
        image: p.image.isEmpty ? null : p.image,
        source: p.source,
        contentId: p.contentId,
        lat: p.lat,
        lng: p.lng,
      ));
    }
    if (includeMine) {
      try {
        for (final c in await _courses.mine()) {
          final start = c.start;
          if (start == null || start.length < 2) continue;
          // 경로는 `[경도, 위도]` 순이다(`WalkDraft.path` 와 같다).
          final d = haversineMeters(lat, lng, start[1], start[0]);
          if (d > radiusM) continue;
          out.add(CourseCandidate(
            id: 'course:${c.id}',
            title: c.name,
            kind: CourseKind.myCourse,
            distanceM: d,
            lengthM: c.distanceM.toDouble(),
            // 경로는 `[경도, 위도]` 순이다 — 위에서 거리를 잴 때와 같게 뒤집어 읽는다.
            lat: start[1],
            lng: start[0],
          ));
        }
      } on CourseFailure {
        // 로그인 전이거나 연결이 없다 — 카탈로그 후보만으로 간다.
      }
    }
    return out;
  }

  static CourseKind kindOf(PetPlace p) {
    if (p.categoryKey == 'playground') return CourseKind.playground;
    if (p.categoryKey == 'trail') return p.isLocalTrail ? CourseKind.localTrail : CourseKind.trail;
    return CourseKind.park;
  }
}
