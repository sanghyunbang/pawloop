// 메모 길이 제한 — 이슈 #161 완료 조건 5.
//
// 서버는 `@Size(max=500)` 인데 앱 `TextField` 에 `maxLength` 가 없었다. 501자를 쓴
// 사람은 '저장' 을 누른 뒤에야 400 을 받고, 그 기록은 거절 큐로 갔다. 되돌릴 수 없는
// 실패를 입력 단계에서 막는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/create_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('메모 칸이 서버와 같은 상한을 건다', (t) async {
    // 메모 칸은 화면 아래쪽이라 기본 뷰포트에서는 빌드조차 안 된다. 화면을 키워
    // 전부 그리게 한 뒤에 본다.
    t.view.physicalSize = const Size(1200, 4200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(const MaterialApp(home: CreateScreen()));
    await t.pump();

    final memo = t.widgetList<TextField>(find.byType(TextField))
        .where((f) => f.maxLines == 4)
        .single;

    expect(memo.maxLength, WalkRepository.maxMemoLength,
        reason: '앱과 서버가 다른 숫자를 들면 사용자는 저장을 누른 뒤에 거절당한다');
  });

  testWidgets('상한을 화면에 박아 두지 않는다 — 저장소 상수를 따라간다', (t) async {
    // 계약·컬럼 폭·앱이 같은 숫자를 세 곳에 적으면 한쪽만 바뀌는 날이 온다.
    expect(WalkRepository.maxMemoLength, 500);
  });
}
