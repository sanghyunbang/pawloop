// lib/v2/data/login_terms_gate.dart
//
// 로그인 **전에** 받는 약관 동의 — 애플 App Review Guideline 1.2.
//
// ## 왜 로그인 화면에 있나
//
// 1.2 는 UGC 앱에 "가입·로그인 **전에** 이용약관(EULA)에 동의를 받으라" 고 요구한다. 우리 동의 화면
// (`consent_screen.dart`)은 소셜 로그인으로 **계정이 생긴 뒤에** 뜬다 — 카카오·구글·Apple 화면 중간에
// 우리 약관을 끼울 수 없어서 "돌아온 직후" 가 가장 이른 자리였다(#180). 애플 기준으로는 그것이 늦다.
// 그래서 로그인 화면의 소셜 버튼 위에 체크칸 하나를 두고, 체크해야 세 버튼이 켜진다.
//
// **로그인 뒤 동의 화면은 그대로다.** 거기서 만 14세 이상 · 이용약관 · 개인정보 · 위치 · 마케팅을 문서
// 버전과 함께 **서버에** 남기고(ADR-0020), 동의 없는 계정을 하루 뒤 거둔다(#660). 이 체크칸은 그 앞에서
// "읽고 동의한다" 를 받는 문이지 동의 기록의 정본이 아니다.
//
// ## 기기에 남긴다 — 문서 버전과 함께
//
// 한 번 동의한 기기는 다음에 로그인 화면을 열 때 체크된 채로 보여 준다. 대신 **이용약관과
// 개인정보처리방침의 지금 버전**([LegalDocument.version])을 함께 적고, 둘 중 하나라도 바뀌면 다시
// 체크해야 한다 — 바뀐 약관에 옛 체크가 이어지면 그것은 동의가 아니다.
//
// 계정이 아니라 **기기** 단위다(`IntroGate` 와 같다). 로그인 전이라 아직 계정이 없다. 가족이 기기를
// 나눠 써도 계정마다의 동의는 로그인 뒤 동의 화면이 따로 받는다. 그래서 로그아웃에 안 지운다
// (`session_keys_are_classified_test.dart` 의 남기는 키).
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/settings/legal_document_screen.dart' show LegalDocument;

class LoginTermsGate {
  const LoginTermsGate({SharedPreferences? preferences}) : _injected = preferences;

  final SharedPreferences? _injected;

  /// 동의를 남기는 키. 값은 [currentStamp] 모양의 문자열이다.
  static const String key = 'login_terms_agreed_v1';

  /// 지금 문서 버전 둘. 이 값과 기기에 남은 값이 **같을 때만** 동의한 것으로 본다.
  static String get currentStamp =>
      'TERMS:${LegalDocument.terms.version}|PRIVACY:${LegalDocument.privacy.version}';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// 이 기기가 **지금 버전의** 약관 둘에 동의한 적이 있는가.
  ///
  /// 못 읽으면 "안 했다" 로 본다 — 한 번 더 체크하게 하는 쪽이, 동의 없이 버튼이 켜지는 쪽보다 낫다.
  Future<bool> hasAgreed() async {
    try {
      return (await _prefs).getString(key) == currentStamp;
    } catch (_) {
      return false;
    }
  }

  /// 체크한 채로 로그인 버튼을 눌렀다. 못 적으면 다음에 한 번 더 체크할 뿐이다 — 삼킨다.
  Future<void> markAgreed() async {
    try {
      await (await _prefs).setString(key, currentStamp);
    } catch (_) {}
  }

  /// 체크를 풀었다. 기억도 지운다 — 풀어 둔 체크가 다음에 켜져 있으면 사용자의 마지막 뜻과 다르다.
  Future<void> clear() async {
    try {
      await (await _prefs).remove(key);
    } catch (_) {}
  }
}
