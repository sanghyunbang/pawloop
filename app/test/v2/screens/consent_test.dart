// 약관 동의 — 게이트와 화면. 이슈 #180.
//
// ## 여기서 재는 것
//
//  1. 필수를 다 안 채우면 못 넘어가는가. 위치기반서비스 동의가 필수인가.
//  2. 계정마다 따로 세는가. 한 기기를 가족이 나눠 쓸 때 앞사람의 동의가 뒷사람에게
//     적용되면 그 사람은 약관을 본 적이 없는데 동의한 것이 된다.
//  3. 저장에 실패하면 넘어가지 않고 말하는가. 삼키면 다음 실행에 또 뜨고 사용자는
//     '동의했는데 왜 또 묻지' 를 겪는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/consent_gate.dart';
import 'package:heat_trip_flutter/v2/screens/consent_screen.dart';

/// 동의가 끝난 횟수. **값이 아니라 통을 돌려준다** — 값으로 돌려주면 호출부가 든 것은
/// 그때의 0 이고, 화면이 올려도 그 숫자는 영원히 0 이다. 실제로 그렇게 써서 첫 테스트가
/// 비어 있었고, 코드를 되돌려도 초록이었다.
Future<ValueNotifier<int>> _pump(WidgetTester t,
    {ConsentGate? gate, int userId = 11}) async {
  final agreed = ValueNotifier<int>(0);
  await t.pumpWidget(MaterialApp(
    home: ConsentScreen(
      userId: userId,
      onAgreed: () => agreed.value++,
      gate: gate,
    ),
  ));
  await t.pumpAndSettle();
  return agreed;
}

/// 저장이 항상 실패하는 게이트.
class _BrokenGate implements ConsentGate {
  @override
  Future<bool> markAgreed(int userId, {required bool marketing}) async => false;

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('게이트', () {
    test('한 번도 안 물었으면 동의하지 않은 것이다', () async {
      expect(await const ConsentGate().hasAgreed(11), isFalse);
    });

    test('동의하면 남고, 앱을 다시 켜도 남아 있다', () async {
      expect(await const ConsentGate().markAgreed(11, marketing: false), isTrue);
      expect(await const ConsentGate().hasAgreed(11), isTrue);
    });

    test('계정마다 따로 센다 — 앞사람의 동의가 뒷사람에게 적용되면 안 된다', () async {
      await const ConsentGate().markAgreed(11, marketing: false);
      expect(await const ConsentGate().hasAgreed(12), isFalse,
          reason: '한 기기를 가족이 나눠 쓸 수 있다');
    });

    test('마케팅은 필수와 따로 센다', () async {
      await const ConsentGate().markAgreed(11, marketing: false);
      expect(await const ConsentGate().hasAgreed(11), isTrue);
      expect(await const ConsentGate().marketingOptIn(11), isFalse,
          reason: '한 값에 묶으면 마케팅 거부가 가입 거부가 된다');

      await const ConsentGate().markAgreed(11, marketing: true);
      expect(await const ConsentGate().marketingOptIn(11), isTrue);
    });

    test('지우면 다시 물어본다 — 탈퇴 뒤 같은 id 로 온 사람에게 적용되면 안 된다', () async {
      await const ConsentGate().markAgreed(11, marketing: true);
      await const ConsentGate().clear(11);

      expect(await const ConsentGate().hasAgreed(11), isFalse);
      expect(await const ConsentGate().marketingOptIn(11), isFalse);
    });
  });
  group('화면', () {
    testWidgets('필수 셋을 다 안 채우면 못 넘어간다', (t) async {
      final agreed = await _pump(t);

      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();
      expect(agreed.value, 0);

      // 둘만 채워도 안 된다.
      await t.tap(find.text('이용약관'));
      await t.tap(find.text('개인정보처리방침'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();
      expect(agreed.value, 0, reason: '위치기반서비스 동의가 빠졌다');
    });

    testWidgets('위치기반서비스가 필수다 — 산책 기록이 이 앱의 본체다', (t) async {
      await _pump(t);
      // [필수] 표시가 셋, [선택] 이 하나다.
      expect(find.text('[필수] '), findsNWidgets(3));
      expect(find.text('[선택] '), findsOneWidget);
      expect(find.text('위치기반서비스 이용약관'), findsOneWidget);
    });

    testWidgets('필수 셋을 채우면 넘어간다 — 마케팅은 안 해도 된다', (t) async {
      var agreed = 0;
      await t.pumpWidget(MaterialApp(
        home: ConsentScreen(userId: 11, onAgreed: () => agreed++),
      ));
      await t.pumpAndSettle();

      await t.tap(find.text('이용약관'));
      await t.tap(find.text('개인정보처리방침'));
      await t.tap(find.text('위치기반서비스 이용약관'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();

      expect(agreed, 1);
      expect(await const ConsentGate().hasAgreed(11), isTrue);
      expect(await const ConsentGate().marketingOptIn(11), isFalse);
    });

    testWidgets('전체 동의를 누르면 선택까지 켜진다', (t) async {
      var agreed = 0;
      await t.pumpWidget(MaterialApp(
        home: ConsentScreen(userId: 11, onAgreed: () => agreed++),
      ));
      await t.pumpAndSettle();

      await t.tap(find.text('전체 동의 (선택 항목 포함)'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();

      expect(agreed, 1);
      expect(await const ConsentGate().marketingOptIn(11), isTrue);
    });

    testWidgets('저장에 실패하면 넘어가지 않고 말한다', (t) async {
      var agreed = 0;
      await t.pumpWidget(MaterialApp(
        home: ConsentScreen(userId: 11, onAgreed: () => agreed++, gate: _BrokenGate()),
      ));
      await t.pumpAndSettle();

      await t.tap(find.text('전체 동의 (선택 항목 포함)'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();

      expect(agreed, 0, reason: '넘어가면 다음 실행에 또 뜨고 사용자는 이유를 모른다');
      expect(find.text('동의를 저장하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
    });

    testWidgets('각 항목의 전문을 읽을 수 있다 — 읽을 수 없는 동의는 동의가 아니다', (t) async {
      await _pump(t);
      // 항목 넷 각각에 전문 보기 화살표가 있다.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
    });
  });
}
