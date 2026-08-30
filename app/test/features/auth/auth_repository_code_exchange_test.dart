// 1회용 코드 → 토큰 교환. (이슈 #14)
//
// `POST /auth/oauth/{provider}/callback` 은 소셜 로그인에서 토큰이 앱에 도달하는
// 유일한 통로다. 딥링크에는 코드와 state 만 실린다.
//
// 실제 네트워크를 타지 않는다 — `MockClient` 로 응답을 손으로 만든다(정책 #21).
// 교환 메서드가 `http.Client` 를 주입받기 때문에 가능한 테스트다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';

const _base = 'https://api.example.test';

/// `http.Response` 는 content-type 이 없으면 본문을 latin1 로 인코딩한다 —
/// 한글이 섞인 계약 오류 메시지가 그 자리에서 FormatException 을 던진다.
const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

AuthRepositoryImpl _repo(MockClient client) =>
    AuthRepositoryImpl(baseUrl: _base, plainClient: client);

void main() {
  group('exchangeOAuthCode — POST /auth/oauth/{provider}/callback', () {
    test('200 이면 AuthTokens 를 읽는다 — expiresIn·isNew·user 까지', () async {
      // 이 셋은 예전 딥링크(`?token=&refresh=`)로는 표현할 방법이 없었다.
      // 소셜 신규 가입자의 온보딩 분기가 여기서 살아난다.
      late http.Request seen;
      final repo = _repo(
        MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'accessToken': 'AT-1',
              'refreshToken': 'RT-1',
              'expiresIn': 3600,
              'isNew': true,
              'user': {'id': 7},
            }),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      final tokens = await repo.exchangeOAuthCode(
        provider: 'kakao',
        code: 'CODE-1',
        state: 'ST-1',
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/auth/oauth/kakao/callback');
      expect(tokens, isNotNull);
      expect(tokens!.accessToken, 'AT-1');
      expect(tokens.refreshToken, 'RT-1');
      expect(tokens.expiresIn, 3600);
      expect(tokens.isNew, isTrue);
      expect(tokens.user, {'id': 7});
    });

    test('요청 바디에 code 와 state 가 담긴다', () async {
      late http.Request seen;
      final repo = _repo(
        MockClient((req) async {
          seen = req;
          return http.Response('{"accessToken":"AT","expiresIn":1}', 200,
              headers: _jsonHeaders);
        }),
      );

      await repo.exchangeOAuthCode(
        provider: 'google',
        code: 'CODE-1',
        state: 'ST-1',
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['code'], 'CODE-1');
      expect(
        body['state'],
        'ST-1',
        reason: '서버가 코드 발급 시점의 state 와 대조한다 — 빠뜨리면 401 이다',
      );
      expect(seen.headers['Content-Type'], contains('application/json'));
    });

    test('provider 가 경로에 들어간다 — 코드는 그것을 만든 공급자로만 교환된다', () async {
      final seen = <String>[];
      final repo = _repo(
        MockClient((req) async {
          seen.add(req.url.path);
          return http.Response('{"accessToken":"AT","expiresIn":1}', 200,
              headers: _jsonHeaders);
        }),
      );

      await repo.exchangeOAuthCode(provider: 'kakao', code: 'c', state: 's');
      await repo.exchangeOAuthCode(provider: 'google', code: 'c', state: 's');

      expect(seen, ['/auth/oauth/kakao/callback', '/auth/oauth/google/callback']);
    });

    test('401 이면 null 이다 — 재사용·만료·state 불일치가 전부 여기로 온다', () async {
      final repo = _repo(MockClient((_) async => http.Response('', 401)));

      expect(
        await repo.exchangeOAuthCode(provider: 'kakao', code: 'c', state: 's'),
        isNull,
      );
    });

    test('429 도 null 이다 — 한도에 걸린 것을 성공으로 읽지 않는다', () async {
      final repo = _repo(
        MockClient((_) async => http.Response(
              jsonEncode({
                'error': {'code': 'RATE_LIMITED', 'message': '요청이 너무 잦습니다.'}
              }),
              429,
              headers: _jsonHeaders,
            )),
      );

      expect(
        await repo.exchangeOAuthCode(provider: 'kakao', code: 'c', state: 's'),
        isNull,
      );
    });

    test('200 인데 본문이 계약과 다르면 null 이다', () async {
      // 예전 서버가 JWT 원문을 돌려주던 시절의 함정과 같은 형태다 — 본문 통째로를
      // 토큰 자리에 저장하면 이후 모든 요청이 401 이 된다.
      final repo = _repo(
        MockClient((_) async => http.Response('not json at all', 200)),
      );

      expect(
        await repo.exchangeOAuthCode(provider: 'kakao', code: 'c', state: 's'),
        isNull,
      );
    });

    test('네트워크 예외는 삼키지 않고 올려보낸다 — 호출부가 취소·네트워크·서버를 구분해야 한다', () async {
      final repo = _repo(
        MockClient((_) async => throw http.ClientException('no route')),
      );

      expect(
        () => repo.exchangeOAuthCode(provider: 'kakao', code: 'c', state: 's'),
        throwsA(isA<http.ClientException>()),
      );
    });
  });
}
