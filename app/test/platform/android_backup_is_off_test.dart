// 안드로이드 백업으로 좌표가 나가지 않는다 — 이슈 #270.
//
// ## 무엇이 있었나
//
// `AndroidManifest.xml` 에 `android:allowBackup` 이 **없었다.** 안드로이드 기본값은
// `true` 다. 그러면 Auto Backup 이 앱의 `shared_preferences` 를 사용자의 구글 드라이브로
// 올리는데, 거기에 아직 못 올린 산책 초안이 있고 그 안에 **원시 GPS 경로가 평문으로**
// 들어 있다 — `walk_outbox.dart` 의 `'path': [[경도, 위도], ...]`.
//
// `legal-lbs-compliance.md` 의 A안은 **"좌표가 단말을 떠나지 않는다"** 가 전제다.
// `LocationUploadPolicy` 가 우리 서버로 가는 길을 전부 막아도, **OS 가 그 뒤로 들고
// 나가면** 그 전제가 깨진다. 우리 코드에 전송이 한 줄도 없어도 좌표는 구글 서버에 있다.
//
// ## 왜 검사를 다나
//
// 매니페스트는 **사람이 손으로 고치는 파일**이다. 권한을 하나 더할 때, 라이브러리가
// 시키는 대로 태그를 붙일 때, 병합 충돌을 풀 때 — 한 줄이 조용히 사라진다. 그리고
// 사라져도 **앱은 잘 돈다.** 아무도 모른다.
//
// #235 의 전수 조사가 이 자리를 찾았다. 본문이 센 아홉 경로에 없던 **열 번째**다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File get _manifest => File('android/app/src/main/AndroidManifest.xml');

File get _rules => File('android/app/src/main/res/xml/data_extraction_rules.xml');

String _read(File file) {
  if (!file.existsSync()) {
    fail('${file.path} 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  return file.readAsStringSync();
}

void main() {
  group('안드로이드 백업', () {
    test('allowBackup 이 false 다 — 안 적으면 기본값이 true 라 좌표가 구글로 간다', () {
      expect(
        _read(_manifest),
        contains('android:allowBackup="false"'),
        reason: 'shared_preferences 에 아직 못 올린 산책 초안의 원시 GPS 경로가 있습니다. '
            'Auto Backup 은 우리 코드를 한 줄도 안 지나고 그것을 들고 나갑니다.',
      );
    });

    test('dataExtractionRules 가 걸려 있다 — API 31+ 는 기기 간 전송이 따로다', () {
      expect(
        _read(_manifest),
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'allowBackup="false" 는 클라우드 백업만 끕니다. Android 12 부터 '
            '기기 간 전송(device-to-device)이 따로 있고 그것은 이 규칙이 정합니다. '
            'compileSdk 가 36 입니다.',
      );
    });

    test('그 규칙 파일이 실재하고 두 경로를 다 막는다 — 하나만 막으면 반만 막힌 것이다', () {
      final rules = _read(_rules);

      for (final channel in ['cloud-backup', 'device-transfer']) {
        expect(
          rules,
          contains('<$channel>'),
          reason: '$channel 절이 없으면 그 경로는 기본 동작(전부 백업)입니다.',
        );
      }

      // 두 절 각각이 sharedpref 를 빼는지 본다. 여기에 초안 큐가 산다.
      final cloud = rules.substring(
          rules.indexOf('<cloud-backup>'), rules.indexOf('</cloud-backup>'));
      final transfer = rules.substring(
          rules.indexOf('<device-transfer>'), rules.indexOf('</device-transfer>'));

      for (final entry in {'cloud-backup': cloud, 'device-transfer': transfer}.entries) {
        expect(
          entry.value,
          contains('domain="sharedpref"'),
          reason: '${entry.key} 가 sharedpref 를 안 빼면 walk_outbox_pending_v1 이 '
              '그 경로로 나갑니다 — 좌표가 든 바로 그 키입니다.',
        );
      }
    });

    test('초안 큐가 정말 좌표를 담는다 — 안 담으면 위 검사들이 아무것도 안 지킨다', () {
      // 이 단언이 전제를 잰다. walk_outbox 가 경로를 저장 안 하게 바뀌면 위 셋의
      // 이유가 사라지므로, 그때는 이 파일을 다시 읽어야 한다.
      final outbox = _read(File('lib/v2/data/walk_outbox.dart'));

      expect(
        outbox,
        contains("'path': path"),
        reason: '초안이 원시 좌표열을 shared_preferences 에 남기는 것이 이 검사의 전제입니다.',
      );
      expect(outbox, contains('walk_outbox_pending_v1'));
    });
  });
}
