// 로그인/갱신 응답 본문 해석 테스트 (이슈 #10 계약 · #11 적용).
//
// 순수 함수라 네트워크도 플랫폼 채널도 타지 않는다 — 정책 #21.
//
// 이 테스트가 잠그는 것: **평문 JWT 를 그대로 토큰으로 쓰던 옛 동작으로 돌아가지 않는 것.**
// 2026-08 이전 `POST /auth/login` 은 본문 전체가 JWT 였고, #10 이 JSON 으로 바꾼 뒤에도
// 앱이 본문을 그대로 저장하는 바람에 JSON 통째로가 토큰 자리에 들어가 모든 요청이 401 이었다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';

void main() {
  group('AuthTokens.tryParse', () {
    test('계약의 로그인 응답에서 네 필드를 모두 읽는다', () {
      final body = jsonEncode({
        'accessToken': 'eyJhbGciOiJIUzI1NiJ9.payload.sig',
        'refreshToken': 'r' * 43,
        'expiresIn': 3600,
        'isNew': false,
        'user': {'id': 7, 'nickname': '보리아빠'},
      });

      final tokens = AuthTokens.tryParse(body)!;

      expect(tokens.accessToken, 'eyJhbGciOiJIUzI1NiJ9.payload.sig');
      expect(tokens.refreshToken, 'r' * 43);
      expect(tokens.expiresIn, 3600);
      expect(tokens.isNew, isFalse);
      expect(tokens.user?['id'], 7);
    });

    test('갱신 응답처럼 isNew·user 가 빠져 있어도 읽는다', () {
      final body = jsonEncode({
        'accessToken': 'AT',
        'refreshToken': 'RT',
        'expiresIn': 3600,
      });

      final tokens = AuthTokens.tryParse(body)!;

      expect(tokens.accessToken, 'AT');
      expect(tokens.isNew, isFalse);
      expect(tokens.user, isNull);
    });

    test('옛 서버의 평문 JWT 본문은 토큰으로 받아들이지 않는다', () {
      // 이 한 줄이 이슈 #11 의 1순위였다. null 이 아니면 JWT 자리에
      // JSON 이나 쓰레기 문자열이 저장된다.
      expect(AuthTokens.tryParse('eyJhbGciOiJIUzI1NiJ9.payload.sig'), isNull);
    });

    test('accessToken 이 없거나 공백뿐이면 null 이다', () {
      expect(AuthTokens.tryParse(jsonEncode({'expiresIn': 3600})), isNull);
      expect(
        AuthTokens.tryParse(jsonEncode({'accessToken': '   ', 'expiresIn': 1})),
        isNull,
      );
      expect(
        AuthTokens.tryParse(jsonEncode({'accessToken': 12345})),
        isNull,
      );
    });

    test('본문이 깨진 JSON 이거나 배열이어도 예외를 던지지 않는다', () {
      expect(AuthTokens.tryParse('{not json'), isNull);
      expect(AuthTokens.tryParse('[]'), isNull);
      expect(AuthTokens.tryParse(''), isNull);
    });

    test('빈 refreshToken 은 없는 것으로 본다', () {
      // 빈 문자열을 저장해 두면 갱신이 "토큰 있음" 으로 판단해 400 을 받으러 나간다.
      final tokens = AuthTokens.tryParse(
        jsonEncode({'accessToken': 'AT', 'refreshToken': '', 'expiresIn': 60}),
      )!;

      expect(tokens.refreshToken, isNull);
    });

    test('expiresIn 이 없어도 로그인을 실패시키지 않는다', () {
      final tokens = AuthTokens.tryParse(jsonEncode({'accessToken': 'AT'}))!;

      expect(tokens.accessToken, 'AT');
      expect(tokens.expiresIn, 0);
    });
  });
}
