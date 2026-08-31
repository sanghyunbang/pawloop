import 'package:shared_preferences/shared_preferences.dart';

/// 채팅에 처음 들어갈 때 받는 동의 — 이슈 #82 완료 조건 6.
///
/// ## 왜 필요한가
///
/// Google Play 의 UGC 정책이 **"이용자가 콘텐츠를 만들기 전에"** 약관 동의를 요구한다.
/// 채팅은 이 앱에서 사용자가 남의 눈에 보이는 글을 처음 쓰는 자리다.
///
/// ## 왜 서버에 안 남기는가
///
/// 지금 이 동의가 하는 일은 **화면에 한 번 보여 주는 것**이다. 서버에 남기면 그 값이
/// 계약·표·마이그레이션을 하나씩 끌고 오는데, 그렇게 만든 열이 실제로 읽히는 곳은
/// "이 화면을 띄울까" 하나뿐이다. 필요해지는 시점 — 동의 이력을 증빙해야 하는 순간 — 에
/// 서버로 옮기고, **그때가 언제인지 여기 적어 둔다.**
///
/// 대신 한계를 그대로 적는다. 기기를 바꾸거나 앱을 지웠다 깔면 **다시 뜬다.** 동의를
/// 되돌리는 방법은 앱 삭제뿐이다. 지금 단계에서 그 정도는 감수할 만하다고 봤다.
///
/// ## 계정마다 따로 센다
///
/// 한 기기를 가족이 나눠 쓸 수 있다. 계정이 바뀌었는데 앞사람의 동의가 그대로 적용되면
/// **그 사람은 약관을 본 적이 없는데 동의한 것이 된다.**
class ChatTermsGate {
  const ChatTermsGate({SharedPreferences? preferences}) : _injected = preferences;

  final SharedPreferences? _injected;

  /// 동의를 남기는 키. 계정 id 를 붙여 사람마다 따로 센다.
  static String keyFor(int userId) => 'chat_terms_agreed_v1_$userId';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// 이 계정이 이미 동의했는가.
  ///
  /// **읽기에 실패하면 "안 했다" 로 본다.** 실패를 "했다" 로 읽으면 저장소가 잠깐 삐끗한
  /// 사이에 동의 없이 채팅이 열린다 — 그 방향의 실수가 더 나쁘다.
  Future<bool> hasAgreed(int userId) async {
    try {
      return (await _prefs).getBool(keyFor(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 동의를 남긴다.
  ///
  /// 저장에 실패해도 예외를 올리지 않는다. 실패하면 다음에 또 물어보게 되는데, 그건
  /// 성가신 일이지 위험한 일이 아니다 — 반대로 실패를 오류로 올리면 **동의했는데 채팅에
  /// 못 들어가는** 상태가 된다.
  Future<void> markAgreed(int userId) async {
    try {
      await (await _prefs).setBool(keyFor(userId), true);
    } catch (_) {
      // 삼킨다. 위 javadoc 참조.
    }
  }
}
