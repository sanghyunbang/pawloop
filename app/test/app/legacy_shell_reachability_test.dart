// v2 가 레거시 감정 여행 셸로 가는 길이 없는가 — 이슈 #184.
//
// ## 왜 소스를 세는가
//
// 이건 화면을 펌프해서 잴 수 없다. "어느 화면에서도 거기로 안 간다" 는 **없음의**
// 주장이라, 있는 것을 확인하는 방식으로는 증명이 안 된다. 그래서 소스를 읽는다.
//
// ## 무엇이 문제였나
//
// 레거시 이메일 로그인으로 들어가면 감정 여행 화면이 나왔다 — "오늘의 마음",
// 기쁨/슬픔/불안, 탭이 오늘·탐색·피드·나. Pawloop 이 아니라 Heat Trip 이다.
//
// 더 나빴던 것은 **회원 탈퇴**다. #165 로 v2 설정에 넣은 탈퇴 화면이 성공 후
// `goNamed('start')` 로 레거시 시작 화면에 보냈다. 탈퇴한 사람이 Heat Trip 로고를
// 보고 끝났다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 레거시 감정 여행 셸의 경로·이름. 여기로 가면 다른 제품이다.
const _legacyShellDestinations = <String>[
  '/foryou_v2',
  '/emotion_map',
  '/discover',
  '/start',
  "goNamed('start')",
  "goNamed('forYouV2')",
];

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('v2 어디에서도 레거시 감정 여행 셸로 가지 않는다', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib/v2')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 주석은 센다고 치지 않는다 — 이 파일들이 '예전에는 그랬다' 를 설명하려고
        // 그 경로 이름을 본문에 적고 있다.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;

        for (final bad in _legacyShellDestinations) {
          if (line.contains(bad)) {
            offenders.add('${file.path}:${i + 1}  $line');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: '여기로 가면 사용자는 Pawloop 이 아니라 Heat Trip 을 본다:\n${offenders.join('\n')}');
  });

  test('탈퇴 화면이 화면을 직접 밀지 않는다 — 라우터가 정한다', () {
    // 주석은 뺀다. 이 파일이 '예전에는 goNamed(start) 였다' 를 설명하려고 그 문자열을
    // 본문에 적고 있다 — 설명은 코드가 아니다.
    final code = File('lib/v2/screens/settings/account_delete_screen.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    // 성공 분기에서 명시적으로 이동하면 라우터의 규칙과 두 곳이 된다. 그 둘이
    // 갈리는 날 탈퇴한 사람이 엉뚱한 데 착지한다.
    expect(code.contains("goNamed('start')"), isFalse);
    expect(code.contains("go('/start')"), isFalse);
  });
}
