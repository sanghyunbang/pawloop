// 시작 전에 "누구랑 나가요?" — 이슈 #343.
//
// ## 여기서 재는 것
//
//  1. **한 마리면 안 묻는다.** 대부분의 사용자가 한 마리이고, 그 사람에게 시트를 한 장 더
//     띄우면 산책 시작이 두 번 누르는 일이 된다. 완료 조건 2 가 이것이다.
//  2. **두 마리면 묻고, 고른 것이 추적 화면까지 간다.** 물어만 보고 안 쓰면 아무것도 안 한
//     것과 같다.
//  3. **닫으면 시작하지 않는다.** 빈 목록으로 밀어 넣으면 누구 것도 아닌 산책이 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/location_priming_sheet.dart';
import 'package:heat_trip_flutter/v2/screens/start_walk.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_dog_picker.dart';

DogProfile _dog(String name, {int? serverId}) => DogProfile(
      serverId: serverId,
      name: name,
      breed: '말티즈',
      size: DogSize.small,
      ageMonths: 24,
    );

/// 시작 버튼 한 개. 추적 화면 대신 "무엇을 들고 열렸나" 를 적는 함수를 꽂는다.
class _Harness {
  int opened = 0;
  int asked = 0;
  List<DogProfile> offered = const [];
  List<int>? answer;
}

Future<_Harness> _pump(
  WidgetTester t, {
  required List<DogProfile> pets,
  List<int>? answer,
  bool useRealSheet = false,
}) async {
  final h = _Harness()..answer = answer;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => startWalk(
            ctx,
            pets: pets,
            openTracking: (_, __, ___) async => h.opened++,
            askDogs: useRealSheet
                ? null
                : (context, offered) async {
                    h.asked++;
                    h.offered = offered;
                    return h.answer;
                  },
          ),
          child: const Text('산책 시작'),
        ),
      ),
    ),
  ));
  return h;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    // 위치 사전 안내(#325)는 이 테스트의 관심이 아니다 — 이미 물어본 상태로 둔다.
    LocationPriming.checkPermission = () async => LocationPermission.always;
  });
  tearDown(() {
    AuthState.resetForTest();
    LocationPriming.resetForTest();
    WalkSafetyStore.clear();
  });

  group('묻는가', () {
    testWidgets('한 마리면 묻지 않고 바로 시작한다 — 완료 조건 2', (t) async {
      final h = await _pump(t, pets: [_dog('보리', serverId: 7)]);

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();

      expect(h.asked, 0, reason: '한 마리에게 매번 시트를 띄우면 시작이 두 번 누르는 일이 된다');
      expect(h.opened, 1);
    });

    testWidgets('아이가 없어도 묻지 않는다 — 고를 것이 없다', (t) async {
      final h = await _pump(t, pets: const []);

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();

      expect(h.asked, 0);
      expect(h.opened, 1);
    });

    testWidgets('서버에 안 올라간 아이는 세지 않는다 — 그 아이에게 산책을 달 수 없다', (t) async {
      final h = await _pump(t, pets: [_dog('보리', serverId: 7), _dog('초코')]);

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();

      expect(h.asked, 0, reason: '보낼 수 있는 아이가 하나뿐이다');
    });

    testWidgets('두 마리면 묻는다', (t) async {
      final h = await _pump(
        t,
        pets: [_dog('보리', serverId: 7), _dog('초코', serverId: 9)],
        answer: const [7, 9],
      );

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();

      expect(h.asked, 1);
      expect(h.offered.map((p) => p.name), ['보리', '초코']);
      expect(h.opened, 1);
    });

    testWidgets('닫으면 시작하지 않는다 — 빈 목록으로 밀어 넣지 않는다', (t) async {
      final h = await _pump(
        t,
        pets: [_dog('보리', serverId: 7), _dog('초코', serverId: 9)],
        answer: null,
      );

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();

      expect(h.asked, 1);
      expect(h.opened, 0, reason: '누구 것도 아닌 산책을 만들지 않는다');
    });
  });

  group('진짜 시트', () {
    testWidgets('기본은 전부 골라져 있고, 하나를 끄면 그 아이가 빠진다', (t) async {
      final h = await _pump(
        t,
        pets: [_dog('보리', serverId: 7), _dog('초코', serverId: 9)],
        useRealSheet: true,
      );

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();

      expect(find.text('누구랑 나가요?'), findsOneWidget);
      expect(find.text('2마리와 시작하기'), findsOneWidget,
          reason: '함께 나가는 것이 흔하다 — 매번 체크하게 하면 시트가 방해가 된다');

      await t.tap(find.text('초코'));
      await t.pumpAndSettle();
      expect(find.text('1마리와 시작하기'), findsOneWidget);

      await t.tap(find.text('1마리와 시작하기'));
      await t.pumpAndSettle();

      expect(h.opened, 1);
    });

    testWidgets('아무도 안 고르면 시작 버튼이 잠긴다', (t) async {
      final h = await _pump(
        t,
        pets: [_dog('보리', serverId: 7), _dog('초코', serverId: 9)],
        useRealSheet: true,
      );

      await t.tap(find.text('산책 시작'));
      await t.pumpAndSettle();
      await t.tap(find.text('보리'));
      await t.tap(find.text('초코'));
      await t.pumpAndSettle();

      expect(find.text('한 마리는 골라 주세요'), findsOneWidget);
      final button = t.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(h.opened, 0);
    });
  });

  group('needed', () {
    test('서버 id 가 있는 아이가 둘 이상일 때만 참이다', () {
      expect(WalkDogPicker.needed(const []), isFalse);
      expect(WalkDogPicker.needed([_dog('보리', serverId: 7)]), isFalse);
      expect(WalkDogPicker.needed([_dog('보리'), _dog('초코')]), isFalse,
          reason: '서버에 없으면 산책을 달 수 없다');
      expect(
          WalkDogPicker.needed([_dog('보리', serverId: 7), _dog('초코', serverId: 9)]), isTrue);
    });
  });
}
