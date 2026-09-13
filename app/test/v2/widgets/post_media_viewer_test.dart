// 전체 보기의 영상 페이지 — 포스터와 재생 버튼으로 시작하고, 눌러야 컨트롤러를 만든다 (#429).
//
// 위젯 테스트에는 플레이어 플랫폼이 없다. 그래서 컨트롤러를 만드는 함수를 꽂아 "누르기 전엔
// 안 만든다" 와 "못 만들면 한 줄로 말하고 예외를 새지 않는다" 를 잰다. 진짜 재생은 에뮬레이터.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/widgets/post_media_viewer.dart';

const _video = PostMedia(
  id: 2,
  kind: PostMediaKind.video,
  url: 'https://cdn.example.test/posts-video/7/2.mp4',
  posterUrl: 'https://cdn.example.test/posts/7/posters/2.jpg',
  width: 1280,
  height: 720,
  durationMs: 8000,
);

void main() {
  testWidgets('영상 페이지는 포스터와 재생 버튼으로 시작하고 — 누르기 전엔 컨트롤러를 안 만든다', (tester) async {
    final made = <Uri>[];
    VideoPlayerController factory(Uri url) {
      made.add(url);
      throw StateError('테스트에는 플레이어가 없다');
    }

    await tester.pumpWidget(MaterialApp(
      home: PostMediaViewer(media: const [_video], controllerFactory: factory),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-play')), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(made, isEmpty, reason: '넘겨 보다 스친 영상이 데이터를 먹거나 소리를 내면 안 된다');
    expect(find.text('영상 재생은 곧 지원돼요'), findsNothing, reason: '이제 재생한다');
  });

  testWidgets('재생을 누르면 컨트롤러를 만들고, 못 만들면 "재생할 수 없어요" 한 줄 — 예외가 새지 않는다', (tester) async {
    final made = <Uri>[];
    VideoPlayerController factory(Uri url) {
      made.add(url);
      throw StateError('테스트에는 플레이어가 없다');
    }

    await tester.pumpWidget(MaterialApp(
      home: PostMediaViewer(media: const [_video], controllerFactory: factory),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('post-media-play')));
    await tester.pumpAndSettle();

    expect(made, [Uri.parse(_video.url)], reason: '재생할 파일은 url 이지 포스터가 아니다');
    expect(find.byKey(const Key('post-media-video-error')), findsOneWidget);
    expect(find.text('재생할 수 없어요'), findsOneWidget);
    expect(find.byKey(const Key('post-media-play')), findsOneWidget, reason: '다시 누를 수 있다');
    expect(tester.takeException(), isNull);
  });
}
