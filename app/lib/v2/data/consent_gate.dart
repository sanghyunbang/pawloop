import 'package:shared_preferences/shared_preferences.dart';

/// 계정 동의 — 이용약관 · 개인정보처리방침 · 위치기반서비스 · 마케팅(선택). 이슈 #180.
///
/// ## 왜 필요한가
///
/// **v2 에는 동의를 받는 자리가 없었다.** 로그인은 카카오·구글뿐이고 그 흐름 어디에도
/// 약관을 보여 주거나 동의를 받는 화면이 없다. 동의 체크박스가 있는 회원가입 화면은
/// `features/auth/presentation/sign_up_screen.dart` 인데, 그 화면으로 가는 길이 v2 에
/// 하나도 없다(이슈 #184).
///
/// 그래서 이 앱은 **아무 동의 없이** 위치를 수집하고 콘텐츠를 받고 있었다.
///
/// 위치정보법이 요구하는 것은 두 가지다.
///
///  - 제15조 — 동의 없이 개인위치정보를 수집·이용·제공하면 3년 이하 징역 또는
///    3천만원 이하 벌금
///  - 제18조·제19조 — **위치기반서비스 이용약관에 명시하고 동의를 받아야 한다.**
///    위반은 5년 이하 징역 또는 5천만원 이하 벌금으로 미신고보다 무겁다
///
/// ## 왜 서버가 아니라 기기에 남기는가
///
/// `ChatTermsGate` 와 같은 판단이고, 같은 한계를 진다 — **기기를 바꾸거나 앱을 지웠다
/// 깔면 다시 뜬다.**
///
/// 다만 여기는 채팅 동의와 무게가 다르다. 위치정보법은 동의를 **받았다는 사실**을
/// 다투게 되는 상황을 전제하고, 기기 안의 불리언 하나는 그 증빙이 되지 않는다.
/// 사업자 신고를 마치고 실제로 운영을 시작하는 시점에는 서버로 옮겨야 한다.
/// **그 작업을 이슈로 남겨 두었다.**
///
/// ## 계정마다 따로 센다
///
/// 한 기기를 가족이 나눠 쓸 수 있다. 계정이 바뀌었는데 앞사람의 동의가 그대로 적용되면
/// **그 사람은 약관을 본 적이 없는데 동의한 것이 된다.**
///
/// ## 버전을 키에 넣지 않는다
///
/// 약관이 바뀌면 다시 받아야 하지만, 키에 버전을 넣으면 옛 키가 읽히지 않은 채 남고
/// "언제 무엇에 동의했는지" 를 셀 수 없게 된다. 재동의는 서버로 옮기는 작업에서 함께
/// 다룬다 — 그때가 버전별 이력을 남길 수 있는 유일한 자리다.
class ConsentGate {
  const ConsentGate({SharedPreferences? preferences}) : _injected = preferences;

  final SharedPreferences? _injected;

  /// 필수 동의를 마쳤는가를 남기는 키.
  static String keyFor(int userId) => 'account_consent_v1_$userId';

  /// 마케팅 수신 동의(선택). **필수와 따로 센다** — 선택 항목을 필수와 한 값에 묶으면
  /// "마케팅을 안 받겠다" 가 "가입을 안 하겠다" 가 된다.
  static String marketingKeyFor(int userId) => 'account_consent_marketing_v1_$userId';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// 이 계정이 필수 동의를 마쳤는가.
  ///
  /// **읽기에 실패하면 "안 했다" 로 본다.** 실패를 "했다" 로 읽으면 저장소가 잠깐 삐끗한
  /// 사이에 동의 없이 위치가 수집된다 — 그 방향의 실수가 훨씬 나쁘다.
  Future<bool> hasAgreed(int userId) async {
    try {
      return (await _prefs).getBool(keyFor(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 마케팅 수신에 동의했는가.
  Future<bool> marketingOptIn(int userId) async {
    try {
      return (await _prefs).getBool(marketingKeyFor(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 동의를 남긴다.
  ///
  /// **성공 여부를 돌려준다.** `ChatTermsGate.markAgreed` 는 실패를 삼키는데, 거기는
  /// 실패해도 다음에 또 물어보는 것이 전부다. 여기는 다르다 — 실패를 삼키면 화면이
  /// 넘어간 뒤 다음 실행에 다시 뜨고, 사용자는 "동의를 했는데 왜 또 묻지" 를 겪는다.
  /// 화면이 그 사실을 알아야 말해 줄 수 있다.
  Future<bool> markAgreed(int userId, {required bool marketing}) async {
    try {
      final prefs = await _prefs;
      final required_ = await prefs.setBool(keyFor(userId), true);
      // 마케팅 쓰기가 실패해도 필수 동의는 남긴 것으로 본다 — 선택 항목 하나 때문에
      // 필수 동의를 다시 받게 하면 그게 더 나쁘다.
      await prefs.setBool(marketingKeyFor(userId), marketing);
      return required_;
    } catch (_) {
      return false;
    }
  }

  /// 이 계정의 동의를 지운다. **로그아웃·탈퇴가 부른다.**
  ///
  /// 안 지우면 같은 기기에서 계정을 지웠다가 같은 id 로 다시 만든 사람에게 앞사람의
  /// 동의가 적용된다.
  Future<void> clear(int userId) async {
    try {
      final prefs = await _prefs;
      await prefs.remove(keyFor(userId));
      await prefs.remove(marketingKeyFor(userId));
    } catch (_) {
      // 삼킨다 — 지우지 못해도 다음 사람에게 한 번 더 묻는 쪽으로 기운다.
    }
  }
}
