// 고른 아바타 테두리 색이 남는가 — 이슈 #516.
//
// 편집 화면에 색을 고르는 칸이 있는데 그 값이 **어디에도 안 저장돼** 앱을 껐다 켜면 기본색으로
// 돌아갔다. 고르는 칸을 그려 놓고 안 지키는 것은 저장 버튼이 아무 일도 안 하는 것과 같다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/avatar_border_store.dart';
import 'package:heat_trip_flutter/v2/data/session_traces.dart';
import 'package:heat_trip_flutter/v2/theme/themes.dart';

const _default = Color(0xFFE04A2B);
const _picked = Color(0xFF3B82F6);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppThemeCtl.avatarBorder.value = _default;
  });

  tearDown(() => AppThemeCtl.avatarBorder.value = _default);

  test('고르면 남고, 다시 켜면 그 색이다', () async {
    await const AvatarBorderStore().save(_picked);
    expect(AppThemeCtl.avatarBorder.value.toARGB32(), _picked.toARGB32(),
        reason: '화면은 즉시 바뀌어야 한다');

    // 앱을 껐다 켠 것 — 메모리는 기본값에서 시작하고 디스크에서 되살린다.
    AppThemeCtl.avatarBorder.value = _default;
    await const AvatarBorderStore().restore();

    expect(AppThemeCtl.avatarBorder.value.toARGB32(), _picked.toARGB32());
  });

  test('고른 적이 없으면 기본색 그대로다 — 저장된 것이 없다고 색이 사라지지 않는다', () async {
    await const AvatarBorderStore().restore();

    expect(AppThemeCtl.avatarBorder.value.toARGB32(), _default.toARGB32());
  });

  test('세션이 끝나면 지운다 — 고른 색은 그 사람의 것이다', () async {
    await const AvatarBorderStore().save(_picked);

    expect(sessionScopedKeys, contains(AvatarBorderStore.key),
        reason: '남겨 두면 다음 사람의 아바타에 앞사람이 고른 테가 둘린다 (#513)');

    await clearSessionTraces();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(AvatarBorderStore.key), isNull);
  });
}
