// 경로 사진은 갤러리에만 간다 — 이슈 #310 완료 조건 2 를 소스로 잠근다.
//
// `location_upload_policy_test` 는 "좌표를 요청에 싣는 파일" 을 잡는다. 여기는 반대 방향이다 —
// 좌표를 **받는** 파일 셋이 네트워크로 가는 길 자체를 갖지 않는지 본다. 그림·저장·시트가
// 언젠가 인증 클라이언트를 import 하는 순간 좌표가 밖으로 나갈 수 있는 자리가 생긴다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _files = [
  'lib/v2/walk/route_image.dart',
  'lib/v2/walk/route_photo_saver.dart',
  'lib/v2/widgets/walk_finish_sheet.dart',
];

/// 코드 줄에 있으면 안 되는 것. 주석 줄은 보지 않는다 — 머리 주석이 "이것을 import 하지
/// 않는다" 라고 적는 것까지 잡으면 설명을 못 적게 만든다.
const _forbidden = [
  'package:http',
  'AuthedClient',
  "'/api/",
  'dart:io',
  'HttpClient',
  'WebSocket',
  // 지도 스냅숏(#483)은 트래킹 화면만 찍는다 — 그림·저장·시트 파일은 바이트만 받는다.
  'flutter_naver_map',
  'takeSnapshot',
];

String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('경로 그림·저장·시트 파일은 네트워크로 가는 import 나 호출이 없다', () {
    final offenders = <String>[];
    for (final path in _files) {
      expect(File(path).existsSync(), isTrue, reason: '$path 가 없다 — 옮겼으면 목록도 고쳐라');
      final code = _codeOnly(path);
      for (final word in _forbidden) {
        if (code.contains(word)) offenders.add('$path 에 $word');
      }
    }
    expect(offenders, isEmpty,
        reason: '좌표를 받는 파일에 네트워크 길이 생겼다. 사진은 갤러리에만 간다(#310)');
  });

  test('저장기는 gal 하나만 플랫폼과 이야기한다 — 다른 플러그인·채널이 없다', () {
    final code = _codeOnly('lib/v2/walk/route_photo_saver.dart');
    expect(code.contains("import 'package:gal/gal.dart';"), isTrue);
    expect(code.contains('MethodChannel'), isFalse);
  });
}
