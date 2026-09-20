// lib/v2/data/email_auth_service.dart
//
// 이메일 가입·로그인을 **한 곳**으로 모은다 — 이슈 #635 (ADR-0024).
//
// ## 왜 서비스가 필요한가
//
// 토큰을 받은 뒤에 해야 할 일이 셋이다. 하나라도 빠뜨리면 조용히 이상해진다.
//
//   1. **보안 저장소에** 저장한다 — 평문 SharedPreferences 가 아니다(#8)
//   2. **refresh 토큰도 함께** 저장한다 — 예전에 AT 만 저장해서 한 시간 뒤 조용히
//      로그아웃됐다(#9·#11)
//   3. `GET /auth/me` 로 **상태를 확정**한다 — 토큰만 저장하고 화면을 옮기면 앱은
//      여전히 "내가 누구인가" 를 모른다(#12)
//
// 로그인 화면과 가입 화면이 각자 이 셋을 적으면 한쪽만 고쳐지는 날이 온다. v1 의 두
// 화면이 실제로 그렇게 갈라져 있었다 — 가입 화면은 약관 동의를 따로 받고 있었고 로그인
// 뒤에 동의 화면이 또 물었다(#293).
//
// ## 소셜과 같은 자리로 끝난다
//
// `SocialLoginService` 도 마지막에 `AuthState.completeLogin` 을 부른다. 그래서 신규
// 가입자는 어느 길로 들어와도 라우터가 온보딩으로 보낸다 — 이메일만 다른 길로 가면
// "가입했는데 온보딩이 없는 사람" 이 생긴다.
library;

import '../../features/auth/data/auth_repository_impl.dart';
import '../../features/auth/data/dto/login_request.dart';
import '../../features/auth/data/dto/register_request.dart';
import '../../features/auth/service/secure_token_store.dart';
import 'auth_state.dart';

/// 이메일 로그인·가입의 결과. 화면은 이 값으로만 말한다.
enum EmailAuthOutcome {
  ok,

  /// 401 — 이메일이나 비밀번호가 틀렸다. **어느 쪽인지 말하지 않는다** — 말하면
  /// "그 이메일은 가입돼 있다" 를 아무에게나 알려 주는 셈이다.
  wrongCredentials,

  /// 409 — 그 이메일로 이미 계정이 있다. **가입에서만** 나온다.
  duplicateEmail,

  /// 400 — 서버가 입력을 거절했다. 다시 눌러도 같은 결과다.
  invalidInput,

  /// 못 닿았거나 5xx. 다시 눌러 볼 만하다.
  failed,
}

/// 화면에 그대로 띄우는 문구. 분기를 화면마다 적지 않는다.
String emailAuthMessage(EmailAuthOutcome outcome) => switch (outcome) {
      EmailAuthOutcome.ok => '',
      EmailAuthOutcome.wrongCredentials => '이메일이나 비밀번호가 맞지 않아요',
      EmailAuthOutcome.duplicateEmail => '이미 가입된 이메일이에요 · 로그인해 주세요',
      EmailAuthOutcome.invalidInput => '입력을 다시 확인해 주세요',
      EmailAuthOutcome.failed => '연결이 불안정해요 · 잠시 뒤 다시 시도해 주세요',
    };

class EmailAuthService {
  EmailAuthService._();

  /// 테스트가 갈아 끼우는 자리. 평소에는 진짜 저장소다.
  static AuthRepositoryImpl repository = AuthRepositoryImpl();

  static void resetForTest() => repository = AuthRepositoryImpl();

  /// 이메일로 로그인. 성공하면 토큰을 저장하고 `AuthState` 를 확정한다.
  static Future<EmailAuthOutcome> signIn({
    required String email,
    required String password,
  }) async {
    AuthTokensResult tokens;
    try {
      final result = await repository.login(
        LoginRequest(email: email.trim(), password: password),
      );
      if (result == null) {
        // 저장소가 401 과 네트워크 실패를 둘 다 null 로 준다. 여기서 더 가를 수단이
        // 없으므로 **더 흔한 쪽**(비밀번호 오타)으로 말한다 — "연결이 불안정해요" 를
        // 보여 주면 사용자는 비밀번호를 의심하지 않고 계속 같은 것을 넣는다.
        return EmailAuthOutcome.wrongCredentials;
      }
      tokens = (accessToken: result.accessToken, refreshToken: result.refreshToken, isNew: result.isNew);
    } catch (_) {
      return EmailAuthOutcome.failed;
    }
    await _settle(tokens);
    return EmailAuthOutcome.ok;
  }

  /// 이메일로 가입하고 **바로 로그인까지** 한다.
  ///
  /// 가입만 시키고 로그인 화면으로 되돌리면 방금 정한 비밀번호를 다시 치게 된다.
  /// 서버가 가입 응답에 토큰을 안 주므로 여기서 이어 부른다.
  static Future<EmailAuthOutcome> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final RegisterOutcome outcome;
    try {
      outcome = await repository.register(RegisterRequest(
        email: email.trim(),
        password: password,
        nickname: nickname.trim(),
        // 서버 계약이 요구하는 칸들. 가입 화면에서 안 묻는 것은 기본값으로 채운다 —
        // 물을수록 가입이 길어지고, 이 둘은 지금 어느 화면도 쓰지 않는다.
        name: nickname.trim(),
        gender: 'unknown',
        ageGroup: 'over14',
      ));
    } catch (_) {
      return EmailAuthOutcome.failed;
    }

    return switch (outcome) {
      RegisterOutcome.created => signIn(email: email, password: password),
      RegisterOutcome.duplicateEmail => EmailAuthOutcome.duplicateEmail,
      RegisterOutcome.invalidInput => EmailAuthOutcome.invalidInput,
      RegisterOutcome.failed => EmailAuthOutcome.failed,
    };
  }

  static Future<void> _settle(AuthTokensResult tokens) async {
    await SecureTokenStore.instance.writeTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    await AuthState.completeLogin(isNew: tokens.isNew);
  }
}

/// 저장소가 주는 토큰 셋 — 타입 이름을 여기서 줄여 쓴다.
typedef AuthTokensResult = ({String accessToken, String? refreshToken, bool isNew});
