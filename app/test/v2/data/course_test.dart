// 코스 — 잘라내기 규칙과 요청 모양 (#339).
//
// 자르는 것은 **서버**다. 앱의 `trimCourseEnds` 는 저장 전에 "이만큼이 빠집니다" 를 보여 주기
// 위한 같은 규칙의 사본이라, 여기서 재는 것은 그 사본이 서버와 같은 답을 내는가다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/course_repository.dart';
import 'package:heat_trip_flutter/v2/domain/course_path.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'refresh-token';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

({CourseRepository repo, List<http.Request> seen}) _repo(
  http.Response Function(http.Request request) answer,
) {
  final seen = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      return answer(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CourseRepository(baseUrl: _base, client: client), seen: seen);
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 계약의 `Course` 그대로 — 서버가 주는 키다.
Map<String, Object?> _courseJson({Object? path, String visibility = 'private'}) => {
      'id': 5,
      'walkId': 12,
      'name': '서울숲 한 바퀴',
      'note': '그늘이 많아요',
      'tags': ['shade', 'poopbag'],
      'path': path ?? [[127.041, 37.5445], [127.045, 37.5445]],
      'distanceM': 400,
      'durationS': 900,
      'visibility': visibility,
      'mine': true,
      'createdAt': '2026-09-07T04:00:00Z',
    };

/// 동쪽으로 [stepM]m 씩 [count] 개. 위도 37.5 에서 경도 1도는 약 88,000m 다.
List<List<double>> _line(int count, double stepM) {
  final stepLng = stepM / 88000.0;
  return [for (var i = 0; i < count; i++) [127.0400 + stepLng * i, 37.5445]];
}

void main() {
  group('잘라내기 — 서버와 같은 규칙', () {
    test('양 끝 100m 를 버린다', () {
      final trimmed = trimCourseEnds(_line(61, 10));

      expect(trimmed, isNotNull);
      expect(coursePathLengthMeters(trimmed), closeTo(400, 25));
      expect(trimmed!.first[0], greaterThan(127.0400));
    });

    test('점이 드물어도 거리로 자른다 — 개수가 기준이 아니다', () {
      expect(coursePathLengthMeters(trimCourseEnds(_line(13, 50))), closeTo(400, 25));
    });

    test('300m 가 안 되면 null — 자르고 나면 선이 남지 않는다', () {
      expect(trimCourseEnds(_line(21, 10)), isNull);
      expect(trimCourseEnds(_line(26, 10)), isNull);
      expect(trimCourseEnds(_line(31, 10)), isNotNull);
    });

    test('점이 둘 이하면 null — 지어내지 않는다', () {
      expect(trimCourseEnds(null), isNull);
      expect(trimCourseEnds(const []), isNull);
      expect(trimCourseEnds(_line(2, 10)), isNull);
    });
  });

  group('요청 모양', () {
    test('선을 보내지 않는다 — walkId 만 보낸다', () async {
      final r = _repo((_) => _json(_courseJson(), status: 201));

      await r.repo.create(walkId: 12, name: '서울숲 한 바퀴', note: '그늘이 많아요', tags: ['shade']);

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body['walkId'], 12);
      expect(body['name'], '서울숲 한 바퀴');
      expect(body['tags'], ['shade']);
      expect(body.containsKey('path'), isFalse,
          reason: '앱이 자른 선을 보내면 안 자르는 옛 앱이 집 앞을 공개한다');
      expect(body['visibility'], 'private', reason: '기본은 비공개다');
    });

    test('공개로 만들면 visibility 가 public 이다', () async {
      final r = _repo((_) => _json(_courseJson(visibility: 'public'), status: 201));

      final course = await r.repo.create(walkId: 12, name: '동네 한 바퀴', isPublic: true);

      expect((jsonDecode(r.seen.single.body) as Map)['visibility'], 'public');
      expect(course.isPublic, isTrue);
    });

    test('공개 목록을 부를 때 좌표를 붙이지 않는다 — 가까운 것 고르기는 기기가 한다', () async {
      final r = _repo((_) => _json([_courseJson(visibility: 'public')]));

      await r.repo.publicCourses();

      final uri = r.seen.single.url;
      expect(uri.path, '/api/courses/public');
      expect(uri.queryParameters, isEmpty);
    });
  });

  group('실패의 종류', () {
    test('400 은 "이 기록으로는 못 만든다" 이고 서버 문구를 들고 온다', () async {
      final r = _repo((_) => _json({
            'error': {'code': 'BAD_REQUEST', 'message': '시작·끝 100m 를 빼면 남는 길이 없습니다.'}
          }, status: 400));

      await expectLater(
        r.repo.create(walkId: 12, name: '짧은 길'),
        throwsA(isA<CourseFailure>()
            .having((f) => f.kind, 'kind', CourseFailureKind.tooShort)
            .having((f) => f.message, 'message', contains('남는 길이 없습니다'))),
      );
    });

    test('404 는 남의 것과 없는 것을 구분하지 않는다', () async {
      final r = _repo((_) => _json({'error': {'code': 'NOT_FOUND', 'message': '없습니다'}}, status: 404));

      await expectLater(
        r.repo.one(999),
        throwsA(isA<CourseFailure>().having((f) => f.kind, 'kind', CourseFailureKind.notFound)),
      );
    });

    test('500 은 네트워크로 묶는다 — 다시 보내면 되는 것과 아닌 것만 가른다', () async {
      final r = _repo((_) => _json({'error': {'code': 'INTERNAL', 'message': '서버'}}, status: 500));

      await expectLater(
        r.repo.mine(),
        throwsA(isA<CourseFailure>().having((f) => f.kind, 'kind', CourseFailureKind.network)),
      );
    });
  });

  group('읽는 모양', () {
    test('목록의 항목은 시작점 하나만 들고 온다', () async {
      final r = _repo((_) => _json([
            _courseJson(path: [[127.041, 37.5445]], visibility: 'public'),
            {'id': 'broken'},
          ]));

      final courses = await r.repo.publicCourses();

      expect(courses, hasLength(1), reason: '모양이 깨진 항목은 버리고 나머지를 살린다');
      expect(courses.single.start, [127.041, 37.5445]);
      expect(courses.single.isPublic, isTrue);
    });

    test('산책을 지운 코스는 walkId 가 null 이다 — 코스는 남는다', () async {
      final json = _courseJson();
      json['walkId'] = null;
      final r = _repo((_) => _json(json));

      final course = await r.repo.one(5);

      expect(course.walkId, isNull);
      expect(course.name, '서울숲 한 바퀴');
    });
  });
}
