// Env 는 런타임 파일(.env) 없이 동작해야 한다. — 이슈 #29
//
// 예전에는 flutter_dotenv 가 `.env` 를 에셋에서 읽었고, `dotenv.load()` 전에
// `dotenv.env` 를 건드리면 NotInitializedError 가 났다. 그래서 위젯 테스트가
// HeatTrip 을 통째로 pump 하지 못하고 화면만 따로 띄우는 우회를 해야 했다.
// (app/test/v2/login_screen_test.dart 머리말 참고)
//
// 이제 값은 전부 컴파일 타임 --dart-define 이라 초기화 단계 자체가 없다.
// 이 테스트는 "아무 것도 주입하지 않은 상태"(= CI 가 도는 상태)의 기본값을 못박는다.
// dart-define 을 붙여서 돌리면(예: flutter test --dart-define=API_BASE=...)
// 당연히 그 값이 나오므로 이 파일은 정의값 없이 실행하는 것을 전제한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/config/env.dart';

void main() {
  group('Env — 초기화 없이 읽을 수 있다', () {
    test('어떤 게터도 예외를 던지지 않는다', () {
      expect(() => Env.apiBase, returnsNormally);
      expect(() => Env.isLocal, returnsNormally);
      expect(() => Env.naverMapClientId, returnsNormally);
      expect(() => Env.tourServiceKey, returnsNormally);
      expect(() => Env.mobileOs, returnsNormally);
      expect(() => Env.mobileApp, returnsNormally);
    });
  });

  group('Env — dart-define 미주입 시 기본값', () {
    test('apiBase 는 에뮬레이터 폴백으로 떨어진다', () {
      expect(Env.apiBase, Env.localEmulator);
      expect(Env.localEmulator, 'http://10.0.2.2:8080');
    });

    test('isLocal 은 폴백 주소를 로컬로 판정한다', () {
      expect(Env.isLocal, isTrue);
    });

    test('비밀값은 빈 문자열이다 — 소스에 하드코딩된 기본 키가 없다', () {
      expect(Env.naverMapClientId, isEmpty);
      expect(Env.tourServiceKey, isEmpty);
    });

    test('KTO 호출자 표기는 비밀이 아니므로 기본값을 갖는다', () {
      expect(Env.mobileOs, 'ETC');
      expect(Env.mobileApp, 'HeatTrip');
    });
  });
}
