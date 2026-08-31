import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_terms_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 채팅 첫 진입 동의를 어디에 기억하는가 — 이슈 #82 완료 조건 6.
///
/// 여기서 지키는 것 셋이다.
/// 1. **계정마다 따로 센다** — 한 기기를 가족이 나눠 쓸 수 있고, 앞사람의 동의가 뒷사람에게
///    적용되면 그 사람은 약관을 본 적이 없는데 동의한 것이 된다.
/// 2. **읽기 실패는 "안 했다"** — 저장소가 삐끗한 사이에 동의 없이 채팅이 열리면 안 된다.
/// 3. **쓰기 실패는 삼킨다** — 다음에 또 물어보는 것은 성가신 일이고, 오류로 올리면
///    동의했는데 채팅에 못 들어가는 상태가 된다.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('처음에는 동의한 적이 없다', () async {
    const gate = ChatTermsGate();

    expect(await gate.hasAgreed(7), isFalse);
  });

  test('동의를 남기면 다음에는 안 묻는다', () async {
    const gate = ChatTermsGate();

    await gate.markAgreed(7);

    expect(await gate.hasAgreed(7), isTrue);
  });

  test('계정마다 따로 센다 — 한 기기를 가족이 나눠 쓸 수 있다', () async {
    const gate = ChatTermsGate();

    await gate.markAgreed(7);

    expect(
      await gate.hasAgreed(8),
      isFalse,
      reason: '앞사람의 동의가 뒷사람에게 적용되면 그 사람은 약관을 본 적이 없다',
    );
  });

  test('키에 계정 id 가 들어간다', () {
    expect(ChatTermsGate.keyFor(7), isNot(ChatTermsGate.keyFor(8)));
    expect(ChatTermsGate.keyFor(7), contains('7'));
  });

  test('저장소에 다른 값이 있어도 이 키만 본다', () async {
    SharedPreferences.setMockInitialValues({
      'chat_terms_agreed_v1_7': true,
      'something_else': 'x',
    });
    const gate = ChatTermsGate();

    expect(await gate.hasAgreed(7), isTrue);
    expect(await gate.hasAgreed(9), isFalse);
  });
}
