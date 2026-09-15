// 크기를 모르는 사진은 자르지 않는다 — 이슈 #517.
//
// 서버가 가로세로를 모르면 카드는 자리를 1:1 로 잡는다. 거기에 4:5 사진을 `BoxFit.cover`
// 로 그리면 위아래가 잘린다 — 산책 경로 그림(1080×1350)의 아래쪽 "0.90km · 01:13" 이
// 실제로 그렇게 잘려 있었다. 모를 때는 옆이 비는 편이 내용을 잃는 것보다 낫다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/widgets/post_media_strip.dart';

PostMedia _media({int? width, int? height}) => PostMedia(
      id: 1,
      kind: PostMediaKind.image,
      url: 'https://cdn.test/route.png',
      width: width,
      height: height,
    );

Future<BoxFit> _fitOf(WidgetTester t, PostMedia media) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: PostMediaStrip(media: [media])),
  ));
  await t.pump();
  return t.widget<Image>(find.byType(Image)).fit!;
}

void main() {
  testWidgets('크기를 모르면 안 자른다', (t) async {
    expect(await _fitOf(t, _media()), BoxFit.contain);
  });

  testWidgets('크기를 알면 예전처럼 채운다 — 자리와 사진의 비율이 같아서 잘릴 것이 없다', (t) async {
    expect(await _fitOf(t, _media(width: 1080, height: 1350)), BoxFit.cover);
  });

  test('크기를 모르는 사진의 자리는 1:1 이다 — 4:5 그림이면 위아래가 잘릴 자리다', () {
    expect(_media().hasSize, isFalse);
    expect(_media().aspectRatio, 1);
    expect(_media(width: 1080, height: 1350).hasSize, isTrue);
  });
}
