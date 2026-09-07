// 진행 중인 산책 스냅숏 — 적고, 읽고, 깨진 것과 오래된 것은 잇지 않는다 (#335).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_in_progress.dart';

WalkInProgress _walk({DateTime? savedAt}) => WalkInProgress(
      startedAt: DateTime(2026, 9, 7, 15, 41),
      seconds: 720,
      distanceM: 320,
      path: const [
        [127.0410, 37.5445],
        [127.0416, 37.5449],
      ],
      pathT: const [0, 300],
      savedAt: savedAt ?? DateTime(2026, 9, 7, 15, 53),
    );

void main() {
  const store = WalkInProgressStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('적은 것을 그대로 읽는다 — 경로·시각·거리·초', () async {
    await store.save(_walk());

    final back = await store.load(now: DateTime(2026, 9, 7, 15, 55));

    expect(back, isNotNull);
    expect(back!.startedAt, DateTime(2026, 9, 7, 15, 41));
    expect(back.seconds, 720);
    expect(back.distanceM, 320);
    expect(back.km, closeTo(0.32, 1e-9));
    expect(back.path, [
      [127.0410, 37.5445],
      [127.0416, 37.5449],
    ]);
    expect(back.pathT, [0, 300]);
  });

  test('없으면 null', () async {
    expect(await store.load(), isNull);
  });

  test('6시간 넘게 오래된 스냅숏은 잇지 않고 지운다 — 어제 산책을 오늘 산책에 붙이면 거리가 거짓이 된다', () async {
    await store.save(_walk(savedAt: DateTime(2026, 9, 7, 8, 0)));

    expect(await store.load(now: DateTime(2026, 9, 7, 15, 0)), isNull);
    expect((await SharedPreferences.getInstance()).getString(WalkInProgressStore.key), isNull,
        reason: '한 번 판정한 오래된 것은 다음에 또 묻지 않는다');
  });

  test('깨진 JSON 은 null 이고 지운다', () async {
    SharedPreferences.setMockInitialValues({WalkInProgressStore.key: '{not json'});

    expect(await store.load(), isNull);
    expect((await SharedPreferences.getInstance()).getString(WalkInProgressStore.key), isNull);
  });

  test('path 와 pathT 길이가 다르면 null — 서버 계약이 같은 길이를 요구한다', () {
    final json = _walk().toJson();
    json['pathT'] = [0];
    expect(WalkInProgress.tryParse(json), isNull);
  });

  test('점 하나가 [경도, 위도] 두 수가 아니면 null', () {
    final json = _walk().toJson();
    json['path'] = [
      [127.0, 37.5],
      [127.0],
    ];
    expect(WalkInProgress.tryParse(json), isNull);
  });

  test('clear 하면 없다', () async {
    await store.save(_walk());
    await store.clear();
    expect(await store.load(now: DateTime(2026, 9, 7, 15, 55)), isNull);
  });
}
