// lib/v2/data/avatar_border_store.dart
//
// 아바타 테두리 색이 남는 자리 — 이슈 #516.
//
// 편집 화면에서 고른 색이 **어디에도 안 저장돼** 앱을 껐다 켤 때마다 기본값으로 돌아갔다.
// 고르는 칸을 그려 놓고 안 지키는 것은 저장 버튼이 아무 일도 안 하는 것과 같다.
//
// 값은 `AppThemeCtl.avatarBorder` 라는 메모리 한 곳에 살고, 이 파일은 그것을 디스크와
// 맞추기만 한다 — 화면이 `SharedPreferences` 를 직접 읽으면 그 한 곳이 두 곳이 된다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/themes.dart';

class AvatarBorderStore {
  const AvatarBorderStore();

  /// 고른 색이 남는 자리. **세션 것이다** — 로그아웃하면 지운다(#513).
  ///
  /// 그 색은 이 기기의 설정이 아니라 **그 사람의 선택**이다. 남겨 두면 다음 사람의 아바타에
  /// 앞사람이 고른 테가 둘린다.
  static const String key = 'v2.avatar_border';

  /// 저장된 색을 되살린다. **`runApp` 전에 한 번** 부른다 — 늦으면 첫 프레임이 기본색으로
  /// 그려졌다가 바뀐다.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final argb = prefs.getInt(key);
      if (argb != null) {
        AppThemeCtl.avatarBorder.value = Color(argb);
      }
    } catch (e) {
      // 못 읽으면 기본색으로 시작한다 — 여기서 던지면 앱이 안 뜬다.
      if (kDebugMode) debugPrint('[AvatarBorder] 못 읽었다: $e');
    }
  }

  /// 고른 색을 남긴다. 메모리 값도 여기서 바꾼다 — 부르는 쪽이 둘을 따로 하면 한쪽을 빠뜨린다.
  Future<void> save(Color color) async {
    AppThemeCtl.avatarBorder.value = color;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, color.toARGB32());
    } catch (e) {
      // 화면은 이미 바뀌었다. 다음 실행에 안 남을 뿐이라 여기서 사용자를 붙잡지 않는다.
      if (kDebugMode) debugPrint('[AvatarBorder] 못 남겼다: $e');
    }
  }
}
