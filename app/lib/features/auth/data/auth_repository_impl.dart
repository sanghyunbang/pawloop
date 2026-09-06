import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/core/net/log_redaction.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/login_request.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/register_request.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/update_profile_request.dart';

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

/// `GET /auth/me` 의 결과. **null 하나로 뭉개지 않는 이유**가 있다(#12).
///
/// 앱 시작 시 저장된 토큰을 검증할 때, "서버가 이 토큰을 거부했다"(401)와
/// "비행기 모드라 물어보지도 못했다"(네트워크 오류)는 정반대의 처방을 받아야 한다.
/// 전자는 재로그인이고 후자는 그냥 기다리는 것이다. 둘 다 null 로 돌려주면
/// 호출부는 구분할 방법이 없고, 지하철에서 앱을 켠 사용자가 로그아웃된다.
enum MeOutcome {
  /// 200 + 계약의 `User`.
  ok,

  /// 401. `AuthedClient` 가 갱신까지 시도한 뒤의 결과이므로 **세션이 끝난 것**이다.
  unauthorized,

  /// 요청이 서버에 닿지 못했거나 5xx. 토큰의 유효성에 대해 아무것도 알려주지 않는다.
  networkError,
}

/// [MeOutcome] 과 (성공 시) 본문.
class MeResult {
  final MeOutcome outcome;

  /// [MeOutcome.ok] 일 때만 non-null.
  final Map<String, dynamic>? user;

  const MeResult(this.outcome, [this.user]);
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
    : baseUrl = baseUrl ?? Env.apiBase,
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

  /// 1회용 코드 → 토큰 교환 — `POST /auth/oauth/{provider}/callback`. (이슈 #14)
  ///
  /// **소셜 로그인에서 토큰이 앱에 도달하는 유일한 통로다.** 딥링크에는 코드와
  /// `state` 만 실린다 — 예전에는 `?token=<AT>&refresh=<RT>` 로 URL 에 실려 왔고,
  /// 그 URL 은 302 의 `Location` 헤더와 브라우저 히스토리에 남았다.
  ///
  /// 비인증 경로다. 주체는 [code] 자체가 증명하므로 [AuthedClient] 를 태우지 않는다 —
  /// 이 시점에는 붙일 토큰이 아직 없다.
  ///
  /// 성공하면 계약의 `AuthTokens`, 실패하면 null. 코드 재사용·만료·`state` 불일치·
  /// 공급자 불일치가 전부 **본문 없는 401** 로 온다. 서버가 구분해 주지 않는 이유는
  /// 그 차이가 "그 코드가 존재하긴 했는가" 를 알려 주는 오라클이 되기 때문이다.
  ///
  /// **네트워크 예외는 삼키지 않는다.** 호출부([SocialLoginService])가 취소·네트워크·
  /// 서버 오류를 구분해 다른 문장을 보여줘야 하는데, 여기서 null 로 뭉개면 그 구분이
  /// 사라진다. 계약 위반(200 인데 본문이 다름)만 null 이다.
  Future<AuthTokens?> exchangeOAuthCode({
    required String provider,
    required String code,
    required String state,
  }) async {
    final url = Uri.parse('$baseUrl/auth/oauth/$provider/callback');

    final response = await _plain.post(
      url,
      headers: const {'Content-Type': AuthedClient.jsonContentType},
      body: jsonEncode({'code': code, 'state': state}),
    );

    if (response.statusCode == 200) {
      final tokens = AuthTokens.tryParse(response.body);
      if (tokens == null && kDebugMode) {
        // 본문은 절대 그대로 찍지 않는다 — 성공 본문에는 토큰이 들어 있다.
        debugPrint('[X] 코드 교환 응답이 계약(AuthTokens)과 다르다');
      }
      return tokens;
    }

    if (kDebugMode) {
      // 코드도 state 도 찍지 않는다. 상태 코드만 남긴다. (#61)
      debugPrint('[X] 소셜 코드 교환 실패: ${response.statusCode}');
    }
    return null;
  }

  /// 사용자 정보 조회 — `GET /auth/me`.
  ///
  /// 토큰 인자를 받지 않는다. 헤더 부착은 [AuthedClient] 의 일이고, 액세스 토큰이
  /// 만료돼 있으면 그쪽이 갱신 후 한 번 재시도한다.
  Future<Map<String, dynamic>?> getMyProfile() async =>
      (await fetchMe()).user;

  /// [getMyProfile] 과 같은 요청이지만 **실패의 종류를 구분해서** 돌려준다.
  ///
  /// 앱 시작 시 토큰 검증(`AuthState.init`)이 401 과 네트워크 오류를 다르게
  /// 처리해야 하기 때문이다 — [MeOutcome] 주석 참고.
  Future<MeResult> fetchMe() async {
    final url = Uri.parse('$baseUrl/auth/me');

    try {
      final response = await _authed.getJson(url);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return MeResult(MeOutcome.ok, decoded);
        }
        // 200 인데 객체가 아니다 — 계약 위반이다. 토큰 탓으로 돌리지 않는다.
        if (kDebugMode) debugPrint('[X] /auth/me 200 본문이 객체가 아니다');
        return const MeResult(MeOutcome.networkError);
      }

      if (response.statusCode == 401) {
        // AuthedClient 가 갱신 + 재시도까지 끝낸 뒤의 401 이다. 세션이 끝났다.
        return const MeResult(MeOutcome.unauthorized);
      }

      if (kDebugMode) {
        debugPrint('[X] 유저 정보 불러오기 실패: ${response.statusCode}');
      }
      return const MeResult(MeOutcome.networkError);
    } catch (e) {
      if (kDebugMode) debugPrint('[X] 유저 정보 요청 중 에러: ${e.runtimeType}');
      return const MeResult(MeOutcome.networkError);
    }
  }

  /// 로그아웃 — `POST /auth/logout`. 계약상 204이고 **전 기기** 폐기다(#9).
  ///
  /// 본문을 보내지 않는다 — 서버는 Authorization 헤더의 주체로 그 사용자의 살아 있는
  /// refresh 토큰을 **전부** 폐기한다. 멱등이라 이미 폐기된 상태여도 204 다.
  ///
  /// 성공 여부를 bool 로 돌려주지만 **호출부는 실패해도 로컬 토큰을 지워야 한다**
  /// (`AuthState.logout`). 예외는 그대로 올려보낸다 — 삼키면 호출부가 오프라인
  /// 로그아웃과 성공을 구분할 수 없다.
  Future<bool> logout() async {
    final url = Uri.parse('$baseUrl/auth/logout');
    // 본문이 없으므로 `postJson` 이 아니라 맨 POST 다 — 빈 본문에 JSON
    // Content-Type 을 붙이면 서버에 "읽을 것이 있다" 고 거짓말하는 셈이다.
    final res = await _authed.post(url);
    if (res.statusCode == 204 || res.statusCode == 200) return true;
    if (kDebugMode) debugPrint('[X] 로그아웃 실패: ${res.statusCode}');
    return false;
  }

  /// 닉네임의 최대 글자 수. 계약의 `maxLength` 이자 서버의 `@Size` 와 같은 수다(#229).
  ///
  /// **컬럼이 정한 수가 아니다.** 컬럼은 `varchar(255)` 인데 그건 저장 한계이고, 이 수는
  /// 이 화면이 먼저 쓰던 것을 서버가 정본으로 올린 것이다. 2026-09-03 이전에는 서버에
  /// 상한이 아예 없어서 이 화면의 20 이 **저장소 전체의 유일한 방어선**이었다 — 소셜
  /// 로그인은 이 화면을 아예 안 지나므로 그때도 방어가 아니었다.
  static const int maxNicknameLength = 20;

  /// 이름의 최대 글자 수. 닉네임이 비었을 때의 대체 표시값이라 같은 이유로 막는다.
  static const int maxNameLength = 50;

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
