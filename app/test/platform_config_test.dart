// 딥링크 복귀에 필요한 플랫폼 설정 파일을 문자열로 검증한다.
//
// 브라우저에서 heattrip://login-callback 으로 앱에 돌아오는 구간 자체는 OS 레벨
// URL 핸들러를 타므로 flutter test 로 자동화할 수 없다(이슈 #21 "테스트하지 않는 것").
// 자동 테스트가 막을 수 있는 것은 "설정 파일이 올바른 값을 갖는가"까지다.
//
// 파일을 dart:io 로 직접 읽는다 — `flutter test` 의 작업 디렉터리는 app/ 이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ios/Runner/Info.plist', () {
    late String plist;

    setUpAll(() {
      final file = File('ios/Runner/Info.plist');
      expect(file.existsSync(), isTrue, reason: 'ios/Runner/Info.plist 가 없다');
      plist = file.readAsStringSync();
    });

    test('CFBundleURLTypes 로 커스텀 스킴을 등록한다', () {
      expect(plist, contains('CFBundleURLTypes'));
      expect(plist, contains('CFBundleURLSchemes'));
    });

    test('등록된 스킴이 heattrip 이고 URL 이름이 번들 ID 와 같다', () {
      expect(plist, contains('<string>heattrip</string>'));
      expect(plist, contains('CFBundleURLName'));
      expect(plist, contains('<string>com.cetacealab.heattrip</string>'));
    });

    test('사진 고르기 문구가 있다 — 커뮤니티 글에 사진을 붙인다 (#429)', () {
      // iOS 14+ 의 image_picker 는 PHPicker 라 이 문구 없이도 창이 뜨지만, 플러그인 README 가
      // 요구하고 iOS 13 이하에서는 없으면 고르는 순간 앱이 죽는다. 문구에 "위치 정보는 지운다" 를
      // 적은 것은 약속이다 — `image_prep_test` 가 그 약속을 바이트로 잰다.
      expect(plist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
      expect(plist, contains('위치 정보는 지우고 올려요'));
    });
  });

  group('android/app/src/main/AndroidManifest.xml', () {
    late String manifest;

    setUpAll(() {
      final file = File('android/app/src/main/AndroidManifest.xml');
      expect(file.existsSync(), isTrue, reason: 'AndroidManifest.xml 이 없다');
      manifest = file.readAsStringSync();
    });

    test('heattrip://login-callback 을 받는 intent-filter 가 있다', () {
      expect(manifest, contains('android:scheme="heattrip"'));
      expect(manifest, contains('android:host="login-callback"'));
    });

    test('커스텀 스킴에 의미 없는 autoVerify 를 걸지 않는다', () {
      // autoVerify 는 App Links(https) 전용이다. 커스텀 스킴에 붙여봐야
      // 검증할 assetlinks.json 도 없고, 딥링크 동작에 아무 영향이 없다.
      expect(manifest, isNot(contains('android:autoVerify')));
    });

    test('flutter_web_auth_2 의 CallbackActivity 가 등록되어 있다', () {
      // 플러그인은 CallbackActivity.onCreate 에서만 대기 중인 Result 를 완료시킨다.
      // MainActivity 로만 받으면 앱은 앞으로 나오지만 Future 가 끝나지 않는다.
      expect(
        manifest,
        contains('com.linusu.flutter_web_auth_2.CallbackActivity'),
      );
    });
  });
}
