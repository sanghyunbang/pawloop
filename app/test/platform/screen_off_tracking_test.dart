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

    test('Always 는 여전히 요청하지 않는다 — WhenInUse 로 시작한 갱신을 백그라운드 모드가 이어 준다', () {
      final p = _read(_plist);
      expect(p, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
      expect(p, isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription</key>')));
      expect(p, isNot(contains('<key>NSLocationAlwaysUsageDescription</key>')));
    });
  });
}
