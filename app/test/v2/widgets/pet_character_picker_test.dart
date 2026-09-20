// 얼굴 고르기 줄 — 이슈 #585.
//
// ## 여기서 지키는 것
//
//  1. **맨 앞이 "기본"** 이고, 거기에는 그 아이의 종류 그림이 뜬다. 고른 얼굴을 도로 물릴
//     길이 이것뿐이다 — 서버는 `null` 을 "지워 달라" 로 받는다(#586).
//  2. **고른 칸이 화면 안에 있다.** 열넷은 390dp 에 다 안 들어간다. 뒤쪽 얼굴을 고른 아이의
//     편집 화면을 열면 왼쪽 여섯 칸이 전부 흐리게 보여서, 사용자는 아무것도 안 고른 줄 안다
//     — 케어 항목에서 에뮬레이터로 찾은 것과 같은 실패다(#560).
//
// 화면 너비를 **390dp 로 고정**한다. 기본 800dp 로는 열넷이 거의 다 들어가서 2번이 절대
// 재현되지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/pet_character_picker.dart';

const double _screen = 390;

Future<List<String?>> pumpPicker(
  WidgetTester tester, {
  String? selected,
  PetSpecies species = PetSpecies.dog,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final picked = <String?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: PetCharacterPicker(
          selected: selected,
          species: species,
          onPick: picked.add,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('기본 한 칸 + 얼굴 열셋', (t) async {
    await pumpPicker(t);

    expect(find.byKey(const Key('pet-character-default')), findsOneWidget);
    expect(find.text('기본'), findsOneWidget);
    // 줄 전체는 스크롤이라 한 번에 다 안 뜬다. 맨 앞 몇 칸이 보이는 것으로 충분하다.
    expect(find.byKey(const Key('pet-character-dog_face')), findsOneWidget);
    expect(find.text('푸들'), findsOneWidget);
  });

  testWidgets('기본 칸에는 그 아이의 종류 그림이 뜬다 — 고르기 전 화면이 미리 보인다', (t) async {
    await pumpPicker(t, species: PetSpecies.cat);

    final image = t.widget<Image>(find.descendant(
      of: find.byKey(const Key('pet-character-default')),
      matching: find.byType(Image),
    ));
    expect((image.image as AssetImage).assetName, petSpeciesAsset(PetSpecies.cat));
  });

  testWidgets('누르면 그 열쇠말이 온다', (t) async {
    final picked = await pumpPicker(t);

    await t.tap(find.byKey(const Key('pet-character-poodle')));
    await t.pumpAndSettle();

    expect(picked, ['poodle']);
  });

  testWidgets('"기본" 을 누르면 null 이 온다 — 되돌릴 길이 이것뿐이다', (t) async {
    final picked = await pumpPicker(t, selected: 'poodle');

    await t.tap(find.byKey(const Key('pet-character-default')));
    await t.pumpAndSettle();

    expect(picked, [null]);
  });

  testWidgets('뒤쪽 얼굴을 고른 채로 열면 그 칸이 화면 안에 있다', (t) async {
    await pumpPicker(t, selected: 'hedgehog');

    final chip = find.byKey(const Key('pet-character-hedgehog'));
    expect(chip, findsOneWidget, reason: '고른 칸이 아예 안 그려졌다 — 굴리지 않았다는 뜻이다');

    final rect = t.getRect(chip);
    expect(rect.left, greaterThanOrEqualTo(0.0),
        reason: '고른 칸이 왼쪽 밖이면 사용자는 아무것도 안 고른 줄 안다');
    expect(rect.right, lessThanOrEqualTo(_screen),
        reason: '고른 칸이 오른쪽 밖이면 같은 일이 벌어진다');
  });

  testWidgets('이미 보이는 칸이면 안 굴린다 — 맨 앞의 "기본" 을 밀어내지 않는다', (t) async {
    // 푸들은 셋째라 390dp 에 이미 보인다. 그래도 굴리면 되돌릴 유일한 칸이 왼쪽 밖으로
    // 밀려난다 — 이 테스트가 처음 빨간불을 냈을 때가 정확히 그 상태였다.
    await pumpPicker(t, selected: 'poodle');

    final home = t.getRect(find.byKey(const Key('pet-character-default')));
    expect(home.left, greaterThanOrEqualTo(0.0));
    expect(home.right, lessThanOrEqualTo(_screen));
    expect(t.getRect(find.byKey(const Key('pet-character-poodle'))).right,
        lessThanOrEqualTo(_screen),
        reason: '고른 칸도 함께 보여야 한다');
  });
}
