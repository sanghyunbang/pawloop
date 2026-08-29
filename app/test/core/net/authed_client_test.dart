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
