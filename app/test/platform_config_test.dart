// 딥링크 복귀에 필요한 플랫폼 설정 파일을 문자열로 검증한다.
//
// 브라우저에서 heattrip://login-callback 으로 앱에 돌아오는 구간 자체는 OS 레벨
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

    test('등록된 스킴이 heattrip 이고 URL 이름이 번들 ID 와 같다', () {
      expect(plist, contains('<string>heattrip</string>'));
      expect(plist, contains('CFBundleURLName'));
      expect(plist, contains('<string>app.pawloop</string>'));
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
