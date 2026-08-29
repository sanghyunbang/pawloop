import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/core/net/log_redaction.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/login_request.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/register_request.dart';
import 'package:heat_trip_flutter/features/profile/data/dto/update_profile_request.dart';

/// 회원가입 결과. 화면이 사용자에게 무엇을 말해야 하는지 결정한다.
///
/// bool 이 아닌 이유: 계약이 **409(이미 가입된 이메일)** 를 400(입력 오류)과
/// 분리했다(#10). 예전에는 둘 다 400 이라 앱이 구분할 수 없었고, 그래서
/// "회원가입 실패. 다시 시도해주세요." 하나로 뭉뚱그렸다 — 이미 계정이 있는
/// 사용자에게 그 문구는 아무 도움이 안 된다.
enum RegisterOutcome {
  /// 201 Created.
  created,

  /// 409 Conflict — 같은 이메일이 이미 있다.
  duplicateEmail,

  /// 400 — 입력 검증 실패.
  invalidInput,

  /// 그 밖의 실패(네트워크·5xx 등).
  failed,
}

/// 실제 HTTP 요청을 통해 백엔드와 통신하는 클래스.
///
/// - 비인증 경로(`/auth/signup`·`/auth/login`)는 평범한 `http` 를 쓴다.
///   토큰이 없는 상태의 요청이라 `AuthedClient` 를 태울 이유가 없다.
/// - 인증 경로(`/auth/me`)는 [AuthedClient] 를 탄다 — 헤더 부착도, 401 갱신도
///   그쪽이 한다. 이 파일은 더 이상 `Authorization` 을 만들지 않는다(#11).
class AuthRepositoryImpl {
  // --dart-define 으로 주입된 API_BASE / API_BASE_URL 을 불러옴 (Env)
  final String baseUrl;

  /// 비인증 요청용. 테스트에서 `MockClient` 를 꽂을 수 있게 주입받는다.
  final http.Client _plain;

  /// 인증 요청용.
  final AuthedClient _authed;

  AuthRepositoryImpl({String? baseUrl, http.Client? plainClient, AuthedClient? authedClient})
    : baseUrl = baseUrl ?? Env.apiBase ?? '',
      _plain = plainClient ?? http.Client(),
      _authed = authedClient ?? AuthedClient.instance;

  /// 로그인 요청 — `POST /auth/login`.
  ///
  /// 성공하면 계약의 `AuthTokens`, 실패하면 null.
  ///
  /// > ⚠️ **2026-08 이전에는 응답 본문이 JWT 원문 문자열이었다.** 그때 코드는
  /// > `response.body` 를 그대로 토큰으로 돌려줬고, #10 이 응답을 JSON 으로 바꾼
  /// > 뒤로는 **JSON 통째로가 토큰 자리에 저장되어 모든 요청이 401** 이 됐다.
  /// > 그래서 본문 해석을 [AuthTokens.tryParse] 로 옮겼다.
  ///
  /// 자격증명 실패는 **본문 없는 401** 이다(예전에는 500). 가입되지 않은 이메일과
  /// 비밀번호 오류를 구분하지 않는다 — 구분해 주면 그 자체가 가입 여부 조회 수단이 된다.
  Future<AuthTokens?> login(LoginRequest request) async {
    final url = Uri.parse('$baseUrl/auth/login');

    try {
      final response = await _plain.post(
        url,
        headers: const {'Content-Type': AuthedClient.jsonContentType},
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final tokens = AuthTokens.tryParse(response.body);
        if (tokens == null && kDebugMode) {
          // 본문은 절대 그대로 찍지 않는다 — 성공 본문에는 토큰이 들어 있다.
          debugPrint('[X] 로그인 응답이 계약(AuthTokens)과 다르다');
        }
        return tokens;
      }

      if (kDebugMode) {
        debugPrint('[X] 로그인 실패 : ${response.statusCode}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[X] 로그인 요청 오류: ${e.runtimeType}');
      return null;
    }
  }

  /// 회원 가입 요청 — `POST /auth/signup`.
  ///
  /// > ⚠️ 성공은 **201 + `User`** 다(#10). 예전에는 `200` + 평문 `"회원가입 성공"`
  /// > 이었다. 중복 이메일은 **409**(예전에는 400).
  ///
  /// **이 응답에는 토큰이 없다.** 가입 직후 로그인 상태로 만들려면 [login] 을
  /// 한 번 더 호출해야 한다 — 계약이 그렇게 나눠져 있다.
  Future<RegisterOutcome> register(RegisterRequest request) async {
    final url = Uri.parse('$baseUrl/auth/signup');

    try {
      final response = await _plain.post(
        url,
        headers: const {'Content-Type': AuthedClient.jsonContentType},
        body: jsonEncode(request.toJson()),
      );

      switch (response.statusCode) {
        case 201:
          return RegisterOutcome.created;
        case 409:
          return RegisterOutcome.duplicateEmail;
        case 400:
          if (kDebugMode) {
            debugPrint('[X] 회원가입 검증 실패: ${redactBody(response.body)}');
          }
          return RegisterOutcome.invalidInput;
        default:
          if (kDebugMode) {
            debugPrint('[X] 회원가입 실패 : ${response.statusCode}');
          }
          return RegisterOutcome.failed;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[X] 회원가입 요청 오류: ${e.runtimeType}');
      return RegisterOutcome.failed;
    }
  }

  /// 사용자 정보 조회 — `GET /auth/me`.
  ///
  /// 토큰 인자를 받지 않는다. 헤더 부착은 [AuthedClient] 의 일이고, 액세스 토큰이
  /// 만료돼 있으면 그쪽이 갱신 후 한 번 재시도한다.
  Future<Map<String, dynamic>?> getMyProfile() async {
    final url = Uri.parse('$baseUrl/auth/me');

    try {
      final response = await _authed.getJson(url);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (kDebugMode) {
        debugPrint('[X] 유저 정보 불러오기 실패: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[X] 유저 정보 요청 중 에러: ${e.runtimeType}');
      return null;
    }
  }

  /// 사용자 정보 수정 — `PUT /auth/me`.
  Future<bool> updateMyProfile(UpdateProfileRequest req) async {
    final url = Uri.parse('$baseUrl/auth/me');
    try {
      final response = await _authed.putJson(url, body: req.toJson());
      if (response.statusCode == 200) return true;
      if (kDebugMode) {
        debugPrint('[X] 프로필 업데이트 실패: ${response.statusCode}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[X] 프로필 업데이트 오류: ${e.runtimeType}');
      return false;
    }
  }

  /// 계정 삭제 — `DELETE /auth/me`. 계약상 204.
  Future<bool> deleteMyAccount() async {
    final url = Uri.parse('$baseUrl/auth/me');
    try {
      final res = await _authed.deleteJson(url);
      if (res.statusCode == 200 || res.statusCode == 204) return true;
      if (kDebugMode) {
        debugPrint('[X] deleteMyAccount 실패: ${res.statusCode}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[X] deleteMyAccount 에러: ${e.runtimeType}');
      return false;
    }
  }
}
