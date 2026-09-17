// 소셜 로그인 왕복 전체 — state 생성·대조와 코드 교환의 이음새. (이슈 #14)
//
// `FlutterWebAuth2.authenticate` 는 static 이라 스텁이 불가능하다. 그래서
// `SocialLoginService` 는 인증 왕복(`authenticator`)·코드 교환(`exchanger`)·
// 토큰 저장(`tokenStore`) 세 자리를 주입점으로 열어 둔다. 여기서 그 셋을 갈아끼워
// 순수 함수 테스트가 닿지 못하는 **순서와 이음새**를 확인한다.
//
// 자동화할 수 없는 것: 시스템 브라우저가 `pawloop://` 스킴으로 앱에 복귀하는 구간.
// 그건 플랫폼 채널 + AndroidManifest/Info.plist 설정이라 위젯 테스트의 사정권 밖이다
// (완료 조건 7 은 수동 체크리스트로 남는다).

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';
import 'package:heat_trip_flutter/features/auth/service/oauth_callback.dart';
import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';

class _FakeTokenStore implements AuthTokenStore {
  String? access;
  String? refresh;
  bool cleared = false;
  Object? throwOnSave;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    if (throwOnSave != null) throw throwOnSave!;
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
  }

  @override
  Future<void> clear() async => cleared = true;
}

/// 인증 시작 URL 에서 앱이 붙인 state 를 꺼낸다 — 서버가 하는 일과 같다.
String _stateFrom(String url) => Uri.parse(url).queryParameters['state'] ?? '';

void main() {
  late _FakeTokenStore store;

  setUp(() {
    store = _FakeTokenStore();
    SocialLoginService.tokenStore = store;
  });

  tearDown(SocialLoginService.resetForTest);

  /// 서버처럼 행동하는 스텁: 받은 state 를 그대로 돌려준다.
  void echoingServer({String code = 'CODE-1', String? forceState}) {
    SocialLoginService.authenticator = ({
      required url,
      required callbackUrlScheme,
    }) async {
      final state = forceState ?? _stateFrom(url);
      return 'pawloop://login-callback?code=$code&state=$state';
    };
  }

  group('인증 시작 URL', () {
    test('state 를 쿼리로 붙여 보낸다 — 서버가 그것을 왕복 동안 붙든다', () async {
      String? seenUrl;
      SocialLoginService.authenticator = ({
        required url,
        required callbackUrlScheme,
      }) async {
        seenUrl = url;
        return 'pawloop://login-callback?error=access_denied';
      };

      await SocialLoginService.signIn('kakao');

      expect(seenUrl, isNotNull);
      expect(Uri.parse(seenUrl!).path, endsWith('/oauth2/authorization/kakao'));
      expect(
        _stateFrom(seenUrl!),
        matches(r'^[A-Za-z0-9_-]{16,128}$'),
        reason: 'state 를 보내지 않으면 서버가 딥링크에 실어 줄 값이 없다',
      );
    });

    test('로그인마다 다른 state 를 쓴다 — 값이 고정이면 대조가 통과 의식일 뿐이다', () async {
      final seen = <String>[];
      SocialLoginService.authenticator = ({
        required url,
        required callbackUrlScheme,
      }) async {
        seen.add(_stateFrom(url));
        return 'pawloop://login-callback?error=access_denied';
      };

      await SocialLoginService.signIn('kakao');
      await SocialLoginService.signIn('kakao');

      expect(seen.toSet().length, 2);
    });
  });

  group('성공 경로', () {
    test('state 가 맞으면 코드를 교환해 토큰을 저장하고 성공을 돌려준다', () async {
      echoingServer(code: 'CODE-42');
      String? exchangedCode;
      String? exchangedState;
      String? exchangedProvider;
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async {
        exchangedProvider = provider;
        exchangedCode = code;
        exchangedState = state;
        return const AuthTokens(
          accessToken: 'AT-1',
          refreshToken: 'RT-1',
          expiresIn: 3600,
          isNew: true,
        );
      };

      final result = await SocialLoginService.signIn('google');

      expect(result.ok, isTrue);
      expect(result.isNew, isTrue,
          reason: '#14 이전에는 딥링크에 isNew 를 실을 방법이 없어 항상 false 였다');
      expect(exchangedProvider, 'google');
      expect(exchangedCode, 'CODE-42');
      expect(exchangedState, isNotEmpty);
      expect(store.access, 'AT-1');
      expect(store.refresh, 'RT-1');
    });

    test('교환에 보내는 state 는 인증 시작 때 만든 그 값이다', () async {
      String? sentState;
      SocialLoginService.authenticator = ({
        required url,
        required callbackUrlScheme,
      }) async {
        sentState = _stateFrom(url);
        return 'pawloop://login-callback?code=C&state=$sentState';
      };
      String? exchangedState;
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async {
        exchangedState = state;
        return const AuthTokens(accessToken: 'AT', expiresIn: 1);
      };

      await SocialLoginService.signIn('kakao');

      expect(exchangedState, sentState);
    });
  });

  group('state 불일치 (완료 조건 4)', () {
    test('돌아온 state 가 다르면 로그인 실패이고 교환을 시도조차 하지 않는다', () async {
      echoingServer(forceState: 'someone-elses-state');
      var exchangeCalled = false;
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async {
        exchangeCalled = true;
        return const AuthTokens(accessToken: 'AT', expiresIn: 1);
      };

      final result = await SocialLoginService.signIn('kakao');

      expect(result.ok, isFalse);
      expect(result.outcome, SocialLoginOutcome.serverError);
      expect(
        exchangeCalled,
        isFalse,
        reason: '대조에 실패한 코드를 교환하면 대조가 있으나 마나가 된다',
      );
      expect(store.access, isNull);
    });

    test('state 가 아예 빠진 콜백도 실패다', () async {
      SocialLoginService.authenticator = ({
        required url,
        required callbackUrlScheme,
      }) async => 'pawloop://login-callback?code=CODE-1';

      expect((await SocialLoginService.signIn('kakao')).ok, isFalse);
    });
  });

  group('교환 실패', () {
    test('교환이 null 이면 서버 오류다 — 토큰을 저장하지 않는다', () async {
      echoingServer();
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async => null;

      final result = await SocialLoginService.signIn('kakao');

      expect(result.outcome, SocialLoginOutcome.serverError);
      expect(store.access, isNull);
    });

    test('교환이 네트워크 예외로 실패하면 networkError 다 — 서버 오류로 뭉개지 않는다', () async {
      echoingServer();
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async => throw http.ClientException('no route');

      final result = await SocialLoginService.signIn('kakao');

      expect(result.outcome, SocialLoginOutcome.networkError);
    });

    test('토큰 저장이 실패하면 성공이라고 말하지 않는다', () async {
      echoingServer();
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async => const AuthTokens(accessToken: 'AT', expiresIn: 1);
      store.throwOnSave = StateError('keystore unavailable');

      final result = await SocialLoginService.signIn('kakao');

      expect(result.outcome, SocialLoginOutcome.serverError);
    });
  });

  group('취소·오류 딥링크', () {
    test('사용자가 거부하면 canceled 이고 교환하지 않는다', () async {
      SocialLoginService.authenticator = ({
        required url,
        required callbackUrlScheme,
      }) async => 'pawloop://login-callback?error=access_denied';
      var exchangeCalled = false;
      SocialLoginService.exchanger = ({
        required provider,
        required code,
        required state,
      }) async {
        exchangeCalled = true;
        return null;
      };

      final result = await SocialLoginService.signIn('kakao');

      expect(result.outcome, SocialLoginOutcome.canceled);
      expect(exchangeCalled, isFalse);
    });

    test('서버가 보낸 오류 코드는 serverError 다', () async {
      SocialLoginService.authenticator = ({
        required url,
        required callbackUrlScheme,
      }) async => 'pawloop://login-callback?error=account_state_invalid';

      expect(
        (await SocialLoginService.signIn('kakao')).outcome,
        SocialLoginOutcome.serverError,
      );
    });
  });
}
