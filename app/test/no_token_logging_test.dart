import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 토큰(과 토큰이 박혀 있는 콜백 URL)을 로그로 흘리는 코드가 다시 들어오지
/// 못하게 막는 정적 검사.
///
/// `print` 는 릴리스 빌드에서도 동작해 logcat 에 남는다. `adb logcat`,
/// 버그 리포트, 크래시 리포터 수집 경로로 토큰이 빠져나간다.
///
/// 네트워크를 타지 않는다 — `dart:io` 로 소스 파일만 읽는다.
void main() {
  /// 로그 호출 한 줄에 이 중 하나라도 걸리면 위반.
  const leakPatterns = <String, String>{
    // $token, ${token}, $accessToken, ${_refreshToken}, $jwtToken ...
    r'\$\{?\s*_*[A-Za-z0-9_]*[Tt]oken': '토큰 변수 보간',
    // $jwt, ${jwtString}
    r'\$\{?\s*_*[A-Za-z0-9_]*[Jj][Ww][Tt]': 'JWT 변수 보간',
    // $bearer, ${authHeader} 류
    r'\$\{?\s*_*[A-Za-z0-9_]*[Bb]earer': 'Bearer 헤더 보간',
    // 딥링크 콜백 URL 전체 — URL 쿼리에 토큰이 들어 있다.
    r'\$\{?\s*result\b': '콜백 결과 URL 보간',
    r'queryParameters': '쿼리 파라미터 통째 출력',
  };

  test('app/lib 안에 토큰이나 콜백 URL 을 그대로 찍는 로그가 한 줄도 없다', () {
    final libDir = _resolveLibDir();

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((entity) => entity.path.endsWith('.dart'))
        .toList();

    // 스캔이 비어 있으면 이 테스트는 아무것도 검증하지 않는 셈이다.
    expect(
      dartFiles.length,
      greaterThan(100),
      reason: 'lib 스캔이 비었다 (cwd=${Directory.current.path})',
    );
    expect(
      dartFiles.any((f) => f.path.replaceAll(r'\', '/').endsWith(
          'features/auth/service/social_login_service.dart')),
      isTrue,
      reason: '과거 위반이 있던 파일이 스캔 대상에 있어야 한다',
    );

    final logCall = RegExp(r'\b(?:debugPrint|print)\s*\(');
    final compiled = leakPatterns.map(
      (pattern, label) => MapEntry(RegExp(pattern), label),
    );

    final violations = <String>[];

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!logCall.hasMatch(line)) continue;
        if (line.trimLeft().startsWith('//')) continue; // 주석은 봐준다

        compiled.forEach((regex, label) {
          if (regex.hasMatch(line)) {
            final relative = file.path.replaceAll(r'\', '/');
            violations.add('$relative:${i + 1} — $label: ${line.trim()}');
          }
        });
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '토큰이 로그로 새어 나간다. kDebugMode 가드를 걸어도 토큰 원문은 찍지 마라.\n'
          '${violations.join('\n')}',
    );
  });

  test('app/lib 안에서 SharedPreferences 에 토큰을 평문으로 저장하는 곳이 없다', () {
    // 토큰 저장 창구는 SecureTokenStore 하나뿐이어야 한다.
    // SharedPreferences 는 앱 데이터 디렉터리의 XML 이라 루팅·백업 추출로 읽힌다.
    final plaintextWrite = RegExp(
      '''setString\\(\\s*['"](?:jwt_token|access_token|refresh_token|token)['"]''',
    );

    final violations = <String>[];
    for (final file in _dartFilesUnderLib()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!plaintextWrite.hasMatch(line)) continue;
        violations.add(
          '${file.path.replaceAll(r'\', '/')}:${i + 1} — ${line.trim()}',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '토큰을 평문으로 저장한다. SecureTokenStore 를 써라.\n'
          '${violations.join('\n')}',
    );
  });
}

List<File> _dartFilesUnderLib() => _resolveLibDir()
    .listSync(recursive: true)
    .whereType<File>()
    .where((entity) => entity.path.endsWith('.dart'))
    .toList();

Directory _resolveLibDir() {
  for (final candidate in <String>['lib', 'app/lib', '../lib']) {
    final dir = Directory(candidate);
    if (dir.existsSync()) return dir;
  }
  fail('app/lib 디렉터리를 찾지 못했다 (cwd=${Directory.current.path})');
}
