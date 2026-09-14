// 공유 카드는 기기 안에서 끝난다 — 이슈 #344 완료 조건 3 을 소스로 잠근다.
//
// `route_photo_no_network_test` 와 같은 방향입니다: 좌표를 **받는** 파일이 네트워크로 가는
// 길 자체를 갖지 않는지 봅니다. 다른 점이 하나 있습니다 — `walk_share.dart` 는 PNG 를
// 임시 파일로 써야 해서 `dart:io` 를 씁니다. 그래서 그 파일만은 파일 쓰기를 허용하되,
// **어디에 쓰는지**(캐시 디렉터리)까지 함께 잠급니다. 허용을 한 줄 열어 두면 언젠가
// 그 줄로 다른 것이 들어옵니다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 좌표를 들고 있으면서 파일조차 만지면 안 되는 것.
const _pure = ['lib/v2/walk/walk_share_card.dart'];

/// 임시 파일은 쓰지만 네트워크는 없어야 하는 것.
const _fileOk = ['lib/v2/walk/walk_share.dart'];

const _network = [
  'package:http',
  'AuthedClient',
  "'/api/",
  'HttpClient',
  'WebSocket',
  'Socket(',
  // 지도 스냅숏(#483)은 트래킹 화면만 찍는다 — 카드는 바이트만 받는다.
  'flutter_naver_map',
  'takeSnapshot',
];

String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('공유 카드·공유 시트 파일에 네트워크로 가는 길이 없다', () {
    final offenders = <String>[];
    for (final path in [..._pure, ..._fileOk]) {
      expect(File(path).existsSync(), isTrue, reason: '$path 가 없다 — 옮겼으면 목록도 고쳐라');
      final code = _codeOnly(path);
      for (final word in _network) {
        if (code.contains(word)) offenders.add('$path 에 $word');
      }
    }
    expect(offenders, isEmpty,
        reason: '카드에는 경로가 들어 있다. 밖으로 나가면 A안(#235)이 무너진다');
  });

  test('카드를 그리는 파일은 파일 시스템도 안 만진다', () {
    for (final path in _pure) {
      final code = _codeOnly(path);
      expect(code.contains('dart:io'), isFalse, reason: '$path 는 그리기만 한다');
    }
  });

  test('공유 시트는 캐시 디렉터리에만 쓴다 — 사용자 문서·외부 저장소가 아니다', () {
    final code = _codeOnly(_fileOk.single);

    expect(code.contains('getTemporaryDirectory()'), isTrue);
    for (final other in [
      'getApplicationDocumentsDirectory',
      'getExternalStorageDirectory',
      'getDownloadsDirectory',
    ]) {
      expect(code.contains(other), isFalse,
          reason: '$other 에 쓰면 사용자가 지우기 전까지 카드가 기기에 쌓인다');
    }
  });
}
