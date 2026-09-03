// 사용자가 쓴 글이 기기 로그에 남지 않는다 — 이슈 #214.
//
// **`flutter analyze` 만으로는 부족하다.** `avoid_print: error` 를 켰지만
// `// ignore: avoid_print` 한 줄이면 그 규칙이 통째로 비켜 간다. 그러면 다음 사람이
// "잠깐만 찍어 보려고" 넣은 줄이 릴리스에 남는다.
//
// Flutter 의 `print()` 는 **릴리스 빌드에서도** 플랫폼 로그(Android logcat / iOS oslog)에
// 쓴다. USB 디버깅이 켜진 기기에서는 누구나 읽는다.
//
// 무엇이 남고 있었나(2026-09-03 이전):
//  - `journey_repository_impl.dart` 가 응답 본문 전체를 찍었다 — 사용자가 쓴 **일기 본문**이다
//  - `profile_edit_screen.dart` 가 프로필 원본을 찍었다 — **이메일이 들어 있다**

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `print(` 호출. `debugPrint(`·`sprint(` 같은 접미 일치를 피하려고 앞 글자를 본다.
final _printCall = RegExp(r'(?<![.\w])print\s*\(');

/// 규칙을 비켜 가는 주석.
final _ignoreComment = RegExp(r'//\s*ignore(_for_file)?:.*avoid_print');

void main() {
  test('lib/ 에 print( 호출이 없다 — 릴리스 로그에 사용자 글이 남는다', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 문서 주석 안의 언급은 호출이 아니다 — logging_client.dart 가 왜 print 를
        // 쓰면 안 되는지 설명하면서 그 이름을 적는다.
        if (line.trimLeft().startsWith('//')) continue;
        if (_printCall.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '찍어야 하면 debugPrint 를 쓰세요. 릴리스에서 잘립니다.\n${offenders.join('\n')}',
    );
  });

  test('avoid_print 를 비켜 가는 주석이 없다 — analyze 는 이것을 안 잡는다', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_ignoreComment.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '이 주석 한 줄이면 avoid_print: error 가 통째로 비켜 갑니다.\n'
          '정말 필요하면 이 테스트에 예외를 이유와 함께 더하세요 — '
          '주석만 달고 지나가면 아무도 안 봅니다.\n${offenders.join('\n')}',
    );
  });

  test('규칙이 error 로 켜져 있다 — info 면 CI 가 통과하면서 다시 쌓인다', () {
    final options = File('analysis_options.yaml').readAsStringSync();

    expect(
      options,
      contains('avoid_print: error'),
      reason: '이 규칙은 원래 info 였고 그 사이에 14곳이 쌓였습니다(#214). '
          'use_build_context_synchronously 가 같은 이유로 같은 자리에 있습니다.',
    );
  });
}

/// `lib/` 아래의 모든 `.dart`. 생성 파일(`.g.dart`·`.freezed.dart`)도 센다 —
/// 거기서 찍혀도 로그에 남는 것은 같다.
Iterable<File> _dartFilesUnder(String root) sync* {
  final dir = Directory(root);
  if (!dir.existsSync()) {
    fail('$root 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}
