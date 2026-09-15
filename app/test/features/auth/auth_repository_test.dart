// AuthRepositoryImpl — #10 이 바꾼 로그인·가입 계약을 앱이 제대로 읽는지 (이슈 #11 1순위).
//
// 실제 네트워크를 타지 않는다 — `MockClient` 로 응답을 손으로 만든다(정책 #21).
// baseUrl 과 클라이언트를 주입받는 생성자가 있어서 가능한 테스트다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/login_request.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/register_request.dart';

const _base = 'https://api.example.test';

/// `http.Response` 는 content-type 이 없으면 본문을 latin1 로 인코딩한다 —
/// 한글이 섞인 계약 오류 메시지가 그 자리에서 FormatException 을 던진다.
const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

AuthRepositoryImpl _repo(MockClient client) =>
    AuthRepositoryImpl(baseUrl: _base, plainClient: client);

/// 토큰이 없는 저장소. `GET /auth/me` 는 헤더 없이도 나가고, 여기서 재는 것은 상한이다.
class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  group('fetchMe — GET /auth/me 의 상한 (#514)', () {
    test('응답을 안 주는 서버는 상한에 걸려 networkError 다 — 콜드 스타트가 스플래시에 멈추면 안 된다', () async {
      // 연결은 되고 응답만 안 오는 서버. 끊긴 연결 · 죽은 프로세스 · 중간 장비가 이렇다.
      final dead = MockClient((_) => Completer<http.Response>().future);
      final repo = AuthRepositoryImpl(
        baseUrl: _base,
        authedClient: AuthedClient(inner: dead, baseUrl: _base, store: _NoTokens()),
        requestTimeout: const Duration(milliseconds: 30),
      );

      final result = await repo.fetchMe();

      expect(result.outcome, MeOutcome.networkError,
          reason: '이 분기는 토큰을 안 지운다 — 비행기 모드로 켠 사람을 쫓아내지 않는다');
    });

    test('상한이 실제로 걸려 있다 — 갱신 왕복보다 짧고, 사람이 기다릴 만한 길이다', () {
      expect(AuthRepositoryImpl.timeout, lessThanOrEqualTo(AuthedClient.refreshTimeout),
          reason: '갱신(15초)보다 길면 이 상한은 아무것도 안 막는다');
      expect(AuthRepositoryImpl.timeout, greaterThanOrEqualTo(const Duration(seconds: 5)),
          reason: '너무 짧으면 느린 모바일 네트워크에서 멀쩡한 세션이 매번 끊긴 것처럼 보인다');
    });
  });

  group('login — POST /auth/login', () {
    test('AuthTokens JSON 에서 accessToken 과 refreshToken 을 읽는다', () async {
      late http.Request seen;
      final repo = _repo(
        MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'accessToken': 'AT-1',
              'refreshToken': 'RT-1',
              'expiresIn': 3600,
              'isNew': false,
              'user': {'id': 7},
            }),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      final tokens = await repo.login(
        LoginRequest(email: 'a@b.c', password: 'pw12345678'),
      );

      expect(seen.url.path, '/auth/login');
      expect(tokens, isNotNull);
      expect(tokens!.accessToken, 'AT-1');
      expect(tokens.refreshToken, 'RT-1');
      expect(tokens.isNew, isFalse);
    });

    test('응답 본문 전체를 토큰으로 쓰지 않는다 — 그러면 모든 요청이 401 이 된다', () async {
      // #10 이전 코드는 `response.body` 를 그대로 돌려줬다. 응답이 JSON 으로 바뀐
      // 지금 그렇게 하면 `{"accessToken":...}` 통째로가 Bearer 뒤에 붙는다.
      const body =
          '{"accessToken":"AT-1","refreshToken":"RT-1","expiresIn":3600}';
      final repo = _repo(MockClient((_) async => http.Response(body, 200)));

      final tokens = await repo.login(
        LoginRequest(email: 'a@b.c', password: 'pw12345678'),
      );

      expect(tokens!.accessToken, 'AT-1');
      expect(tokens.accessToken, isNot(contains('{')));
      expect(tokens.accessToken, isNot(body));
    });

    test('자격증명 실패는 본문 없는 401 이고 null 을 돌려준다', () async {
      final repo = _repo(MockClient((_) async => http.Response('', 401)));

      expect(
        await repo.login(LoginRequest(email: 'a@b.c', password: 'nope1234')),
        isNull,
      );
    });

    test('200 인데 본문이 계약과 다르면 null 이다 — 쓰레기를 토큰으로 저장하지 않는다', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response('회원가입 성공', 200, headers: _jsonHeaders),
        ),
      );

      expect(
        await repo.login(LoginRequest(email: 'a@b.c', password: 'pw12345678')),
        isNull,
      );
    });
  });

  group('register — POST /auth/signup', () {
    RegisterRequest req() => RegisterRequest(
      email: 'a@b.c',
      password: 'pw12345678',
      nickname: '보리아빠',
      name: '방상현',
      gender: 'male',
      ageGroup: 'over14',
    );

    test('성공은 201 이다 — 200 만 성공으로 보던 옛 코드는 여기서 걸린다', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(jsonEncode({'id': 7}), 201),
        ),
      );

      expect(await repo.register(req()), RegisterOutcome.created);
    });

    test('중복 이메일 409 를 입력 오류와 구분한다', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'CONFLICT', 'message': '이미 가입된 이메일입니다.'},
            }),
            409,
            headers: _jsonHeaders,
          ),
        ),
      );

      expect(await repo.register(req()), RegisterOutcome.duplicateEmail);
    });

    test('400 은 입력 검증 실패다', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'VALIDATION', 'message': '입력을 확인하세요.'},
            }),
            400,
            headers: _jsonHeaders,
          ),
        ),
      );

      expect(await repo.register(req()), RegisterOutcome.invalidInput);
    });

    test('그 밖의 실패는 failed 다', () async {
      final repo = _repo(MockClient((_) async => http.Response('', 500)));

      expect(await repo.register(req()), RegisterOutcome.failed);
    });
  });
}
