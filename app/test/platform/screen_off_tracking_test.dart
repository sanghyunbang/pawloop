// 화면을 꺼도 산책이 이어지려면 플랫폼 선언이 맞아야 한다 (#335).
//
// 코드가 포그라운드 서비스를 요청해도 매니페스트에 권한이 없으면 Android 14+ 는
// SecurityException 으로 서비스를 죽인다. iOS 는 UIBackgroundModes 가 없으면 앱이 뒤로 가는
// 순간 위치 갱신을 멈춘다. 둘 다 런타임에야 드러나는 실수라 여기서 파일을 읽어 잡는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File get _manifest => File('android/app/src/main/AndroidManifest.xml');
File get _plist => File('ios/Runner/Info.plist');

String _read(File file) {
  if (!file.existsSync()) {
    fail('${file.path} 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  return file.readAsStringSync();
}

void main() {
  group('안드로이드 포그라운드 서비스', () {
    test('권한 넷 — FOREGROUND_SERVICE · FOREGROUND_SERVICE_LOCATION · POST_NOTIFICATIONS · WAKE_LOCK(enableWakeLock 이 요구, 없으면 서비스가 예외로 죽는다)', () {
      final m = _read(_manifest);
      for (final p in [
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.WAKE_LOCK',
      ]) {
        expect(m, contains('<uses-permission android:name="$p"'), reason: '$p 가 없으면 서비스가 시작 직후 죽거나(14+) 알림이 안 보인다(13+)');
      }
    });

    test('ACCESS_BACKGROUND_LOCATION 은 선언하지 않는다 — 앞에서 켠 포그라운드 서비스면 충분하고, 그 권한은 심사에서 별도 사유를 요구한다', () {
      expect(_read(_manifest), isNot(contains('android:name="android.permission.ACCESS_BACKGROUND_LOCATION"')));
    });
  });

  group('iOS 백그라운드 위치', () {
    test('UIBackgroundModes 에 location 이 있다', () {
      final p = _read(_plist);
      expect(p, contains('<key>UIBackgroundModes</key>'));
      final i = p.indexOf('<key>UIBackgroundModes</key>');
      final block = p.substring(i, p.indexOf('</array>', i));
      expect(block, contains('<string>location</string>'));
    });

    test('Always 는 여전히 요청하지 않는다 — 코드에서 잰다, plist 가 아니라', () {
      // **재는 대상을 바꾼 자리다.** 전에는 `NSLocationAlwaysAndWhenInUseUsageDescription`
      // 이 plist 에 **없는 것**으로 이 약속을 쟀다. 그런데 애플이 빌드를 받고
      // ITMS-90683 으로 그 키를 **요구**했다 — 우리가 안 써도 번들 안의 geolocator 가
      // `requestAlwaysAuthorization` 을 참조하기 때문이다(.ipa 의 `Runner` 바이너리에서
      // 그 문자열이 나온다).
      //
      // 약속 자체는 그대로다 — **우리는 Always 를 요청하지 않는다.** 그러니 plist 대신
      // 요청하는 쪽, 즉 코드를 잰다. 이쪽이 원래 재려던 것이기도 하다.
      final dart = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final offenders = <String>[];
      for (final f in dart) {
        final src = f.readAsStringSync();
        // 주석을 걷어낸다 — 설명으로 적은 낱말이 걸리면 안 된다.
        final code = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
        if (code.contains('requestAlwaysAuthorization') ||
            RegExp(r'requestPermission\([^)]*always').hasMatch(code)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '''
Always 권한을 요청하면 "항상 허용" 창이 뜨고, 산책 중에만 쓰겠다는 약속과 어긋난다.
WhenInUse 로 시작한 갱신을 UIBackgroundModes=location 이 이어 주므로 요청할 이유가 없다.''');

      // `NSLocationAlwaysUsageDescription`(iOS 10 이하의 "항상만") 은 애플이 요구하지
      // 않는다. 이건 여전히 없어야 한다.
      final p = _read(_plist);
      expect(p, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
      expect(p, isNot(contains('<key>NSLocationAlwaysUsageDescription</key>')));
    });
  });
}
