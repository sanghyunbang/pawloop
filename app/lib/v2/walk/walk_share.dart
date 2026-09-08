// lib/v2/walk/walk_share.dart
//
// 공유 카드를 OS 공유 시트로 — 이슈 #344.
//
// ## 기기 안에서 끝난다
//
// PNG 를 임시 파일로 쓰고 그 파일을 공유 시트에 넘긴다. **서버로 안 올린다** — 카드에는
// 경로가 들어 있고, 그 경로가 서버로 가면 A안(#235)이 무너진다. 어디로 보낼지는 사용자가
// 공유 시트에서 고른다(카톡·인스타·갤러리 저장).
//
// ## 임시 파일을 쓰는 이유
//
// `share_plus` 는 바이트가 아니라 파일 경로를 받는다. 캐시 디렉터리에 쓰므로 OS 가 알아서
// 지운다 — 우리가 지우면 공유 앱이 읽기 전에 사라질 수 있다.
//
// 이 파일에는 네트워크 클라이언트가 없다. `walk_share_no_network_test.dart` 가 잠근다.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'walk_share_card.dart';

/// 공유가 안 된 이유 — 화면이 문구를 고르는 데 쓴다.
class WalkShareException implements Exception {
  final Object cause;
  const WalkShareException(this.cause);

  String get message => '공유 시트를 열지 못했어요';

  @override
  String toString() => 'WalkShareException($cause)';
}

class WalkShare {
  /// 파일을 만들어 공유 시트에 넘기는 일. 테스트가 가짜를 꽂는 자리다.
  static Future<void> Function(Uint8List png, String name, String text) sender = _sharePlus;

  static Future<void> _sharePlus(Uint8List png, String name, String text) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text),
    );
  }

  /// 카드를 그려 공유 시트를 연다.
  ///
  /// 곁들이는 글은 **거리와 아이 이름뿐**이다 — 위치도 시각도 안 적는다. 카드에 이미 있고,
  /// 글로 한 번 더 적으면 공유 앱의 미리보기에 그것만 남는 경우가 있다.
  static Future<void> share(WalkShareCard card) async {
    try {
      final png = await WalkShareImage.renderPng(card);
      await sender(
        png,
        'pawloop_walk_${DateTime.now().millisecondsSinceEpoch}.png',
        '${card.dogName}${withParticle(card.dogName)} ${card.distanceLabel} 걸었어요',
      );
    } on Object catch (e) {
      throw WalkShareException(e);
    }
  }

  static void resetForTest() => sender = _sharePlus;
}
