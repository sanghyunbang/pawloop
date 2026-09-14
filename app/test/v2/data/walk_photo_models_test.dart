// 사진 경로 · id 가 초안과 스냅숏을 지나 살아남고, 서버 응답의 media 를 읽는다 (#450).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/walk_in_progress.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

void main() {
  test('WalkDraft: photoPaths · mediaIds 가 JSON 을 지나 그대로다 — 앱이 죽어도 사진은 남는다', () {
    final draft = WalkDraft.fresh(
      startedAt: DateTime(2026, 9, 14, 7),
      endedAt: DateTime(2026, 9, 14, 7, 30),
      distanceM: 1000,
      durationS: 600,
      path: const [],
      photoPaths: const ['/docs/walk_photos/1/a.jpg', '/docs/walk_photos/1/b.jpg'],
    ).copyWith(mediaIds: const [31]);

    final back = WalkDraft.tryParse(draft.toJson())!;

    expect(back.photoPaths, ['/docs/walk_photos/1/a.jpg', '/docs/walk_photos/1/b.jpg']);
    expect(back.mediaIds, [31]);
    expect(back.copyWith(memo: '메모').photoPaths, hasLength(2), reason: 'copyWith 가 사진을 안 떨어뜨린다');
  });

  test('WalkDraft: 옛 초안(키 없음)은 빈 목록이다', () {
    final back = WalkDraft.tryParse({
      'clientWalkId': 'abcdefgh',
      'startedAt': '2026-09-14T07:00:00Z',
      'endedAt': '2026-09-14T07:30:00Z',
      'distanceM': 1000,
      'durationS': 600,
      'path': <List<double>>[],
    })!;
    expect(back.photoPaths, isEmpty);
    expect(back.mediaIds, isEmpty);
  });

  test('WalkInProgress: photoPaths 가 스냅숏을 지나 그대로다', () {
    final snapshot = WalkInProgress(
      startedAt: DateTime(2026, 9, 14, 7),
      seconds: 120,
      distanceM: 200,
      path: const [[127.0, 37.5]],
      pathT: const [0],
      photoPaths: const ['/docs/walk_photos/1/a.jpg'],
      savedAt: DateTime(2026, 9, 14, 7, 2),
    );

    final back = WalkInProgress.tryParse(snapshot.toJson())!;

    expect(back.photoPaths, ['/docs/walk_photos/1/a.jpg']);
  });

  test('ServerWalk: media 를 올린 순서로 읽고, 없으면 빈 목록이다', () {
    final walk = ServerWalk.tryParse({
      'id': 1,
      'dogId': 9,
      'clientWalkId': 'k',
      'startedAt': '2026-09-14T07:00:00Z',
      'distanceM': 1000,
      'durationS': 600,
      'media': [
        {'id': 31, 'kind': 'image', 'url': 'https://cdn/a.jpg', 'width': 1200, 'height': 1600},
        {'id': 32, 'kind': 'image', 'url': 'https://cdn/b.jpg'},
        {'id': 'bad'},
      ],
    })!;

    expect(walk.media.map((m) => m.id), [31, 32]);
    expect(walk.media.first.url, 'https://cdn/a.jpg');
    expect(walk.media.first.width, 1200);
    expect(walk.media.last.width, isNull);

    final plain = ServerWalk.tryParse({
      'id': 2,
      'dogId': 9,
      'clientWalkId': 'k',
      'startedAt': '2026-09-14T07:00:00Z',
      'distanceM': 1000,
      'durationS': 600,
    })!;
    expect(plain.media, isEmpty);
  });
}
