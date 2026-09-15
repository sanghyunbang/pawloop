// 산책 저장 뒤 — 스낵바에 "보기", 케어 산책 칸에도 남긴다 (#326).
//
// 가짜 산책 저장소(서버 저장 성공)와 가짜 가족 저장소(가족 있음)를 꽂고 진짜 화면을 세운다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/app/navigator_keys.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_care_link.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/create_screen.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';

class _Walks implements WalkRepository {
  int saved = 0;
  @override
  Future<List<ServerPet>> pets() async => const [
        ServerPet(id: 1, name: 'Bori', species: ServerPetSpecies.dog, size: ServerPetSize.medium, neutered: false),
      ];
  @override
  Future<ServerWalk> saveWalk({
    required int dogId,
    List<int> dogIds = const [],
    required String clientWalkId,
    required DateTime startedAt,
    DateTime? endedAt,
    required int distanceM,
    required int durationS,
    List<List<double>>? path,
    List<int>? pathT,
    String? memo,
    String? weather,
    WalkPlaceRef? place,
    List<int> mediaIds = const [],
  }) async {
    saved++;
    return ServerWalk(
      id: 7,
      dogId: dogId,
      clientWalkId: clientWalkId,
      startedAt: startedAt,
      endedAt: endedAt,
      distanceM: distanceM,
      durationS: durationS,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';
  @override
  Future<String?> readRefreshToken() async => 'refresh-token';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

({FamilyRepository repo, List<http.Request> posts}) _family() {
  final posts = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
      }
      if (request.method == 'POST') {
        posts.add(request);
        return _json({
          'id': 99, 'dogId': null, 'groupId': 3, 'type': 'walk',
          'doneBy': {'userId': 11, 'nickname': '나'}, 'occurredAt': '2026-09-07T09:05:00', 'memo': null,
        }, status: 201);
      }
      return _json(const []);
    }),
    baseUrl: 'https://api.example.test',
    store: _Tokens(),
  );
  return (repo: FamilyRepository(baseUrl: 'https://api.example.test', client: client), posts: posts);
}

WalkDraft _tracked() => WalkDraft.fresh(
      startedAt: DateTime(2026, 9, 7, 9, 0),
      endedAt: DateTime(2026, 9, 7, 9, 12),
      distanceM: 850,
      durationS: 720,
      path: const [],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated; // 기록 화면이 열려도 서버를 안 부른다
  });
  tearDown(AuthState.resetForTest);

  testWidgets('저장되면 "산책이 기록됐어요 · 보기" 이고, 케어 산책 칸에도 남긴다', (t) async {
    final walks = _Walks();
    final family = _family();
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      home: CreateScreen(
        draft: _tracked(),
        repository: walks,
        careLink: WalkCareLink(repository: family.repo),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('저장'));
    await t.pumpAndSettle();

    expect(walks.saved, 1);
    expect(find.text('산책이 기록됐어요'), findsOneWidget);
    expect(find.text('보기'), findsOneWidget);
    expect(find.textContaining('🐾'), findsNothing, reason: '시스템 이모지는 안 쓴다');
    expect(family.posts, hasLength(1), reason: '케어 산책 칸');
    expect(jsonDecode(family.posts.single.body)['type'], 'walk');

    await t.tap(find.text('보기'));
    await t.pumpAndSettle();
    expect(find.byType(MyRecordsScreen), findsOneWidget);
  });

  testWidgets('스낵바는 시간이 지나면 사라진다 — 탭 바를 계속 덮으면 안 된다', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      home: CreateScreen(
        draft: _tracked(),
        repository: _Walks(),
        careLink: WalkCareLink(repository: _family().repo),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    expect(find.text('산책이 기록됐어요'), findsOneWidget);

    // 적어 둔 시간(3.2초)의 세 배를 기다린다.
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();

    expect(find.text('산책이 기록됐어요'), findsNothing,
        reason: 'SnackBar 는 action 이 있으면 persist 가 기본 참이라(Flutter 3.32) duration 을 '
            '무시하고 영원히 남는다. 이 스낵바는 화면 맨 아래 탭 바를 덮으므로, 산책을 저장한 '
            '사람은 탭을 못 누른다');
  });

  testWidgets('낭독기를 쓰면 그대로 남는다 — "보기" 까지 짚어 갈 시간이 필요하다', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      home: Builder(
        builder: (context) => MediaQuery(
          // 화면 낭독기가 켜진 기기다.
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: CreateScreen(
            draft: _tracked(),
            repository: _Walks(),
            careLink: WalkCareLink(repository: _family().repo),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();

    expect(find.text('산책이 기록됐어요'), findsOneWidget,
        reason: '옛 플러터의 조건이 그것이었다 — 버튼이 있는 말풍선은 낭독기를 쓸 때만 남는다. '
            '눈으로 읽는 사람에게는 3.2초, 짚어 가는 사람에게는 누를 때까지');
  });
}
