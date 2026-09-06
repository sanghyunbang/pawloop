// lib/v2/data/intro_gate.dart
//
// 첫 실행 소개(#323)를 **이 기기에서 봤는가** — 계정이 아니라 기기 단위다.
//
// 소개는 로그인 화면보다 앞에 있어서 아직 계정이 없다. 그래서 `ConsentGate`·
// `ChatTermsGate` 처럼 사용자 id 로 키를 나누지 않는다. 한 기기를 가족이 나눠 써도
// 두 번째 사람에게 다시 보여 주지 않는다 — 앱이 무엇인지는 한 번이면 충분하고,
// 다시 보고 싶으면 설정 > 앱 소개 다시 보기 가 있다.
import 'package:shared_preferences/shared_preferences.dart';

class IntroGate {
  const IntroGate({SharedPreferences? preferences}) : _injected = preferences;

  final SharedPreferences? _injected;

  /// `v1` — 장 구성이 크게 바뀌어 다시 보여 주고 싶으면 키를 올린다.
  static const String key = 'intro_seen_v1';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// 본 적이 있는가. 저장소를 못 읽으면 **안 봤다** 로 본다 — 한 번 더 보여 주는 쪽이
  /// 소개 없이 시작하는 쪽보다 낫다(건너뛰기가 한 번 더 늘어날 뿐이다).
  Future<bool> hasSeen() async {
    try {
      return (await _prefs).getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markSeen() async {
    try {
      await (await _prefs).setBool(key, true);
    } catch (_) {
      // 못 적으면 다음 실행에 한 번 더 나온다. 그 이상은 없다.
    }
  }

  /// 테스트·설정에서 되돌릴 때.
  Future<void> clear() async {
    try {
      await (await _prefs).remove(key);
    } catch (_) {}
  }
}
