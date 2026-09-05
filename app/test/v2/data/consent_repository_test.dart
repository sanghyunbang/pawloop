// `ConsentRepository` — 계약대로 보내고 받는가. 이슈 #190.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/consent_repository.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';
  @override
  Future<String?> readRefreshToken() async => 'RT-1';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

ConsentRepository _repo(Future<http.Response> Function(http.Request) handler) =>
    ConsentRepository(
      baseUrl: _base,
      client: AuthedClient(inner: MockClient(handler), baseUrl: _base, store: _FakeTokenStore()),
    );

void main() {
  test('PUT /api/consents 에 계약 모양으로 보낸다 — kind 는 대문자, version 은 vX.Y', () async {
    http.Request? sent;
    final repo = _repo((req) async {
      sent = req;
      return _json({
        'consents': [
          {'kind': 'TERMS', 'version': 'v1.2', 'agreed': true, 'at': '2026-09-05T03:00:00Z'},
        ]
      });
    });

    final out = await repo.record(const [
      ConsentEntry(kind: ConsentKind.terms, version: 'v1.2', agreed: true),
      ConsentEntry(kind: ConsentKind.marketing, version: 'v1.0', agreed: false),
    ]);

    expect(sent!.method, 'PUT');
    expect(sent!.url.path, '/api/consents');
    expect(sent!.url.queryParameters, isEmpty, reason: '좌표는 물론 아무것도 쿼리에 안 싣는다');
    final body = jsonDecode(sent!.body) as Map<String, dynamic>;
    expect(body['consents'], [
      {'kind': 'TERMS', 'version': 'v1.2', 'agreed': true},
      {'kind': 'MARKETING', 'version': 'v1.0', 'agreed': false},
    ]);
    expect(out.single.kind, ConsentKind.terms);
    expect(out.single.at.isUtc, isTrue);
  });

  test('GET /api/consents 의 응답을 읽는다 — 모르는 kind 는 버린다', () async {
    final repo = _repo((req) async {
      expect(req.method, 'GET');
      return _json({
        'consents': [
          {'kind': 'PRIVACY', 'version': 'v1.3', 'agreed': true, 'at': '2026-09-05T03:00:00Z'},
          {'kind': 'NEWSLETTER', 'version': 'v9.9', 'agreed': true, 'at': '2026-09-05T03:00:00Z'},
        ]
      });
    });

    final out = await repo.fetch();

    expect(out.map((c) => c.kind), [ConsentKind.privacy]);
  });

  test('200 이 아니면 ConsentFailure 다 — 화면이 "다시 시도" 로 간다', () async {
    final repo = _repo((_) async => _json({'message': 'no'}, status: 500));

    expect(() => repo.fetch(), throwsA(isA<ConsentFailure>()));
  });

  test('네트워크가 끊겨도 ConsentFailure 다 — 던지는 타입이 하나여야 화면이 다룰 수 있다', () async {
    final repo = _repo((_) async => throw Exception('끊김'));

    expect(() => repo.record(const []), throwsA(isA<ConsentFailure>()));
  });
}
