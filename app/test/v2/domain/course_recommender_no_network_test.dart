// 오늘의 코스(#485)는 좌표를 기기 안에서만 쓴다 — 추천기와 후보 모으기에 네트워크로 가는 길이 없다.
//
// `route_photo_no_network_test` 와 같은 방식이다: 좌표를 **받는** 파일 둘이 인증 클라이언트나
// 네트워크 import 를 갖지 않는지 소스로 본다. 후보 모으기가 부르는 저장소(카탈로그 · 내 코스)는
// 요청에 좌표를 싣지 않는다 — 그건 `location_upload_policy_test` 가 잰다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _files = [
  'lib/v2/domain/course_recommender.dart',
  'lib/v2/data/course_candidates.dart',
];

const _forbidden = [
  'package:http',
  'AuthedClient',
  "'/api/",
  'Uri.parse(',
  'dart:io',
  'HttpClient',
];

String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('추천기 · 후보 모으기 파일에 네트워크로 가는 import 나 호출이 없다', () {
    final offenders = <String>[];
    for (final path in _files) {
      expect(File(path).existsSync(), isTrue, reason: '$path 가 없다 — 옮겼으면 목록도 고쳐라');
      final code = _codeOnly(path);
      for (final word in _forbidden) {
        if (code.contains(word)) offenders.add('$path 에 $word');
      }
    }
    expect(offenders, isEmpty, reason: '좌표를 받는 파일에 네트워크 길이 생겼다. 추천은 기기 안에서 끝난다(#485)');
  });

  test('추천기는 domain 이라 data 의 안전 지수 enum 말고는 아무것도 안 든다', () {
    final imports = File('lib/v2/domain/course_recommender.dart')
        .readAsLinesSync()
        .where((l) => l.startsWith('import '))
        .toList();
    expect(imports, ["import 'dart:math' as math;", "import '../data/walk_safety.dart' show WalkSafetyLevel;"]);
  });
}
