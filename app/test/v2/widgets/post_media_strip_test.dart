// 사진·영상 자리 — 비율 상한 · 캐러셀 · 영상 길이 (#429 · #465).
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

  testWidgets('minAspect 1 이면 세로 사진이 정사각까지 — 카드가 넘기는 값이다 (#465)', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media(width: 720, height: 1280)], minAspect: 1)));
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byType(AspectRatio));
    expect(box.height / box.width, closeTo(1, 1e-6));
  });

  testWidgets('가로 사진은 minAspect 와 상관없다 — 4:3 이면 4:3', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media(width: 1600, height: 1200)], minAspect: 1)));
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byType(AspectRatio));
    expect(box.width / box.height, closeTo(4 / 3, 1e-6));
  });

  testWidgets('둘 이상이면 캐러셀 — "1/3" 과 점 셋, 넘기면 "2/3"', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media(), _media(id: 2), _media(id: 3)])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-carousel')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);

    await tester.drag(find.byKey(const Key('post-media-carousel')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('1/3'), findsNothing);
  });

  testWidgets('한 장이면 캐러셀도 숫자도 없다', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media()])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-carousel')), findsNothing);
    expect(find.byKey(const Key('post-media-counter')), findsNothing);
  });

  testWidgets('onDoubleTap 을 주면 두 번 탭에 불리고, 한 번 탭은 판정 시간 뒤에 전체 보기다 (#451 4번)', (tester) async {
    var doubled = 0;
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media()], onDoubleTap: () => doubled++)));
    await tester.pumpAndSettle();

    final strip = find.byKey(const Key('post-media-strip'));
    await tester.tap(strip);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(strip);
    await tester.pump();
    expect(doubled, 1);
    expect(find.byKey(const Key('post-media-viewer')), findsNothing, reason: '두 번 탭은 전체 보기가 아니다');

    await tester.tap(strip);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-media-viewer')), findsOneWidget);
    expect(doubled, 1);
  });

  testWidgets('onDoubleTap 이 없으면 한 번 탭이 바로 전체 보기다 — 상세·벽은 늦어지지 않는다', (tester) async {
    await tester.pumpWidget(_host(PostMediaStrip(media: [_media()])));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('post-media-strip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const Key('post-media-viewer')), findsOneWidget, reason: '두 번 탭 인식기가 없으니 기다릴 것이 없다');
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
