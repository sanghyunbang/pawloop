// 카드 격자의 영상 칸 — 재생 표시 옆에 길이가 붙는다 (#429).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/widgets/post_media_strip.dart';

PostMedia _media({
  int id = 1,
  String kind = 'image',
  int? durationMs,
  int width = 1280,
  int height = 720,
}) =>
    PostMedia.tryParse({
      'id': id,
      'kind': kind,
      'url': 'https://cdn.example.test/posts/7/$id.${kind == 'video' ? 'mp4' : 'jpg'}',
      'posterUrl': kind == 'video' ? 'https://cdn.example.test/posts/7/$id.jpg' : null,
      'width': width,
      'height': height,
      'durationMs': durationMs,
    })!;

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(18), child: child)));

void main() {
  testWidgets('세로 영상 한 장은 카드에서 4:5 까지만 자리를 잡는다 — 카드가 한 화면에 들어온다 (#440)',
      (tester) async {
    await tester.pumpWidget(
        _host(PostMediaStrip(media: [_media(kind: 'video', width: 720, height: 1280, durationMs: 8000)])));
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byType(AspectRatio));
    expect(box.height / box.width, closeTo(5 / 4, 1e-6),
        reason: '9:16 을 원본대로 두면 폭의 1.78배가 된다 — 인스타그램·페이스북·레딧처럼 4:5 로 자른다');
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget,
        reason: '잘라도 재생 표시는 그대로다');
  });

  testWidgets('정사각·가로 사진은 원본 비율 그대로다 — 4:3 이면 4:3', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media(width: 1600, height: 1200)])));
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byType(AspectRatio));
    expect(box.width / box.height, closeTo(4 / 3, 1e-6));
  });

  testWidgets('영상 칸에는 길이가 붙는다 — 0:08', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media(kind: 'video', durationMs: 8000)])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-duration')), findsOneWidget);
    expect(find.text('0:08'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('사진에는 길이가 없고, 길이를 모르는 영상에도 없다', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media(), _media(id: 2, kind: 'video')])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-duration')), findsNothing);
  });

  test('formatMediaDuration — m:ss 로, 내림이다', () {
    expect(formatMediaDuration(7900), '0:07', reason: '올림이면 59.1초가 1:00 으로 보여 상한을 넘은 것 같다');
    expect(formatMediaDuration(0), '0:00');
    expect(formatMediaDuration(60000), '1:00');
    expect(formatMediaDuration(61234), '1:01');
    expect(_media(kind: 'video', durationMs: 5000).durationLabel, '0:05');
    expect(_media(durationMs: 5000).durationLabel, isNull, reason: '사진에는 길이가 없다');
  });
}
