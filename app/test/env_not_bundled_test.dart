// `.env` 가 앱 번들로 다시 새어들어가지 않게 막는 회귀 테스트. — 이슈 #29
//
// 왜 소스 파일을 읽어서 검사하는가:
//   `pubspec.yaml` 의 `assets:` 에 올라간 파일은 APK/IPA 안에
//   `assets/flutter_assets/<경로>` 로 **원본 그대로** 들어간다. 코드가 아니라
//   리소스라서 난독화도 최소화도 없다. `unzip -p app-release.apk` 한 줄이면
//   값이 그대로 나온다. 릴리스 APK 를 실제로 풀어보는 검증은 CI 예산상 돌리지
//   않으므로(안드로이드 툴체인 필요), 그 직전 단계인 "선언"을 못박는다.
//
// 파일을 dart:io 로 직접 읽는다 — `flutter test` 의 작업 디렉터리는 app/ 이다.
// (app/test/platform_config_test.dart 와 같은 방식)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app/pubspec.yaml', () {
    late String pubspec;

    setUpAll(() {
      final file = File('pubspec.yaml');
      expect(file.existsSync(), isTrue, reason: 'app/pubspec.yaml 이 없다');
      pubspec = file.readAsStringSync();
    });

    test('assets 에 .env 를 선언하지 않는다', () {
      // 주석(`# .env 는 ...`)은 걸리지 않도록 실제 목록 항목만 본다.
      final assetEntries = pubspec
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('- '))
          .map((l) => l.substring(2).trim());

      expect(
        assetEntries,
        isNot(contains('.env')),
        reason: '.env 를 에셋으로 올리면 APK 안에 원본 그대로 실려 나간다 (이슈 #29)',
      );
    });

    test('flutter_dotenv 에 의존하지 않는다', () {
      expect(
        pubspec,
        isNot(contains('flutter_dotenv:')),
        reason: 'flutter_dotenv 를 되살리면 .env 런타임 로드가 함께 돌아온다 (이슈 #29)',
      );
    });
  });

  test('lib/ 어디에서도 flutter_dotenv 를 import 하지 않는다', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => f.readAsStringSync().contains(
            "import 'package:flutter_dotenv/flutter_dotenv.dart'",
          ),
        )
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty, reason: '환경값은 Env(--dart-define)로만 읽는다 (이슈 #29)');
  });

  test('추적되는 dart-define 템플릿에 실제 비밀값이 없다', () {
    final file = File('dart-define.example.json');
    expect(file.existsSync(), isTrue, reason: 'app/dart-define.example.json 이 없다');
    final json = file.readAsStringSync();

    // 값이 채워져 있으면 안 되는 키들. 템플릿은 빈 문자열이어야 한다.
    for (final key in const ['NAVER_MAP_CLIENT_ID']) {
      expect(
        json,
        contains('"$key": ""'),
        reason: '$key 는 템플릿에서 빈 값이어야 한다 — 진짜 키를 여기 넣지 말 것',
      );
    }

    // 관광공사 서비스키는 **빈 값으로도** 있으면 안 된다 (이슈 #40). 템플릿에 자리가
    // 남아 있으면 다음 사람이 거기에 키를 채워 넣고, 그러면 다시 앱 바이너리로 들어간다.
    expect(
      json,
      isNot(contains('YOUR_DECODING_SERVICE_KEY')),
      reason: '이 키는 서버 환경변수로만 존재한다. 앱 빌드 설정에 자리를 만들지 말 것',
    );
  });

  group('.github/workflows/ci.yml', () {
    test('.env 를 만들어내는 단계가 남아 있지 않다', () {
      // app/ 밖이지만 이슈 #29 완료 조건 5번이라 여기서 함께 지킨다.
      final file = File('../.github/workflows/ci.yml');
      expect(file.existsSync(), isTrue, reason: '.github/workflows/ci.yml 이 없다');
      final ci = file.readAsStringSync();

      expect(
        ci,
        isNot(contains('.env.example')),
        reason: 'CI 가 .env 를 만들어야 한다면 앱이 아직 .env 에 묶여 있다는 뜻이다 (이슈 #29)',
      );
    });
  });
}
