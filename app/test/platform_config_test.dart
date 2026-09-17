// 딥링크 복귀에 필요한 플랫폼 설정 파일을 문자열로 검증한다.
//
// 브라우저에서 pawloop://login-callback 으로 앱에 돌아오는 구간 자체는 OS 레벨
// URL 핸들러를 타므로 flutter test 로 자동화할 수 없다(이슈 #21 "테스트하지 않는 것").
// 자동 테스트가 막을 수 있는 것은 "설정 파일이 올바른 값을 갖는가"까지다.
//
// 파일을 dart:io 로 직접 읽는다 — `flutter test` 의 작업 디렉터리는 app/ 이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 앱 식별자 — 사기로 한 도메인 `pawloop.app` 을 뒤집은 것 (#597).
///
/// 이 값은 안드로이드 · iOS · 소스 폴더 경로 · 문서에 각각 따로 적힌다. 한 곳만 바꾸고
/// 나머지를 잊는 것이 이 계열의 전형적인 사고인데, 그러면 **빌드는 통과하고** 스토어
/// 등록이나 OAuth 콘솔에서야 어긋난 것이 드러난다.
const String kAppId = 'app.pawloop';

void main() {
  // 식별자가 박히는 자리가 여섯이다. 하나씩 따로 재면 "한 곳만 고쳤다" 를 못 잡는다 —
  // 그래서 전부 같은 상수와 대조한다.
  group('앱 식별자가 모든 자리에서 같다 (#597)', () {
    String read(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 가 없다');
      return file.readAsStringSync();
    }

    test('안드로이드 namespace 와 applicationId', () {
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, contains('namespace = "$kAppId"'));
      expect(gradle, contains('applicationId = "$kAppId"'));
    });

    test('안드로이드 매니페스트 둘 (main · debug)', () {
      expect(read('android/app/src/main/AndroidManifest.xml'),
          contains('package="$kAppId"'));
      expect(read('android/app/src/debug/AndroidManifest.xml'),
          contains('package="$kAppId"'));
    });

    test('MainActivity 의 package 선언과 폴더 경로가 식별자를 따른다', () {
      // 폴더가 package 와 다르면 코틀린은 경고만 내고 넘어가는 경우가 있다.
      // 그래서 경로를 식별자에서 **만들어** 확인한다 — 손으로 적은 경로를 믿지 않는다.
      final dir = 'android/app/src/main/kotlin/${kAppId.replaceAll('.', '/')}';
      final src = read('$dir/MainActivity.kt');

      // `contains('package $kAppId')` 로 물으면 `package app.pawloopX` 도 통과한다.
      // 선언을 뽑아서 통째로 견준다.
      final declared =
          RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(src)?.group(1);
      expect(declared, kAppId, reason: 'MainActivity 의 package 선언이 식별자와 다르다');
    });

    test('iOS 번들 ID — pbxproj 의 모든 타깃', () {
      final pbx = read('ios/Runner.xcodeproj/project.pbxproj');
      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(pbx)
          .map((m) => m.group(1)!.trim())
          .toSet();

      expect(ids, isNotEmpty, reason: 'pbxproj 에 번들 ID 가 하나도 없다 — 이 검사가 볼 곳이 사라졌다');
      // 앱 타깃은 식별자 그대로, 테스트 타깃은 `<식별자>.RunnerTests` 다.
      //
      // `startsWith` 로 물으면 안 된다 — `app.pawloopX` 도 통과한다. 이 저장소에서
      // 부분 문자열로 물었다가 검사가 아무것도 안 보던 일이 이미 세 번 있었다 (#601·#603).
      expect(ids, {kAppId, '$kAppId.RunnerTests'},
          reason: 'pbxproj 의 번들 ID 가 식별자와 어긋난다');
    });

    test('iOS CFBundleURLName 이 번들 ID 와 같다', () {
      expect(read('ios/Runner/Info.plist'), contains('<string>$kAppId</string>'));
    });

    test('네이버 지도로 넘길 때 쓰는 appname 도 같은 식별자다', () {
      // 네이버 SDK 는 이 값을 패키지명과 대조한다. 어긋나면 지도 앱이 안 열린다.
      expect(read('lib/v2/data/external_maps.dart'), contains('appname=$kAppId'));
    });

    test('옛 식별자가 앱 안에 남아 있지 않다', () {
      for (final path in [
        'android/app/build.gradle.kts',
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/debug/AndroidManifest.xml',
        'ios/Runner/Info.plist',
        'ios/Runner.xcodeproj/project.pbxproj',
        'lib/v2/data/external_maps.dart',
      ]) {
        expect(read(path), isNot(contains('cetacealab')),
            reason: '$path 에 옛 식별자가 남아 있다');
      }
    });

    // 저장소 전체를 훑는다 — 문서에 옛 식별자가 남으면 다음 사람이 그걸 보고
    // 콘솔에 등록한다. 빌드는 멀쩡한 채로 로그인만 안 되는 종류의 사고다.
    //
    // 역사 기록 둘은 일부러 남긴다. 그때의 결정을 적은 글이라 고치면 기록이 아니라
    // 위조가 된다 — decision-log 의 그 줄들에는 "실행됨" 표시를 덧붙여 뒀다.
    test('저장소 문서에도 옛 식별자가 남아 있지 않다 — 역사 기록 둘만 예외', () {
      const history = {
        '../docs/99-decisions/decision-log.md',
        'docs/legacy/07-implementation-plan.md',
      };

      final offenders = <String>[];
      for (final root in ['.', '../docs', '../backend/src', '../README.md']) {
        final entity = FileSystemEntity.typeSync(root) == FileSystemEntityType.file
            ? [File(root)]
            : Directory(root)
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => !f.path.contains('${Platform.pathSeparator}build${Platform.pathSeparator}'))
                .where((f) => !f.path.contains('.dart_tool'))
                .where((f) => !f.path.contains('${Platform.pathSeparator}Pods${Platform.pathSeparator}'))
                .where((f) => !f.path.contains('${Platform.pathSeparator}bin${Platform.pathSeparator}'))
                .toList();

        for (final file in entity) {
          final normalized = file.path.replaceAll(r'\', '/');
          if (history.any((h) => normalized.endsWith(h.replaceAll('../', '')))) continue;
          if (normalized.endsWith('platform_config_test.dart')) continue;
          String text;
          try {
            text = file.readAsStringSync();
          } catch (_) {
            continue; // 텍스트가 아니면 지나간다
          }
          if (text.contains('cetacealab')) offenders.add(normalized);
        }
      }

      expect(offenders, isEmpty,
          reason: '옛 식별자가 남은 파일이 있다. 역사 기록이라면 위 history 목록에 더한다.');
    });
  });

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

    test('등록된 스킴이 pawloop 이고 URL 이름이 번들 ID 와 같다', () {
      // 2026-09-17 까지는 다른 스킴이었다(#649). 예전 패키지로 배포된 앱이 같은 스킴을
      // 주장해서, 그 앱이 깔린 폰에서는 OS 가 어느 앱에 줄지 못 정해 로그인이 멈췄다.
      expect(plist, contains('<string>pawloop</string>'));
      expect(plist, contains('CFBundleURLName'));
      expect(plist, contains('<string>app.pawloop</string>'));
    });

    test('아이폰 전용이다 — 아이패드 레이아웃이 없는데 지원한다고 말하지 않는다', () {
      // `TARGETED_DEVICE_FAMILY` 가 "1,2"(아이폰+아이패드)였다. 아이패드 폭에 맞춘
      // 레이아웃은 한 줄도 없는데 지원한다고 선언한 것이라, 앱스토어에 내면 13인치
      // 아이패드 스크린샷이 **필수**가 되고 심사관이 아이패드로 켜 본다.
      //
      // **방향이 한쪽이다** — 나중에 아이패드를 더하는 것은 되지만, 이미 낸 앱에서
      // 아이패드 지원을 빼는 것은 애플이 막는다. 그래서 내기 전에 "1" 로 좁힌다.
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')), reason: '''
아이패드를 지원한다고 선언하면 되돌릴 수 없다 — 애플이 이미 낸 앱에서 기기군을 줄이는 것을
막는다. 진짜로 아이패드를 지원할 준비가 됐을 때만 이 검사를 고쳐라.''');
      expect(RegExp(r'TARGETED_DEVICE_FAMILY = "1";').allMatches(pbx).length, 3,
          reason: 'Runner 의 Debug·Release·Profile 세 자리에 다 있어야 한다');
    });

    test('세로만 쓴다 — 가로 레이아웃을 맞춘 적이 없다', () {
      // 가로를 선언해 두면 심사관이 돌려 본다. 앱은 `SystemChrome` 으로 방향을
      // 고정하지 않아서(코드에 한 줄도 없다) Info.plist 가 유일한 제어다.
      expect(plist, contains('UIInterfaceOrientationPortrait'));
      for (final landscape in const [
        'UIInterfaceOrientationLandscapeLeft',
        'UIInterfaceOrientationLandscapeRight',
      ]) {
        expect(plist, isNot(contains(landscape)), reason: '''
$landscape 를 선언해 놓고 가로 레이아웃이 없으면 심사관이 돌렸을 때 깨진 화면을 본다.''');
      }
      expect(plist, isNot(contains('UISupportedInterfaceOrientations~ipad')),
          reason: '아이폰 전용인데 아이패드 방향 키가 남아 있다');
    });

    test('수출규정 답을 미리 적어 둔다 — 업로드마다 묻지 않게', () {
      // 없으면 빌드를 올릴 때마다 App Store Connect 가 암호화 수출규정을 묻고,
      // 답하기 전까지 그 빌드를 심사에 못 건다. HTTPS 만 쓰므로 면제가 맞다.
      expect(plist, contains('<key>ITSAppUsesNonExemptEncryption</key>'));
      expect(plist, contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
          reason: '면제라고 답해 두는 것이다 — true 면 추가 서류를 내야 한다');
    });

    test('한국어 앱이라고 선언한다 — 앱은 Locale(ko) 하나로 고정돼 있다', () {
      // `lib/core/localization.dart` 가 `appSupportedLocales = [Locale('ko')]` 로
      // 못 박아 두었는데 Info.plist 는 아무 말이 없었다. 그러면 앱스토어가 개발
      // 지역(en)만 보고 영어 앱으로 올린다.
      expect(plist, contains('<key>CFBundleLocalizations</key>'));
      expect(plist, contains('<string>ko</string>'));
    });

    test('위치 문구가 백그라운드 기록을 말한다 — 선언만 해 놓고 숨기지 않는다', () {
      // `UIBackgroundModes` 에 `location` 을 선언해 놓고 문구는 그 말을 안 했다.
      // 심사 지침 5.1.1(ii) 가 "clearly and completely" 를 요구한다.
      expect(plist, contains('<key>UIBackgroundModes</key>'));
      expect(plist, contains('<string>location</string>'));
      final match = RegExp(
              r'<key>NSLocationWhenInUseUsageDescription</key>\s*<string>([^<]*)</string>')
          .firstMatch(plist);
      expect(match, isNotNull, reason: '위치 문구를 못 찾았다');
      expect(match!.group(1), contains('백그라운드'), reason: '''
화면을 꺼도 경로를 기록하면서 문구가 그 말을 안 하면, 선언(UIBackgroundModes=location)과
사용자에게 한 말이 어긋난다. 심사 지침 5.1.1(ii) 가 그것을 막는다.''');
      expect(match.group(1), contains('산책을 끝내면 멈춰요'),
          reason: '언제 멈추는지까지 말해야 "completely" 다');
    });

    test('Always 위치 권한은 요구하지 않는다 — 쓰지 않는 것을 묻지 않는다', () {
      expect(plist, isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
          reason: '''
문구를 넣으면 OS 가 "항상 허용" 을 물을 수 있는 앱이 된다. 우리는 산책 중 전경 서비스로만
받으므로 요구할 이유가 없고, 심사에서 이유를 따로 대야 한다.''');
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

    test('pawloop://login-callback 을 받는 intent-filter 가 있다', () {
      expect(manifest, contains('android:scheme="pawloop"'));
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
