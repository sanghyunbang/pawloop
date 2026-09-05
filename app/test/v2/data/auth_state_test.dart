// AuthState — 앱 시작 시 토큰 검증 · isNew 온보딩 분기 · 로그아웃 (이슈 #12).
//
// 실제 네트워크를 타지 않는다. `package:http/testing.dart` 의 `MockClient` 가 요청을
// 전부 가로채고, 토큰 저장소는 손으로 만든 Fake 를 꽂는다 —
// `flutter_secure_storage` 는 플랫폼 채널이라 `flutter_test` 안에서는 쓰기가 던진다.
// (정책 #21)
//
// `AuthState` 가 저장소와 리포지토리를 `configureForTest` 로 받도록 만든 이유가 이것이다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/v2/data/consent_gate.dart';
import 'package:heat_trip_flutter/v2/data/consent_repository.dart';
import 'package:heat_trip_flutter/v2/screens/settings/legal_document_screen.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';

const _base = 'https://api.example.test';

/// 메모리 위의 토큰 저장소. 실저장소(`SecureTokenStore`)의 규칙만 흉내 낸다.
class _FakeTokenStore implements AuthTokenStore {
  String? access;
  String? refresh;
  int clearCount = 0;

  _FakeTokenStore({this.access, this.refresh});

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    access = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    clearCount++;
  }
}

/// 계약 `User` 의 200 본문.
String _userJson({
  int id = 7,
  String? nickname = '보리아빠',
  String? provider = 'kakao',
}) => jsonEncode({
  'id': id,
  'email': 'bori@example.test',
  'name': '방보리',
  'nickname': nickname,
  'provider': provider,
  'imageUrl': null,
});

/// 한글이 든 본문은 charset 을 밝혀야 한다 — [http.Response] 는 content-type 에
/// charset 이 없으면 **latin1** 로 인코딩하고 한글에서 ArgumentError 를 던진다.
http.Response _json(String body, [int code = 200]) => http.Response(
      body,
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// [handler] 를 태운 `AuthState` 를 세운다. 저장소도 함께 돌려준다.
_FakeTokenStore _install(
  MockClientHandler handler, {
  String? accessToken = 'stored-access-token',
  String? refreshToken,
}) {
  final store = _FakeTokenStore(access: accessToken, refresh: refreshToken);
  final mock = MockClient(handler);
  AuthState.configureForTest(
    tokenStore: store,
    repository: AuthRepositoryImpl(
      baseUrl: _base,
      plainClient: mock,
      authedClient: AuthedClient(inner: mock, baseUrl: _base, store: store),
    ),
  );
  return store;
}

/// 서버를 못 부르는 상황. 동의 게이트가 캐시로 떨어지게 한다.
class _DeadConsentServer implements ConsentRepository {
  @override
  Future<List<ServerConsent>> fetch() async => throw const ConsentFailure();
  @override
  Future<List<ServerConsent>> record(List<ConsentEntry> entries) async => throw const ConsentFailure();
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  tearDown(AuthState.resetForTest);

  group('init() — 저장된 토큰을 서버에 물어본다', () {
    test('토큰이 없으면 서버에 묻지 않고 unauthenticated 다', () async {
      var calls = 0;
      _install((req) async {
        calls++;
        return http.Response('{}', 200);
      }, accessToken: null);

      await AuthState.init();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
      expect(AuthState.user, isNull);
      expect(calls, 0, reason: '토큰이 없는데 /auth/me 를 부를 이유가 없다');
    });

    test('빈 문자열 토큰도 "없음"으로 본다', () async {
      _install((req) async => http.Response('{}', 200), accessToken: '');

      await AuthState.init();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
    });

    test('/auth/me 200 이면 authenticated 이고 id·provider·nickname 을 보관한다', () async {
      final seen = <http.Request>[];
      _install((req) async {
        seen.add(req);
        return _json(_userJson());
      });

      await AuthState.init();

      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/auth/me');
      expect(AuthState.status.value, AuthStatus.authenticated);
      expect(AuthState.user!.id, 7);
      expect(AuthState.user!.provider, 'kakao');
      expect(AuthState.user!.nickname, '보리아빠');
    });

    test('서버가 폐기한 토큰(401)이고 갱신도 실패하면 unauthenticated 다', () async {
      // RT 가 없으므로 AuthedClient 는 갱신 자체를 시도하지 못하고 세션을 끝낸다.
      final store = _install(
        (req) async => http.Response('', 401),
        refreshToken: null,
      );

      await AuthState.init();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
      expect(AuthState.user, isNull);
      expect(store.access, isNull, reason: 'AuthedClient 가 죽은 토큰을 지웠어야 한다');
    });

    test('갱신도 401 이면 unauthenticated 다 — RT 가 있어도 마찬가지', () async {
      final store = _install(
        (req) async => http.Response('', 401),
        refreshToken: 'dead-refresh-token',
      );

      await AuthState.init();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
      expect(store.refresh, isNull);
    });

    test('본문에 id 가 없으면(계약 위반) 로그인으로 치지 않는다', () async {
      _install((req) async => _json(jsonEncode({'nickname': '보리'})));

      await AuthState.init();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
    });

    test('네트워크 오류로는 로그아웃시키지 않는다 — 토큰을 그대로 둔다', () async {
      // 비행기 모드로 앱을 켰다고 재로그인을 시키면 멀쩡한 토큰을 가진 사용자를 쫓아낸다.
      final store = _install((req) async => throw const SocketException('offline'));

      await AuthState.init();

      expect(AuthState.status.value, AuthStatus.authenticated);
      expect(AuthState.user, isNull, reason: '프로필은 못 받았다');
      expect(store.access, 'stored-access-token');
    });

    test('init() 가 끝나기 전까지 상태는 unknown 이다 — 스플래시 구간', () async {
      final gate = Completer<http.Response>();
      _install((req) async => gate.future);

      final pending = AuthState.init();
      await Future<void>.delayed(Duration.zero);

      expect(
        AuthState.status.value,
        AuthStatus.unknown,
        reason: '여기서 이미 확정돼 있으면 로그인 화면이 깜빡인다(완료 조건 7)',
      );

      gate.complete(_json(_userJson()));
      await pending;
      expect(AuthState.status.value, AuthStatus.authenticated);
    });
  });

  group('completeLogin() — isNew 온보딩 분기', () {
    test('isNew == true 면 onboarding 으로 확정된다', () async {
      _install((req) async => _json(_userJson()));

      await AuthState.completeLogin(isNew: true);

      expect(AuthState.status.value, AuthStatus.onboarding);
      expect(AuthState.user!.nickname, '보리아빠');
    });

    test('isNew == false 면 authenticated 로 확정된다', () async {
      _install((req) async => _json(_userJson()));

      await AuthState.completeLogin(isNew: false);

      expect(AuthState.status.value, AuthStatus.authenticated);
    });

    test('로그인 직후 401 이면 온보딩이 아니라 unauthenticated 다', () async {
      _install((req) async => http.Response('', 401));

      await AuthState.completeLogin(isNew: true);

      expect(AuthState.status.value, AuthStatus.unauthenticated);
    });
  });

  group('logout() — 서버 폐기 + 로컬 삭제', () {
    test('POST /auth/logout 을 실제로 부른다', () async {
      final seen = <http.Request>[];
      final store = _install((req) async {
        seen.add(req);
        return http.Response('', 204);
      });
      AuthState.status.value = AuthStatus.authenticated;

      await AuthState.logout();

      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/auth/logout');
      expect(
        seen.single.headers['Authorization'],
        'Bearer stored-access-token',
        reason: '서버는 이 헤더로 주체를 알아내 그 사용자의 RT 를 전부 폐기한다',
      );
      expect(store.access, isNull);
      expect(AuthState.status.value, AuthStatus.unauthenticated);
    });

    test('서버 호출이 SocketException 으로 실패해도 로컬 토큰은 지워진다', () async {
      // 비행기 모드에서 로그아웃을 눌렀는데 토큰이 남아 있으면, 사용자는 로그아웃했다고
      // 믿는 채로 다음 실행에서 다시 로그인 상태가 된다.
      final store = _install(
        (req) async => throw const SocketException('airplane mode'),
        refreshToken: 'live-refresh-token',
      );
      AuthState.status.value = AuthStatus.authenticated;

      await AuthState.logout();

      expect(store.clearCount, greaterThan(0));
      expect(store.access, isNull);
      expect(store.refresh, isNull);
      expect(AuthState.status.value, AuthStatus.unauthenticated);
      expect(AuthState.user, isNull);
    });

    test('서버가 5xx 를 줘도 로컬 토큰은 지워진다', () async {
      final store = _install((req) async => http.Response('', 500));
      AuthState.status.value = AuthStatus.authenticated;

      await AuthState.logout();

      expect(store.access, isNull);
      expect(AuthState.status.value, AuthStatus.unauthenticated);
    });
  });

  group('clearLocalSession() — 서버를 부르지 않는 정리(회원 탈퇴)', () {
    test('서버를 부르지 않는다 — 계정이 이미 지워졌으므로 /auth/logout 은 401 이다', () async {
      final seen = <http.Request>[];
      final store = _install((req) async {
        seen.add(req);
        return http.Response('', 204);
      });
      AuthState.status.value = AuthStatus.authenticated;

      await AuthState.clearLocalSession();

      expect(seen, isEmpty, reason: '탈퇴 뒤에는 부를 세션이 없다');
      expect(store.access, isNull);
      expect(store.refresh, isNull);
    });

    test('이 계정의 약관 동의도 지운다 — 같은 id 로 다시 온 사람에게 남으면 안 된다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _install((req) async => http.Response('', 204));
      AuthState.signInForTest(const AuthUser(id: 11, nickname: '탈퇴자'));
      // 동의는 서버가 정본이고 기기는 캐시다(#190). 여기서 재는 것은 "탈퇴가 **캐시**를
      // 지우는가" 이므로, 캐시를 직접 심고 서버가 죽은 게이트로 읽는다 — 서버가 살아
      // 있으면 캐시와 무관하게 서버 답을 쓰기 때문이다.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ConsentGate.keyFor(11),
          '{"TERMS":"${LegalDocument.terms.version}","PRIVACY":"${LegalDocument.privacy.version}","LOCATION":"${LegalDocument.location.version}"}');
      await prefs.setBool(ConsentGate.marketingKeyFor(11), true);
      final offline = ConsentGate(repository: _DeadConsentServer());
      expect(await offline.hasAgreed(11), isTrue);

      await AuthState.clearLocalSession();

      expect(await offline.hasAgreed(11), isFalse,
          reason: '남으면 그 사람은 약관을 본 적이 없는데 동의한 것이 된다');
      expect(await offline.marketingOptIn(11), isFalse);
    });

    test('상태도 함께 내린다 — 이게 없으면 로그인 화면이 홈으로 되튕긴다', () async {
      // 실제로 났던 결함이다. 화면이 저장소만 비우고 status 를 authenticated 로
      // 두면, authRedirect 가 로그인 화면 진입을 홈으로 돌려보낸다.
      _install((req) async => http.Response('', 204));
      AuthState.status.value = AuthStatus.authenticated;

      await AuthState.clearLocalSession();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
      expect(AuthState.user, isNull);
      expect(
        AuthState.sessionEnded,
        isTrue,
        reason: '방금 세션이 끝난 사람이므로 로그인 화면을 띄워야 한다',
      );
    });
  });

  group('AuthUser.fromJson', () {
    test('id 가 없으면 null — 계약이 required 로 못 박은 유일한 필드다', () {
      expect(AuthUser.fromJson({'nickname': '보리'}), isNull);
      expect(AuthUser.fromJson({'id': '7'}), isNull, reason: '문자열 id 는 계약 위반');
    });

    test('nullable 필드가 null 이어도 읽힌다 — 소셜 가입은 nickname 이 없을 수 있다', () {
      final user = AuthUser.fromJson({
        'id': 3,
        'nickname': null,
        'email': null,
        'provider': 'google',
      });

      expect(user!.id, 3);
      expect(user.nickname, isNull);
      expect(user.provider, 'google');
      expect(user.displayName, '이름 없는 계정');
    });

    test('공백뿐인 문자열은 없는 것으로 본다', () {
      final user = AuthUser.fromJson({'id': 1, 'nickname': '   '});
      expect(user!.nickname, isNull);
    });
  });

  // "로그인한 적 없음" 과 "방금 세션이 끝남" 을 라우터가 구분할 수 있어야
  // 폐기 토큰으로 앱을 켰을 때 홈이 아니라 로그인 화면이 뜬다(완료 조건 4·6).
  group('sessionEnded 신호', () {
    test('토큰이 아예 없는 시작은 신호를 켜지 않는다 — 둘러보기를 방해하지 않는다', () async {
      _install((req) async => http.Response('{}', 200), accessToken: null);

      await AuthState.init();

      expect(AuthState.sessionEnded, isFalse);
    });

    test('저장된 토큰이 401 로 거부되면 신호를 켠다', () async {
      _install((req) async => http.Response('', 401));

      await AuthState.init();

      expect(AuthState.sessionEnded, isTrue);
    });

    test('로그아웃도 신호를 켠다', () async {
      _install((req) async => http.Response('', 204));

      await AuthState.logout();

      expect(AuthState.sessionEnded, isTrue);
    });

    test('한 번 소비하면 꺼진다 — 로그인 화면을 닫을 때마다 끌려오면 안 된다', () async {
      _install((req) async => http.Response('', 204));
      await AuthState.logout();

      AuthState.consumeSessionEnded();

      expect(AuthState.sessionEnded, isFalse);
    });

    test('정상 로그인 시작은 신호를 켜지 않는다', () async {
      _install((req) async => _json(_userJson()));

      await AuthState.init();

      expect(AuthState.sessionEnded, isFalse);
    });
  });

  group('세션 만료 훅 (#11 배선)', () {
    test('markSessionExpired 는 상태를 내리고 user 를 비운다', () async {
      _install((req) async => _json(_userJson()));
      await AuthState.init();
      expect(AuthState.user, isNotNull);

      AuthState.markSessionExpired();

      expect(AuthState.status.value, AuthStatus.unauthenticated);
      expect(AuthState.user, isNull);
    });
  });
}
