// 토큰을 지우는 경로는 하나뿐이어야 한다 (이슈 #12).
//
// 이 테스트가 있는 이유는 실제로 난 결함이다. 레거시 `/profile` 화면의
// 로그아웃이 저장소만 비우고 `AuthState` 를 그대로 뒀다. 결과는 두 가지였다.
//
//   1. `POST /auth/logout` 을 부르지 않아 서버의 refresh 토큰이 살아남았다
//      (#9 가 고치려던 바로 그 결함).
//   2. status 가 `authenticated` 로 남아, 새 `authRedirect` 가 로그인 화면
//      진입을 홈으로 **되튕겼다** — 로그아웃을 눌러도 로그인된 것처럼 보인다.
//
// 그 우회로였던 함수는 삭제해서 컴파일 에러로 막았다. 이 테스트는 그것이
// 되살아나거나, 화면이 저장소를 직접 비우는 새 우회로가 생기는 것을 막는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 저장소를 직접 비워도 되는 곳. 셋 다 비운 직후 `AuthState` 가 갱신된다.
const _allowedToClear = <String>{
  // AuthState.clearLocalSession() — 상태 갱신이 같은 함수 안에 있다.
  'lib/v2/data/auth_state.dart',
  // AuthedClient._endSession() — onSessionExpired 훅으로 AuthState 에 알린다.
  'lib/core/net/authed_client.dart',
  // AuthTokenStore 자체(위임 한 줄).
  'lib/core/net/auth_token_store.dart',
};

/// 되살아나면 안 되는 함수 이름. 문자열을 쪼개 둔 것은 이 파일 자신이
/// 자기 검사에 걸리지 않게 하기 위해서다.
const _forbidden = 'clear' 'Token';

void main() {
  final lib = Directory('lib');

  List<File> dartFiles() => lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String rel(File f) => f.path.replaceAll(r'\', '/');

  /// 주석은 검사에서 뺀다 — 이 결함을 설명하는 주석 자체가 걸리면 안 된다.
  String code(File f) => f
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');

  test('토큰만 지우는 헬퍼는 존재하지 않는다 — 되살리면 이 테스트가 빨간불', () {
    final offenders = [
      for (final f in dartFiles())
        if (code(f).contains(_forbidden)) rel(f),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          '토큰만 지우고 AuthState 를 두면 "토큰 없는 authenticated" 상태가 된다. '
          '로그아웃은 AuthState.logout(), 서버 세션이 이미 없으면 '
          'AuthState.clearLocalSession() 을 써라.',
    );
  });

  test('토큰 저장소를 직접 비우는 곳은 허용된 세 파일뿐이다', () {
    final offenders = <String>[];
    for (final f in dartFiles()) {
      final path = rel(f);
      if (_allowedToClear.any(path.endsWith)) continue;

      // 컬렉션 `.clear()` 와 섞이지 않도록 토큰 저장소 수신자를 명시한 형태만 본다.
      final hits = RegExp(
        r'(SecureTokenStore\.instance|_store|tokenStore|_tokens)\s*\.\s*clear\s*\(',
      ).allMatches(code(f));
      if (hits.isNotEmpty) offenders.add('$path (${hits.length}건)');
    }
    expect(
      offenders,
      isEmpty,
      reason: '저장소를 직접 비우면 AuthState 가 모른다. AuthState 를 거쳐라.',
    );
  });
}
