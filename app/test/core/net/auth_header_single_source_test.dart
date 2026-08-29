// `Authorization` 헤더를 만드는 곳이 하나인지 소스 스캔으로 잠근다 — 이슈 #11 완료 조건 1.
//
// 왜 소스 스캔인가: 16개 파일이 각자 헤더를 조립하던 상태는 컴파일도 되고
// 테스트도 통과했다. 다시 그렇게 되는 것을 막는 유일한 방법은 "그렇게 쓰지 마라" 를
// 실행 가능한 형태로 적어 두는 것이다. 백엔드도 같은 방식을 쓴다
// (`AuthSubjectContractSpecTest` 가 컨트롤러의 Authorization 재파싱을 막는다 — #5).
//
// 이 테스트가 빨간불이면 새 파일이 토큰을 직접 붙이고 있다는 뜻이고,
// 그 파일은 401 자동 갱신을 받지 못한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 헤더 조립이 허용된 유일한 파일.
const _theOnlyPlace = 'lib/core/net/authed_client.dart';

void main() {
  test('Authorization 헤더를 만드는 곳은 AuthedClient 하나뿐이다', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'flutter test 는 패키지 루트(app/)에서 돈다',
    );

    final offenders = <String>[];

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final normalized = entity.path.replaceAll(r'\', '/');
      if (normalized.endsWith(_theOnlyPlace)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 주석은 넘어간다 — 이 규칙을 설명하는 문장이 규칙 위반이 되면 곤란하다.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (trimmed.startsWith('*') || trimmed.startsWith('/*')) continue;

        if (line.contains("'Authorization'") ||
            line.contains('"Authorization"') ||
            line.contains("'Bearer \$")) {
          offenders.add('$normalized:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '인증 헤더는 AuthedClient 가 붙인다. 직접 붙이면 401 자동 갱신을 받지 못한다.\n'
          '위반: ${offenders.join(', ')}',
    );
  });
}
