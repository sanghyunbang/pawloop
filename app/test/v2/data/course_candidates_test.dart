// 후보 모으기 (#485) — 카탈로그의 걷는 곳과 내 코스만, 거리는 기기 안에서.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/course_candidates.dart';
import 'package:heat_trip_flutter/v2/data/course_repository.dart';
import 'package:heat_trip_flutter/v2/data/place_catalog_repository.dart';
import 'package:heat_trip_flutter/v2/domain/course_recommender.dart';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'token';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

const _base = 'https://api.example.test';

// 서울숲(37.5445, 127.0374) 근처 — 산책로 · 동네 길 · 놀이터 · 여행지 · 카페 · 병원 · 먼 곳.
const _catalog = '['
    '{"contentId":"trail:101","title":"서울숲 둘레길","source":"trail","category":"trail","contentTypeId":"","addr":"","image":"","tel":"","lng":127.0400,"lat":37.5450,"summary":"4.2km · 약 1시간","courseM":4200},'
    '{"contentId":"trail:lt9","title":"뚝섬 동네 길","source":"localtrail","category":"trail","contentTypeId":"","addr":"","image":"","tel":"","lng":127.0380,"lat":37.5440,"summary":"1.9km · 약 30분","courseM":1900},'
    '{"contentId":"pg:1","title":"성수 놀이터","source":"playground","category":"playground","contentTypeId":"","addr":"","image":"","tel":"","lng":127.0390,"lat":37.5460},'
    '{"contentId":"2733847","title":"서울숲","source":"kto","category":"","contentTypeId":"12","addr":"","image":"https://cdn/park.jpg","tel":"","lng":127.0374,"lat":37.5445},'
    '{"contentId":"9001","title":"강아지 카페","source":"kto","category":"","contentTypeId":"39","addr":"","image":"","tel":"","lng":127.0376,"lat":37.5446},'
    '{"contentId":"vet:1","title":"성수 동물병원","source":"vet","category":"vet","contentTypeId":"","addr":"","image":"","tel":"","lng":127.0377,"lat":37.5447},'
    '{"contentId":"trail:far","title":"한강 먼 길","source":"trail","category":"trail","contentTypeId":"","addr":"","image":"","tel":"","lng":127.1000,"lat":37.5445}'
    ']';

http.Response _json(String body, [int status = 200]) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('course_candidates_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  PlaceCatalogRepository catalog() => PlaceCatalogRepository(
        baseUrl: _base,
        cacheDirectory: () async => tmp,
        client: MockClient((request) async => _json(_catalog)),
      );

  CourseRepository courses(String body, {int status = 200, List<String>? seen}) => CourseRepository(
        baseUrl: _base,
        client: AuthedClient(
          inner: MockClient((request) async {
            seen?.add('${request.method} ${request.url}');
            return _json(body, status);
          }),
          baseUrl: _base,
          store: _NoTokens(),
        ),
      );

  test('2km 안의 산책로 · 동네 길 · 놀이터 · 여행지만 후보다 — 카페 · 병원 · 먼 길은 아니다', () async {
    final source = CourseCandidates(catalog: catalog(), courses: courses('[]'));

    final found = await source.around(lat: 37.5445, lng: 127.0374);

    final ids = found.map((c) => c.id).toSet();
    expect(ids, {'trail:101', 'trail:lt9', 'pg:1', '2733847'});
    expect(found.singleWhere((c) => c.id == 'trail:lt9').kind, CourseKind.localTrail);
    expect(found.singleWhere((c) => c.id == 'trail:101').kind, CourseKind.trail);
    expect(found.singleWhere((c) => c.id == 'pg:1').kind, CourseKind.playground);
    final park = found.singleWhere((c) => c.id == '2733847');
    expect(park.kind, CourseKind.park);
    expect(park.image, 'https://cdn/park.jpg');
    expect(park.distanceM, closeTo(0, 1));
    expect(park.lengthM, isNull, reason: '점 하나짜리 장소의 길이를 지어내지 않는다');
    expect(found.singleWhere((c) => c.id == 'trail:101').lengthM, 4200,
        reason: '계약의 courseM 이 추천이 쓰는 lengthM 이다 (#539)');
    expect(found.singleWhere((c) => c.id == 'trail:lt9').lengthM, 1900);
    expect(found.singleWhere((c) => c.id == 'pg:1').lengthM, isNull,
        reason: '놀이터는 코스가 아니라 길이가 없다 — 0 으로 눕히면 짧은 목표에서 산책로를 이긴다');
    expect(park.source, 'kto');
    expect(park.contentId, '2733847');
    expect(source.placeOf(park)?.contentId, '2733847', reason: '카드를 누르면 여는 장소 시트의 재료다(#723)');
    expect(source.placeOf(park)?.title, park.title);
  });

  test('목표 2km 면 1.9km 코스가 4.2km 코스와 바로 앞 공원을 이긴다 (#539)', () async {
    final source = CourseCandidates(catalog: catalog(), courses: courses('[]'));

    final found = await source.around(lat: 37.5445, lng: 127.0374);
    final ranked = CourseRecommender.rank(candidates: found, targetMinutes: 30);

    expect(ranked.first.targetKm, closeTo(2.0, 0.001));
    expect(ranked.first.course.id, 'trail:lt9',
        reason: '길이가 안 오던 동안에는 후보가 전부 같은 기본값을 먹어, 0m 앞의 서울숲이 1등이었다');
    expect(ranked.map((r) => r.course.id).toList().indexOf('trail:101'),
        greaterThan(ranked.map((r) => r.course.id).toList().indexOf('trail:lt9')),
        reason: '4.2km 는 목표에서 2.2km 멀다');
    expect(ranked.any((r) => r.course.id == '2733847'), isTrue,
        reason: '길이를 모르는 후보도 목록에서 사라지면 안 된다 — 지금의 0.5 자리 그대로');
  });

  test('내 코스는 시작점이 2km 안이면 코스 길이와 함께 든다 — 경로는 [경도, 위도] 순', () async {
    final seen = <String>[];
    final source = CourseCandidates(
      catalog: catalog(),
      courses: courses(
          '[{"id":7,"name":"아침 한 바퀴","path":[[127.0402,37.5455],[127.0420,37.5430]],"distanceM":2000,"durationS":1500,"visibility":"private","mine":true,"createdAt":"2026-09-10T07:00:00Z","tags":[]},'
          '{"id":8,"name":"먼 코스","path":[[127.2000,37.5455]],"distanceM":3000,"durationS":2000,"visibility":"private","mine":true,"createdAt":"2026-09-10T07:00:00Z","tags":[]}]',
          seen: seen),
    );

    final found = await source.around(lat: 37.5445, lng: 127.0374);

    final mine = found.singleWhere((c) => c.id == 'course:7');
    expect(mine.kind, CourseKind.myCourse);
    expect(mine.lengthM, 2000);
    expect(source.placeOf(mine), isNull, reason: '내 코스는 카탈로그 장소가 아니다 — 시트를 열 재료가 없다');
    expect(mine.distanceM, closeTo(270, 60), reason: '시작점(127.0402, 37.5455)까지 약 270m');
    expect(found.any((c) => c.id == 'course:8'), isFalse, reason: '시작점이 14km 밖');
    expect(seen.single, 'GET $_base/api/courses/me', reason: '좌표가 요청에 없다');
  });

  test('내 코스를 못 받아도(로그인 전 · 401) 카탈로그 후보는 그대로 온다', () async {
    final source = CourseCandidates(catalog: catalog(), courses: courses('{"error":"nope"}', status: 401));

    final found = await source.around(lat: 37.5445, lng: 127.0374);

    expect(found.map((c) => c.id), containsAll(['trail:101', 'pg:1']));
    expect(found.any((c) => c.isMine), isFalse);
  });

  test('includeMine 이 꺼져 있으면(게스트) 내 코스를 묻지도 않는다', () async {
    final seen = <String>[];
    final source = CourseCandidates(catalog: catalog(), courses: courses('[]', seen: seen), includeMine: false);

    await source.around(lat: 37.5445, lng: 127.0374);

    expect(seen, isEmpty);
  });
}
