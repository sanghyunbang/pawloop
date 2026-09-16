// 두 화면에서 얼굴을 고르면 서버로 간다 — 이슈 #585.
//
// 고르는 자리가 둘이다. **등록 시트**는 아이를 만들면서 한 번에 보내고, **편집 화면**은
// 나중에 고치거나 되돌린다. 줄 자체는 `pet_character_picker_test.dart` 가 재고, 여기서는
// 고른 값이 **본문에 실려 나가는지**를 잰다 — 그 사이가 끊기면 화면만 바뀌고 서버는 모른다.
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
import 'package:heat_trip_flutter/v2/widgets/dog_avatar.dart';
import 'package:heat_trip_flutter/v2/widgets/pet_registration_sheet.dart';

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

/// 계약의 `Dog` 그대로.
String _dogJson({String? character}) => jsonEncode({
      'id': 7,
      'name': '보리',
      'species': 'dog',
      'breed': '믹스견',
      'size': 'small',
      'birth': null,
      'ageMonths': 30,
      'neutered': false,
      'avatarUrl': null,
      'character': character,
      'mine': true,
    });

const _bori = DogProfile(
  serverId: 7,
  name: '보리',
  breed: '믹스견',
  size: DogSize.small,
  ageMonths: 30,
);

({PetSync sync, List<http.Request> seen, List<String> bodies}) fixture({String? answer}) {
  final seen = <http.Request>[];
  final bodies = <String>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      bodies.add(request.body);
      return http.Response(answer ?? _dogJson(), request.method == 'POST' ? 201 : 200,
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

/// 390dp — 진짜 폰 너비다. 시트는 여기서 끝까지 보인다.
///
/// **고르기 줄은 열넷이라 다 안 보인다.** 좁은 화면에서 안 보이는 칸을 누르려 하면 테스트가
/// "못 찾았다" 로 죽는데, 그건 이 파일이 재려는 것이 아니다(줄 자체는 `pet_character_picker_test`
/// 가 잰다). 그래서 여기서는 **처음부터 보이는 칸**만 누른다.
Future<void> pumpSheet(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

/// 편집 화면은 세로로 길다 — 저장 버튼이 목록의 맨 아래다. 폰 높이로 띄우면 버튼이 아예
/// 안 그려져서 누를 수가 없다(기존 `edit_screen_save_test` 와 같은 크기를 쓴다).
Future<void> pumpEdit(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Map<String, Object?> _sentBy(
  ({PetSync sync, List<http.Request> seen, List<String> bodies}) f,
  String method,
) {
  final at = f.seen.indexWhere((r) => r.method == method);
  expect(at, isNot(-1), reason: '$method 요청이 아예 안 나갔다');
  return jsonDecode(f.bodies[at]) as Map<String, Object?>;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    replacePets(const []);
  });

  group('등록 시트', () {
    testWidgets('고른 얼굴이 등록 본문에 실린다', (t) async {
      final f = fixture(answer: _dogJson(character: 'poodle'));
      await pumpSheet(t, Scaffold(body: PetRegistrationSheet(sync: f.sync)));

      await t.enterText(find.byType(TextField).first, '보리');
      await t.tap(find.byKey(const Key('pet-character-poodle')));
      await t.pumpAndSettle();
      await t.tap(find.text('등록하기'));
      await t.pumpAndSettle();

      expect(_sentBy(f, 'POST')['character'], 'poodle');
    });

    testWidgets('안 고르면 그 키가 본문에 없다', (t) async {
      final f = fixture();
      await pumpSheet(t, Scaffold(body: PetRegistrationSheet(sync: f.sync)));

      await t.enterText(find.byType(TextField).first, '보리');
      await t.tap(find.text('등록하기'));
      await t.pumpAndSettle();

      expect(_sentBy(f, 'POST').containsKey('character'), isFalse);
    });

    testWidgets('고른 얼굴이 사진 칸에 미리 뜬다 — 등록하고 나서 볼 화면 그대로다', (t) async {
      final f = fixture();
      await pumpSheet(t, Scaffold(body: PetRegistrationSheet(sync: f.sync)));

      await t.tap(find.byKey(const Key('pet-character-poodle')));
      await t.pumpAndSettle();

      final preview = t.widget<Image>(find.descendant(
        of: find.byKey(const Key('pet-photo-pick')),
        matching: find.byType(Image),
      ));
      expect((preview.image as AssetImage).assetName, 'assets/emoji/poodle.png');
    });
  });

  group('편집 화면', () {
    testWidgets('나중에 골라도 저장된다 — 그 키 하나만 나간다', (t) async {
      final f = fixture(answer: _dogJson(character: 'turtle'));
      replacePets(const [_bori]);
      selectPet(0);
      await pumpEdit(t, EditScreen(pet: _bori, sync: f.sync));

      await t.tap(find.byKey(const Key('pet-character-turtle')));
      await t.pumpAndSettle();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(_sentBy(f, 'PATCH').keys, ['character'],
          reason: '부분 수정이라 보낸 것만 반영된다 — 다 보내면 두 기기가 서로의 편집을 덮는다');
      expect(_sentBy(f, 'PATCH')['character'], 'turtle');
    });

    testWidgets('"기본" 을 누르면 null 을 보낸다 — 되돌릴 길이 이것뿐이다', (t) async {
      const chosen = DogProfile(
        serverId: 7,
        name: '보리',
        breed: '믹스견',
        size: DogSize.small,
        ageMonths: 30,
        characterKey: 'poodle',
      );
      final f = fixture();
      replacePets(const [chosen]);
      selectPet(0);
      await pumpEdit(t, EditScreen(pet: chosen, sync: f.sync));

      await t.tap(find.byKey(const Key('pet-character-default')));
      await t.pumpAndSettle();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      final sent = _sentBy(f, 'PATCH');
      expect(sent.containsKey('character'), isTrue);
      expect(sent['character'], isNull,
          reason: '안 보내면 "안 바꿈" 이라 한 번 고른 사람이 기본으로 못 돌아간다');
    });

    testWidgets('고르는 즉시 위의 큰 그림이 바뀐다 — 저장을 기다리지 않는다', (t) async {
      // 에뮬레이터에서 찾았다. 푸들을 골랐는데 위의 96px 아바타가 옛 얼굴 그대로여서,
      // 무엇을 고른 것인지 확인할 길이 화면에서 제일 작은 칸밖에 없었다.
      final f = fixture();
      replacePets(const [_bori]);
      selectPet(0);
      await pumpEdit(t, EditScreen(pet: _bori, sync: f.sync));

      await t.tap(find.byKey(const Key('pet-character-turtle')));
      await t.pumpAndSettle();

      final shown = t
          .widgetList<Image>(find.descendant(
            of: find.byType(DogAvatar),
            matching: find.byType(Image),
          ))
          .map((i) => (i.image as AssetImage).assetName)
          .toList();
      expect(shown, contains('assets/emoji/turtle.png'),
          reason: '저장 전에는 옛 얼굴을 그리고 있었다');
    });

    testWidgets('얼굴을 안 건드리면 그 키가 본문에 없다', (t) async {
      final f = fixture();
      replacePets(const [_bori]);
      selectPet(0);
      await pumpEdit(t, EditScreen(pet: _bori, sync: f.sync));

      await t.tap(find.text('중성화 완료'));
      await t.pumpAndSettle();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(_sentBy(f, 'PATCH').keys, ['neutered']);
    });

    testWidgets('이미 고른 아이의 이름만 고쳐도 얼굴은 안 실린다', (t) async {
      // 위 테스트는 얼굴이 **없는** 아이라, 안 고른 값을 그대로 실어 보내도 초록이었다.
      // 그 사이 다른 기기에서 바꾼 얼굴을 이 저장이 덮는 자리다.
      const chosen = DogProfile(
        serverId: 7,
        name: '보리',
        breed: '믹스견',
        size: DogSize.small,
        ageMonths: 30,
        characterKey: 'poodle',
      );
      final f = fixture();
      replacePets(const [chosen]);
      selectPet(0);
      await pumpEdit(t, EditScreen(pet: chosen, sync: f.sync));

      await t.enterText(find.widgetWithText(TextField, '보리'), '보리야');
      await t.pumpAndSettle();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(_sentBy(f, 'PATCH').keys, ['name'],
          reason: '안 건드린 얼굴을 실어 보내면 남의 편집을 덮는다');
    });
  });
}
