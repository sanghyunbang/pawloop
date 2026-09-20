// 케어 카드가 **고른 아이**로 세고 기록한다 — 이슈 #563.
//
// ## 무엇이 있었나
//
// 이 앱의 목적은 업무 분담과 누락 방지다(#76) — "해당 동물을 누르면 누가 산책시켰고 누가
// 물 줬는지" 가 보여야 한다. 그런데 카드가 아이를 안 묻고 그룹 전체를 읽어서, 아이가 둘인
// 집에서는 **보리 이름 아래 카드가 누리 밥까지 셌다.** #561 이 넣은 "2회" 가 그 애매함을
// 오히려 더 드러냈다 — 보리한테 두 번인지 둘이 한 번씩인지 화면이 구별을 못 한다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'a';
  @override
  Future<String?> readRefreshToken() async => 'r';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body), status,
      headers: const {'content-type': 'application/json; charset=utf-8'});

const _bori = DogProfile(
    serverId: 1, name: '보리', breed: '푸들', size: DogSize.small, ageMonths: 24);
const _nuri = DogProfile(
    serverId: 2, name: '누리', breed: '시바', size: DogSize.medium, ageMonths: 48);

Map<String, Object?> _log(int id, String type) => {
      'id': id,
      'dogId': 1,
      'groupId': 3,
      'type': type,
      'doneBy': {'userId': 11, 'nickname': '아빠'},
      'occurredAt': '2026-09-16T10:39:00',
      'memo': null,
    };

({FamilyRepository repo, List<String> gets, List<String> posts}) fixture() {
  final gets = <String>[];
  final posts = <String>[];
  final repo = FamilyRepository(
    baseUrl: _base,
    client: AuthedClient(
      inner: MockClient((request) async {
        if (request.url.path == '/api/groups/me') {
          return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
        }
        if (request.method == 'POST') {
          posts.add(request.body);
          return _json(_log(99, 'water'), status: 201);
        }
        // 카드가 #560 부터 항목 목록도 읽는다. **gets 에는 안 담는다** — 이 파일이 재는
        // 것은 "아이를 물어보는 조회" 라, 섞으면 아래 hasLength 가 무엇을 세는지 흐려진다.
        // 카드가 #741 부터 오늘 일정도 읽는다. 이것도 **gets 에는 안 담는다** — 일정은 아이로
        // 거르지 않으므로(아이 없는 가족 일정도 물어야 한다) 여기서 셀 것이 아니다.
        if (request.url.path == '/api/schedules') return _json(const []);
        if (request.url.path.endsWith('/care-items')) {
          return _json([
            {
              'id': 2,
              'dogId': null,
              'name': '밥',
              'icon': 'meal',
              'systemType': 'meal',
              'dailyTarget': null,
              'sortOrder': 1,
              'archivedAt': null,
            },
            {
              'id': 1,
              'dogId': null,
              'name': '물',
              'icon': 'water',
              'systemType': 'water',
              'dailyTarget': null,
              'sortOrder': 0,
              'archivedAt': null,
            },
          ]);
        }
        gets.add(request.url.toString());
        return _json([_log(1, 'water')]);
      }),
      baseUrl: _base,
      store: _Tokens(),
    ),
  );
  return (repo: repo, gets: gets, posts: posts);
}

Future<void> _pump(WidgetTester t, FamilyRepository repo) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: TodayCareCard(repository: repo, myUserId: 11)),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => replacePets(const [_bori, _nuri]));
  tearDown(() => replacePets(const []));

  testWidgets('고른 아이의 기록만 읽는다 — 보리 카드가 누리 밥을 세면 안 된다 (#563)', (t) async {
    selectPet(0);
    final f = fixture();

    await _pump(t, f.repo);

    expect(f.gets.single, contains('dogId=1'),
        reason: '아이를 안 물으면 두 아이 기록이 한 카드에서 섞인다');
  });

  testWidgets('아이를 바꾸면 다시 읽는다 — 앞 아이의 기록이 남으면 안 된다 (#563)', (t) async {
    selectPet(0);
    final f = fixture();
    await _pump(t, f.repo);

    selectPet(1);
    await t.pumpAndSettle();

    expect(f.gets, hasLength(2));
    expect(f.gets.last, contains('dogId=2'),
        reason: '이 카드는 props 가 안 바뀌어서 홈이 다시 그려도 State 가 살아 있다 — '
            '신호를 직접 안 들으면 앞 아이의 기록이 남는다');
  });

  testWidgets('기록할 때도 아이를 싣는다 — 붙지 않으면 어느 아이 것인지 모른다 (#563)', (t) async {
    selectPet(1);
    final f = fixture();
    await _pump(t, f.repo);

    await t.tap(find.byKey(const Key('care-cell-meal')));
    await t.pumpAndSettle();

    expect(f.posts, hasLength(1));
    expect(jsonDecode(f.posts.single)['dogId'], 2);
  });

  testWidgets('아이가 한 마리도 없으면 아이 없이 읽고 기록한다 — 그 집도 케어를 쓴다', (t) async {
    replacePets(const []);
    final f = fixture();
    await _pump(t, f.repo);

    expect(f.gets.single, isNot(contains('dogId=')));

    await t.tap(find.byKey(const Key('care-cell-meal')));
    await t.pumpAndSettle();

    expect(jsonDecode(f.posts.single).containsKey('dogId'), isFalse,
        reason: '필수로 두면 아이를 한 마리도 등록 안 한 집은 아무것도 못 적는다');
  });
}
