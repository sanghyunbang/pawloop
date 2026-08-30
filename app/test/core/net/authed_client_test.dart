// AuthedClient — 헤더 일원화·401 갱신·single-flight 테스트 (이슈 #11).
//
// 실제 네트워크를 타지 않는다. `package:http/testing.dart` 의 `MockClient` 가
// 요청을 전부 가로채고, 토큰 저장소는 손으로 만든 Fake 를 꽂는다
// (`flutter_secure_storage` 는 플랫폼 채널이고 이 저장소에는 mockito 가 없다 — 정책 #21).
//
// `AuthedClient` 가 baseUrl 과 inner client 를 **주입받도록** 설계된 이유가 이것이다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/core/net/logging_client.dart';

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

String _tokensJson(String access, String refresh) => jsonEncode({
  'accessToken': access,
  'refreshToken': refresh,
  'expiresIn': 3600,
});

bool _isRefresh(http.Request req) => req.url.path == '/auth/token/refresh';

void main() {
  group('헤더 일원화', () {
    test('저장된 액세스 토큰이 Authorization 헤더로 자동 부착된다', () async {
      final seen = <http.Request>[];
      final client = AuthedClient(
        inner: MockClient((req) async {
          seen.add(req);
          return http.Response('{"ok":true}', 200);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1', refresh: 'RT-1'),
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 200);
      expect(seen.single.headers['authorization'], 'Bearer AT-1');
    });

    test('본문이 있는 요청에 JSON Content-Type 기본값이 붙는다', () async {
      final seen = <http.Request>[];
      final client = AuthedClient(
        inner: MockClient((req) async {
          seen.add(req);
          return http.Response('{"ok":true}', 201);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1'),
      );

      await client.postJson(
        Uri.parse('$_base/api/bookmarks'),
        body: {'placeId': 7},
      );

      expect(
        seen.single.headers['content-type'],
        AuthedClient.jsonContentType,
      );
      expect(seen.single.body, '{"placeId":7}');
    });

    test('토큰이 없으면 Authorization 헤더를 붙이지 않는다', () async {
      final seen = <http.Request>[];
      final client = AuthedClient(
        inner: MockClient((req) async {
          seen.add(req);
          return http.Response('[]', 200);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(),
      );

      await client.getJson(Uri.parse('$_base/api/public'));

      expect(seen.single.headers.containsKey('authorization'), isFalse);
    });
  });

  group('401 → 갱신 → 1회 재시도', () {
    test('원 요청이 정확히 2번 관측되고 두 번째는 새 액세스 토큰을 쓴다', () async {
      var protectedHits = 0;
      var refreshHits = 0;
      final seenAuth = <String?>[];
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-1');

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            refreshHits++;
            expect(
              jsonDecode(req.body),
              {'refreshToken': 'RT-1'},
              reason: '갱신 요청은 저장된 RT 를 그대로 실어야 한다',
            );
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          seenAuth.add(req.headers['authorization']);
          return protectedHits == 1
              ? http.Response('', 401)
              : http.Response('{"ok":true}', 200);
        }),
        baseUrl: _base,
        store: store,
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 200);
      expect(protectedHits, 2);
      expect(refreshHits, 1);
      expect(seenAuth, ['Bearer AT-1', 'Bearer AT-2']);
    });

    test('회전된 새 refresh 토큰을 교체 저장한다', () async {
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-1');
      var protectedHits = 0;

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          return protectedHits == 1
              ? http.Response('', 401)
              : http.Response('{}', 200);
        }),
        baseUrl: _base,
        store: store,
      );

      await client.getJson(Uri.parse('$_base/api/me'));

      expect(store.access, 'AT-2');
      expect(store.refresh, 'RT-2');
    });

    test('401 이 아닌 응답은 갱신도 재시도도 하지 않는다', () async {
      var protectedHits = 0;
      var refreshHits = 0;

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            refreshHits++;
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1', refresh: 'RT-1'),
      );

      final res = await client.getJson(Uri.parse('$_base/api/none'));

      expect(res.statusCode, 404);
      expect(protectedHits, 1);
      expect(refreshHits, 0);
    });
  });

  group('single-flight', () {
    test('동시 401 다섯 개가 갱신 요청 하나로 합쳐지고 모두 성공한다', () async {
      var refreshHits = 0;
      var protectedHits = 0;
      final gate = Completer<void>();

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            refreshHits++;
            // 갱신 응답을 붙잡아 둔다 — 그동안 나머지 401 이 전부 도착한다.
            await gate.future;
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          return req.headers['authorization'] == 'Bearer AT-1'
              ? http.Response('', 401)
              : http.Response('{"ok":true}', 200);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1', refresh: 'RT-1'),
      );

      final inFlight = List.generate(
        5,
        (i) => client.getJson(Uri.parse('$_base/api/resource/$i')),
      );

      // 다섯 요청이 모두 401 을 받고 갱신 지점까지 도달할 시간을 준다.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete();

      final results = await Future.wait(inFlight);

      expect(
        refreshHits,
        1,
        reason: '같은 RT 로 두 번 보내면 서버가 재사용으로 보고 전 기기를 끊는다',
      );
      expect(results.map((r) => r.statusCode).toList(), [200, 200, 200, 200, 200]);
      expect(protectedHits, 10, reason: '5개 × (최초 401 + 재시도)');
    });
  });

  group('실패 경로', () {
    test('갱신 자체가 401 이면 재시도하지 않고 저장된 토큰을 지운다', () async {
      var protectedHits = 0;
      var refreshHits = 0;
      var expiredHookCalls = 0;
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-EXPIRED');

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            refreshHits++;
            return http.Response('', 401);
          }
          protectedHits++;
          return http.Response('', 401);
        }),
        baseUrl: _base,
        store: store,
        onSessionExpired: () async => expiredHookCalls++,
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 401);
      expect(protectedHits, 1, reason: '갱신이 실패하면 원 요청을 재시도하지 않는다');
      expect(refreshHits, 1, reason: '실패한 RT 로 다시 두드리면 재사용 판정이 난다');
      expect(store.access, isNull);
      expect(store.refresh, isNull);
      expect(store.clearCount, 1);
      expect(expiredHookCalls, 1);
    });

    test('갱신이 429 를 받으면 토큰을 지우지 않는다 — 일시적 혼잡은 로그아웃이 아니다', () async {
      // #14 가 POST /auth/token/refresh 에 rate limit 을 새로 걸면서 이 응답이 처음으로
      // 나올 수 있게 됐다. 인증 버킷은 소셜 코드 교환과 **공유**하므로, 공용 NAT 뒤에서
      // 로그인이 몰리면 아무 잘못 없는 사용자의 갱신이 429 를 받는다.
      //
      // 예전 코드는 200 이 아닌 모든 응답을 "세션 종료" 로 읽었다. 그 상태에서는 429 한
      // 번에 store.clear() 가 불리고 멀쩡한 refresh 토큰이 사라졌다(실측: clearCount=1,
      // sessionExpiredCalls=1). _performRefresh 의 401 분기를 다시 `!= 200` 으로 되돌리면
      // 이 테스트가 빨간불이다.
      var expiredHookCalls = 0;
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-STILL-VALID');

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'RATE_LIMITED',
                  'message': '요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.',
                  'traceId': 'trace-1',
                },
              }),
              429,
              headers: const {'retry-after': '60'},
            );
          }
          return http.Response('', 401);
        }),
        baseUrl: _base,
        store: store,
        onSessionExpired: () async => expiredHookCalls++,
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 401, reason: '호출부에는 여전히 401 이 간다 — 이번 요청은 실패다');
      expect(
        store.clearCount,
        0,
        reason: '"잠시 후 다시" 를 재로그인 강제로 번역하면 안 된다',
      );
      expect(store.refresh, 'RT-STILL-VALID', reason: '아직 유효한 RT 를 버리지 않는다');
      expect(store.access, 'AT-1');
      expect(expiredHookCalls, 0, reason: '세션 만료 훅이 돌면 화면이 로그인으로 튄다');
    });

    test('갱신이 응답하지 않으면 타임아웃으로 끊고 토큰은 지킨다 — 영원히 걸리지 않는다', () async {
      // 이게 없으면 응답을 주지 않는 서버에서 갱신 future 가 영원히 걸린다. 단일 비행이라
      // 그 하나가 걸리면 뒤따르는 모든 401 재시도가 같은 future 를 기다리며 함께 멈추고,
      // 앱은 로딩만 돌면서 사용자에게 아무 문구도 띄우지 않는다.
      //
      // `.timeout(refreshTimeout)` 을 지우면 이 테스트가 **끝나지 않는다**(빨간불이 아니라
      // 행). 그래서 여기서는 테스트 자체에 상한을 걸어 그 상태를 실패로 만든다.
      var expiredHookCalls = 0;
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-STILL-VALID');

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            // 실제 타임아웃(15초)보다 길게 붙잡아 둔다.
            await Future<void>.delayed(const Duration(seconds: 30));
            return http.Response('', 200);
          }
          return http.Response('', 401);
        }),
        baseUrl: _base,
        store: store,
        onSessionExpired: () async => expiredHookCalls++,
      );

      final res = await client
          .getJson(Uri.parse('$_base/api/bookmarks'))
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw StateError(
              '갱신이 refreshTimeout 안에 끊기지 않았다 — .timeout() 이 빠졌다',
            ),
          );

      expect(res.statusCode, 401, reason: '이번 요청은 실패다');
      expect(store.clearCount, 0, reason: '응답이 없는 것은 "이 RT 가 죽었다" 는 확답이 아니다');
      expect(store.refresh, 'RT-STILL-VALID');
      expect(expiredHookCalls, 0);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('갱신이 5xx 나 네트워크 오류로 실패해도 토큰을 지키고 401 만 돌려준다', () async {
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-1');

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) throw http.ClientException('연결 실패');
          return http.Response('', 401);
        }),
        baseUrl: _base,
        store: store,
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 401);
      expect(
        store.clearCount,
        0,
        reason: '비행기 모드에서 앱을 열었다는 이유로 로그인 상태를 버리면 안 된다',
      );
      expect(store.refresh, 'RT-1');
    });

    test('저장된 refresh 토큰이 없으면 갱신 요청을 아예 보내지 않는다', () async {
      var protectedHits = 0;
      var refreshHits = 0;

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            refreshHits++;
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          return http.Response('', 401);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1'),
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 401);
      expect(refreshHits, 0);
      expect(protectedHits, 1);
    });

    test('재시도한 요청이 또 401 이면 세 번째 요청을 보내지 않고 로그아웃한다', () async {
      var protectedHits = 0;
      var refreshHits = 0;
      final store = _FakeTokenStore(access: 'AT-1', refresh: 'RT-1');

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            refreshHits++;
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          // 새 토큰으로도 계속 401 — 무한 루프를 유도하는 서버.
          return http.Response('', 401);
        }),
        baseUrl: _base,
        store: store,
      );

      final res = await client.getJson(Uri.parse('$_base/api/bookmarks'));

      expect(res.statusCode, 401);
      expect(protectedHits, 2, reason: '재시도는 1회로 제한된다');
      expect(refreshHits, 1);
      expect(store.access, isNull);
      expect(store.clearCount, 1);
    });
  });

  group('multipart', () {
    test('재시도할 때 새 request 를 조립한다 — 원 request 재사용은 StateError 다', () async {
      var protectedHits = 0;
      final bodies = <String>[];

      final client = AuthedClient(
        inner: MockClient((req) async {
          if (_isRefresh(req)) {
            return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
          }
          protectedHits++;
          bodies.add(String.fromCharCodes(req.bodyBytes));
          return protectedHits == 1
              ? http.Response('', 401)
              : http.Response('[{"id":1,"key":"k","url":"u"}]', 200);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1', refresh: 'RT-1'),
      );

      final request = http.MultipartRequest('POST', Uri.parse('$_base/media'))
        ..fields['category'] = 'PROFILE_IMAGE'
        ..files.add(
          http.MultipartFile.fromBytes(
            'files',
            utf8.encode('PNGDATA'),
            filename: 'avatar.png',
          ),
        );

      final streamed = await client.send(request);
      final res = await http.Response.fromStream(streamed);

      expect(res.statusCode, 200);
      expect(protectedHits, 2);
      // 두 번의 전송 모두 파일 파트와 필드를 온전히 실었다.
      for (final body in bodies) {
        expect(body, contains('avatar.png'));
        expect(body, contains('PNGDATA'));
        expect(body, contains('PROFILE_IMAGE'));
      }
    });

    test('multipart 의 Content-Type 은 boundary 를 유지한다 — JSON 기본값이 덮지 않는다', () async {
      final seen = <http.Request>[];
      final client = AuthedClient(
        inner: MockClient((req) async {
          seen.add(req);
          return http.Response('[]', 200);
        }),
        baseUrl: _base,
        store: _FakeTokenStore(access: 'AT-1'),
      );

      final request = http.MultipartRequest('POST', Uri.parse('$_base/media'))
        ..files.add(http.MultipartFile.fromBytes('files', [1, 2, 3]));

      await client.send(request);

      expect(seen.single.headers['content-type'], startsWith('multipart/form-data'));
      expect(seen.single.headers['content-type'], contains('boundary='));
      expect(seen.single.headers['authorization'], 'Bearer AT-1');
    });
  });

  group('로그 위생', () {
    test('LoggingClient 를 겹쳐도 Authorization 값이 로그에 남지 않는다', () async {
      final lines = <String>[];
      final originalDebugPrint = debugPrint;

      try {
        // debugPrint → print 로 흐르게 해 Zone 이 잡을 수 있게 한다.
        debugPrint = debugPrintSynchronously;

        await runZoned(
          () async {
            final client = AuthedClient(
              inner: LoggingClient(
                MockClient((req) async {
                  if (_isRefresh(req)) {
                    return http.Response(_tokensJson('AT-2', 'RT-2'), 200);
                  }
                  return req.headers['authorization'] == 'Bearer AT-1'
                      ? http.Response('', 401)
                      : http.Response('{"ok":true}', 200);
                }),
              ),
              baseUrl: _base,
              store: _FakeTokenStore(access: 'AT-1', refresh: 'RT-1'),
            );
            await client.getJson(Uri.parse('$_base/api/bookmarks'));
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line),
          ),
        );
      } finally {
        debugPrint = originalDebugPrint;
      }

      final log = lines.join('\n');
      expect(log, isNot(contains('AT-1')), reason: '액세스 토큰이 로그에 남으면 안 된다');
      expect(log, isNot(contains('AT-2')));
      expect(log, isNot(contains('RT-1')), reason: 'refresh 토큰도 마찬가지다');
      expect(log, isNot(contains('RT-2')));
      expect(
        log,
        contains('REDACTED'),
        reason: '헤더 줄 자체는 남되 값만 가려져야 한다',
      );
    });
  });
}
