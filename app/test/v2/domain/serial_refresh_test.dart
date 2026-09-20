// 한 번에 하나만, 겹치면 끝난 뒤 한 번 더 (#758) — 지도 마커 다시 그리기가 겹쳐 죽던 자리의 규칙.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/serial_refresh.dart';

void main() {
  test('겹치면 한 번에 하나 — 도는 중의 부름은 끝난 뒤 한 번으로 모인다', () async {
    final refresh = SerialRefresh();
    final gate = Completer<void>();
    var starts = 0;
    Future<void> job() async {
      starts++;
      if (starts == 1) await gate.future;
    }

    final first = refresh.run(job);
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
    expect(refresh.isBusy, isTrue);

    // 도는 중에 셋이 더 부른다 — 바로 돌아온다.
    await refresh.run(job);
    await refresh.run(job);
    await refresh.run(job);
    expect(starts, 1, reason: '도는 중에는 시작하지 않는다 — clearOverlays 가 겹치던 자리');

    gate.complete();
    await first;
    expect(starts, 2, reason: '겹친 셋은 끝난 뒤 한 번으로 모인다 — 마지막 상태 하나만 그리면 된다');
    expect(refresh.isBusy, isFalse);
  });

  test('안 겹치면 부른 만큼 돈다', () async {
    final refresh = SerialRefresh();
    var starts = 0;
    for (var i = 0; i < 3; i++) {
      await refresh.run(() async => starts++);
    }
    expect(starts, 3);
  });

  test('던져도 다음 부름은 된다 — 한 번의 실패가 지도를 영영 못 그리게 하지 않는다', () async {
    final refresh = SerialRefresh();
    await expectLater(refresh.run(() async => throw StateError('지도가 아직')), throwsStateError);
    expect(refresh.isBusy, isFalse);

    var ran = false;
    await refresh.run(() async => ran = true);
    expect(ran, isTrue);
  });
}
