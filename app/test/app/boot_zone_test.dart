// 앱이 뜨는 자리의 존 — 이슈 #514.
//
// 콜드 스타트마다 프레임워크가 `Zone mismatch` assertion 을 던지고 있었다(에뮬레이터
// logcat 실측). 바인딩은 존 **밖**에서 초기화되는데 `runApp` 만 `runZonedGuarded`
// **안**에서 불렸기 때문이다.
//
// 이것은 로그 한 줄의 문제가 아니다. 그 상태에서는 **존이 잡기로 한 비동기 예외가
// 실제로 그 존으로 안 간다** — 잡는 장치를 달아 두고 안 잡히는 상태다.
//
// 그래서 여기서 재는 것은 "존을 쓰지 마라" 가 아니라 **"존을 쓴다면 바인딩도 그 안에서
// 초기화하라"** 다. 지금은 존을 안 쓰고 `PlatformDispatcher.instance.onError` 한 곳으로
// 모은다(프레임워크 권장) — 나중에 존으로 돌아가더라도 이 검사는 여전히 맞는 말을 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 주석은 뺀다 — 이 결함을 설명하는 주석이 자기 검사에 걸리면 안 된다.
String _code(File f) => f
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final source = _code(File('lib/main.dart'));

  test('존을 쓴다면 바인딩도 그 안에서 초기화한다 — 어긋나면 Zone mismatch 다', () {
    final zoneAt = source.indexOf('runZonedGuarded');
    final bindingAt = source.indexOf('ensureInitialized');
    final mismatched = zoneAt >= 0 && bindingAt < zoneAt;

    expect(mismatched, isFalse,
        reason: '바인딩이 존 밖에서 초기화되면 runApp 이 assertion 을 던지고, '
            '그 존이 잡기로 한 비동기 예외가 실제로 거기로 안 간다');
  });

  test('비동기 예외를 받을 자리는 그대로 있다 — 존을 뺀다고 예외를 버리는 것이 아니다', () {
    // `=` 까지 본다. 그냥 이름만 보면 `...onErrorSomethingElse` 같은 더 긴 식별자가
    // 이 검사를 통과시킨다 — 실제로 되돌리기 변형 하나가 그렇게 초록이었다.
    expect(source, contains('PlatformDispatcher.instance.onError ='));
    expect(source, contains('FlutterError.onError ='),
        reason: '프레임워크가 잡은 것과 못 잡은 것, 둘 다 받을 자리가 있어야 한다');
  });
}
