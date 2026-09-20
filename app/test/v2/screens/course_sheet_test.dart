// 홈의 "오늘의 코스" 카드를 누르면 장소 시트가 열린다 — 이슈 #723.
//
// 사장님 발견: 카드를 눌러도 아무 일도 없었다. 여기서 재는 것 셋.
//   - 카탈로그 장소면 지도 탭과 같은 시트가 열리고 **걷기 · 글쓰기** 가 있다
//   - "이 코스 걷기" 는 **카드가 잰 거리**를 들고 `startWalk` 로 간다 — 멀면 시작하지 않는다(#724)
//   - 내 코스는 아직 열 것이 없다 — 아무 시트도 안 뜬다
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/domain/course_recommender.dart';
import 'package:heat_trip_flutter/v2/domain/walk_destination.dart';
import 'package:heat_trip_flutter/v2/screens/course_sheet.dart';
import 'package:heat_trip_flutter/v2/screens/location_priming_sheet.dart';
import 'package:heat_trip_flutter/v2/screens/walk_start_point_sheet.dart';

const _place = PetPlace(
  contentId: '2745594',
  title: '성수연방',
  contentTypeId: '12',
  summary: '카페와 공방이 모인 곳',
  addr: '서울 성동구 성수이로14길',
  image: '',
  tel: '',
  lat: 37.5417,
  lng: 127.0569,
  distM: 810,
);
const _course = CourseCandidate(
  id: '2745594',
  title: '성수연방',
  kind: CourseKind.park,
  distanceM: 810,
  source: 'kto',
  contentId: '2745594',
  lat: 37.5417,
  lng: 127.0569,
);
const _mine = CourseCandidate(
    id: 'course:7', title: '아침 한 바퀴', kind: CourseKind.myCourse, distanceM: 200, lengthM: 2000);

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

/// 글 화면이 서버 대신 부를 빈 목록 — 시트 검사는 문이 열리는지만 본다.
CommunityRepository _emptyFeed() => CommunityRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((_) async => http.Response(
            jsonEncode({'items': const [], 'nextCursor': null, 'hasMore': false}), 200,
            headers: const {'content-type': 'application/json; charset=utf-8'})),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

Future<void> _pump(WidgetTester t, CourseCandidate course, PetPlace? place) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
            onPressed: () => openCourse(ctx, course, place, repository: _emptyFeed()), child: const Text('열기')),
      ),
    ),
  ));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationPriming.checkPermission = () async => LocationPermission.whileInUse;
  });

  tearDown(() {
    AuthState.resetForTest();
    LocationPriming.resetForTest();
    WalkStartPointSheet.resetForTest();
  });

  testWidgets('카탈로그 장소면 지도 탭과 같은 장소 시트가 열린다 — 걷기 · 길찾기 · 글쓰기', (t) async {
    await _pump(t, _course, _place);
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();

    expect(find.text('성수연방'), findsWidgets);
    expect(find.text('이 코스 걷기'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('이 장소로 글쓰기'), findsOneWidget);
    expect(find.text('이 장소의 글 보기'), findsOneWidget, reason: '그 장소의 글을 모아 보는 문(#723 조각 2)');
  });

  testWidgets('"이 장소의 글 보기" 는 그 장소의 글 화면으로 간다', (t) async {
    await _pump(t, _course, _place);
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.tap(find.text('이 장소의 글 보기'));
    await t.pumpAndSettle();

    expect(find.text('성수연방의 글'), findsOneWidget);
    expect(find.byKey(const Key('place-posts-empty')), findsOneWidget, reason: '가짜 저장소가 빈 목록을 줬다');
  });

  testWidgets('"이 코스 걷기" 는 카드가 잰 거리를 들고 startWalk 로 간다 — 810m 는 멀어서 시작하지 않는다',
      (t) async {
    WalkDestination? asked;
    WalkStartPointSheet.ask = (_, __, dest) async {
      asked = dest;
      return null;
    };
    await _pump(t, _course, _place);
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(asked, isNotNull, reason: '810m 는 멀다 — "떨어져 있어요" 가 떠야 한다(#724)');
    expect(asked!.distanceM, 810);
    expect(asked!.lat, 37.5417);
    expect(asked!.lng, 127.0569);
  });

  testWidgets('내 코스는 아직 열 것이 없다 — 아무 시트도 안 뜬다', (t) async {
    await _pump(t, _mine, null);
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();

    expect(find.text('이 코스 걷기'), findsNothing);
    expect(find.text('이 장소로 글쓰기'), findsNothing);
  });
}
