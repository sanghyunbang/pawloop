// 사진 벽 — 이슈 #451 (1번).
//
// 열 나누기는 순수 함수라 값으로 잰다: 순서대로 더 짧은 열에 붙고, 높이는 폭 1 기준
// (1/비율 + 글 두 줄). 타일은 첫 장 하나이고 비율은 4:5 … 1.91:1 로 잘린 값이다(#440).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/post_photo_wall.dart';

Map<String, Object?> _media(int id, {String kind = 'image', int? width = 1600, int? height = 1200}) => {
      'id': id,
      'kind': kind,
      'url': 'https://cdn.example.test/posts/7/$id.${kind == 'video' ? 'mp4' : 'jpg'}',
      'posterUrl': kind == 'video' ? 'https://cdn.example.test/posts/7/$id.jpg' : null,
      'width': width,
      'height': height,
      'durationMs': kind == 'video' ? 8000 : null,
    };

CommunityPost _post(int id, {List<Map<String, Object?>> media = const [], String title = '서울숲 아침 산책'}) =>
    CommunityPost.tryParse({
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'title': title,
      'body': '이른 아침엔 사람이 적어요.',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': media,
    })!;

void main() {
  group('열 나누기', () {
    test('사진 없는 글은 벽에 없다', () {
      final cols = PostPhotoWall.split([_post(1), _post(2, media: [_media(1)]), _post(3)]);
      expect(cols.expand((c) => c).map((p) => p.id), [2]);
    });

    test('순서대로 더 짧은 열에 붙는다 — 세로 사진 뒤에는 두 장이 오른쪽으로 간다', () {
      // 1: 4:5 세로(높이 1.25+0.28) · 2: 1.91:1 가로(0.52+0.28) · 3: 정사각(1+0.28) · 4: 가로
      final cols = PostPhotoWall.split([
        _post(1, media: [_media(1, width: 1080, height: 1350)]),
        _post(2, media: [_media(2, width: 1910, height: 1000)]),
        _post(3, media: [_media(3, width: 1000, height: 1000)]),
        _post(4, media: [_media(4, width: 1910, height: 1000)]),
      ]);
      expect(cols[0].map((p) => p.id), [1, 4], reason: '왼쪽 1.53 vs 오른쪽 0.80 → 3은 오른쪽(2.08) → 4는 왼쪽');
      expect(cols[1].map((p) => p.id), [2, 3]);
    });

    test('높이는 폭 1 기준 1/비율 + 글 두 줄이고, 비율은 4:5 에서 잘린다', () {
      final tall = _post(1, media: [_media(1, width: 1000, height: 3000)]);
      expect(tall.media.first.aspectRatio, closeTo(4 / 5, 1e-9));
      expect(PostPhotoWall.tileHeight(tall), closeTo(1.25 + 0.28, 1e-9));
    });
  });

  testWidgets('타일은 첫 장 하나 · 잘린 비율 · 영상 표시 · +N · 제목과 작성자', (tester) async {
    CommunityPost? tapped;
    final posts = [
      _post(12, media: [_media(1, kind: 'video', width: 1280, height: 720), _media(2)], title: '저녁 산책'),
      _post(13, media: [_media(3, width: 1000, height: 3000)]),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostPhotoWall(posts: posts, onTap: (p) => tapped = p, now: DateTime(2026, 9, 2)),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('photo-tile-12')), findsOneWidget);
    expect(find.byKey(const Key('photo-tile-13')), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2), reason: '글마다 첫 장 하나만 받는다');
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('저녁 산책'), findsOneWidget);
    expect(find.textContaining('보리아빠'), findsNWidgets(2));

    final tallTile = tester.widget<AspectRatio>(find.descendant(
      of: find.byKey(const Key('photo-tile-13')),
      matching: find.byType(AspectRatio),
    ));
    expect(tallTile.aspectRatio, closeTo(4 / 5, 1e-9), reason: '세로 사진 하나가 열을 통째로 먹지 않는다');

    await tester.tap(find.byKey(const Key('photo-tile-12')));
    expect(tapped?.id, 12);
    expect(tester.takeException(), isNull);
  });
}
