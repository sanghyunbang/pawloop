// 편집이 **서버에 저장된다** — 이슈 #516.
//
// 2026-09-15 이전에는 `_save()` 가 메모리의 `kMyPets` 만 바꾸고 "이 기기에만 반영했어요 ·
// 서버 저장은 준비 중이에요" 라고 말했다. 그 말도 사실이 아니었다 — 기기에도 안 남아서,
// 앱을 껐다 켜면 `PetSync.load()` 가 서버 목록으로 통째로 갈아끼웠다. **한 번의 콜드
// 스타트에 편집이 전부 사라졌다.**
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/pet_sync.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/edit_screen.dart';

const String _base = 'https://api.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';
  @override
  Future<String?> readRefreshToken() async => 'RT-1';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

const _bori = DogProfile(
  serverId: 7,
  name: '보리',
  breed: '믹스견',
  size: DogSize.small,
  ageMonths: 30,
  neutered: false,
);

/// 서버가 돌려주는 한 마리. 계약의 `Dog` 키를 그대로 쓴다 — 앱이 읽는 키로 목을 만들면
/// 앱이 틀린 키를 읽고 있을 때 테스트가 그 버그에 동의한다(#82).
String _dogJson({String name = '보리', bool neutered = false, String? breed = '믹스견'}) =>
    jsonEncode({
      'id': 7,
      'name': name,
      'species': 'dog',
      'breed': breed,
      'size': 'small',
      'birth': '2023-03-01',
      'ageMonths': 30,
      'neutered': neutered,
    });

({PetSync sync, List<http.Request> seen, List<String> bodies}) fixture({
  int status = 200,
  String? body,
}) {
  final seen = <http.Request>[];
  final bodies = <String>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      bodies.add(request.body);
      if (request.method == 'PATCH') {
        return http.Response(body ?? _dogJson(neutered: true), status,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('[]', 200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    sync: PetSync(repository: WalkRepository(baseUrl: _base, client: client)),
    seen: seen,
    bodies: bodies,
  );
}

Future<void> pumpEdit(WidgetTester tester, PetSync sync) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: EditScreen(pet: _bori, sync: sync)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    replacePets(const [_bori]);
    selectPet(0);
  });

  testWidgets('바꾼 것을 저장하면 PATCH 가 나가고 "저장했어요" 라고 말한다', (t) async {
    final f = fixture();
    await pumpEdit(t, f.sync);

    await t.tap(find.text('중성화 완료'));
    await t.pumpAndSettle();
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();

    final patch = f.seen.where((r) => r.method == 'PATCH').toList();
    expect(patch, hasLength(1), reason: '이 화면의 저장은 서버로 간다');
    expect(patch.single.url.path, '/api/dogs/7');
    expect(find.text('저장했어요'), findsOneWidget);
    expect(find.textContaining('이 기기에만'), findsNothing,
        reason: '서버에 저장해 놓고 "이 기기에만" 이라고 하면 그것도 거짓말이다');
  });

  testWidgets('바꾼 것만 보낸다 — 안 건드린 필드는 본문에 없다', (t) async {
    final f = fixture();
    await pumpEdit(t, f.sync);

    await t.tap(find.text('중성화 완료'));
    await t.pumpAndSettle();
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();

    final sent = jsonDecode(f.bodies[f.seen.indexWhere((r) => r.method == 'PATCH')]) as Map;
    expect(sent.keys, ['neutered'],
        reason: '부분 수정이라 보낸 것만 반영된다 — 다 보내면 두 기기가 서로의 편집을 덮는다');
    expect(sent['neutered'], isTrue);
  });

  testWidgets('아무것도 안 바꾸고 저장하면 서버를 안 부른다 — 빈 본문은 400 이다', (t) async {
    final f = fixture();
    await pumpEdit(t, f.sync);

    await t.tap(find.text('저장'));
    await t.pumpAndSettle();

    expect(f.seen.where((r) => r.method == 'PATCH'), isEmpty);
  });

  testWidgets('서버가 거절하면 그렇게 말하고 화면을 안 닫는다', (t) async {
    final f = fixture(status: 400, body: jsonEncode({'error': {'code': 'VALIDATION'}}));
    await pumpEdit(t, f.sync);

    await t.tap(find.text('중성화 완료'));
    await t.pumpAndSettle();
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();

    expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
    expect(find.byType(EditScreen), findsOneWidget,
        reason: '실패했는데 닫히면 사용자는 저장된 줄 안다');
  });

  testWidgets('목록의 그 아이가 서버가 돌려준 값으로 바뀐다', (t) async {
    final f = fixture(body: _dogJson(name: '보리야', neutered: true));
    await pumpEdit(t, f.sync);

    await t.tap(find.text('중성화 완료'));
    await t.pumpAndSettle();
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();

    expect(kMyPets.value.single.name, '보리야',
        reason: '화면이 보낸 값이 아니라 서버의 답으로 바꾼다 — 서버가 다듬은 것이 있다');
    expect(kMyPets.value.single.neutered, isTrue);
  });
}
