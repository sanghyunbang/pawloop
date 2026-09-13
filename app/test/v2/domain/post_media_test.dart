// 글에 붙은 사진·영상 파서 — 계약의 `PostMedia` 키로 읽는다 (#429).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/post_media.dart';

Map<String, Object?> _image({int id = 1, int? width = 1600, int? height = 1200}) => {
      'id': id,
      'kind': 'image',
      'url': 'https://cdn.example.test/post/$id.jpg',
      'posterUrl': null,
      'width': width,
      'height': height,
      'durationMs': null,
    };

Map<String, Object?> _video({int id = 2}) => {
      'id': id,
      'kind': 'video',
      'url': 'https://cdn.example.test/post/$id.mp4',
      'posterUrl': 'https://cdn.example.test/post/$id.jpg',
      'width': 1280,
      'height': 720,
      'durationMs': 12500,
    };

void main() {
  test('계약의 키로 읽는다 — id·kind·url·posterUrl·width·height·durationMs', () {
    final media = PostMedia.tryParse(_video())!;
    expect(media.id, 2);
    expect(media.kind, PostMediaKind.video);
    expect(media.url, 'https://cdn.example.test/post/2.mp4');
    expect(media.posterUrl, 'https://cdn.example.test/post/2.jpg');
    expect((media.width, media.height, media.durationMs), (1280, 720, 12500));
  });

  test('사진은 그림이 url 이고, 영상은 썸네일이 posterUrl 이다', () {
    expect(PostMedia.tryParse(_image())!.thumbnailUrl, 'https://cdn.example.test/post/1.jpg');
    expect(PostMedia.tryParse(_video())!.thumbnailUrl, 'https://cdn.example.test/post/2.jpg');
    expect(PostMedia.parseList([{..._video(), 'posterUrl': null}]).single.thumbnailUrl, isNull,
        reason: '썸네일이 없는 영상은 어두운 칸이다 — 영상 파일을 그림으로 열지 않는다');
  });

  test('모르는 kind 는 버린다 — 나머지는 산다', () {
    final list = PostMedia.parseList([
      _image(id: 1),
      {..._image(id: 7), 'kind': 'document'},
      _video(id: 2),
    ]);
    expect([for (final m in list) m.id], [1, 2]);
  });

  test('모양이 아닌 항목은 버린다 — 한 칸이 깨져도 글은 산다', () {
    expect(PostMedia.tryParse(null), isNull);
    expect(PostMedia.tryParse('x'), isNull);
    expect(PostMedia.tryParse({..._image(), 'url': ''}), isNull);
    expect(PostMedia.tryParse({..._image(), 'id': 'a'}), isNull);
    expect(PostMedia.parseList(null), isEmpty);
    expect(PostMedia.parseList('nope'), isEmpty);
    expect(PostMedia.parseList([null, 3, _image()]).length, 1);
  });

  test('가로세로비 — 크기를 모르면 1, 너무 길거나 납작하면 잘라 둔다', () {
    expect(PostMedia.tryParse(_image(width: null, height: null))!.aspectRatio, 1);
    expect(PostMedia.tryParse(_image(width: 0, height: 10))!.aspectRatio, 1);
    expect(PostMedia.tryParse(_image(width: 1600, height: 1200))!.aspectRatio,
        closeTo(4 / 3, 1e-9));
    expect(PostMedia.tryParse(_image(width: 100, height: 1000))!.aspectRatio, 0.6,
        reason: '세로로 아주 긴 사진이 카드를 끝없이 늘리지 않는다');
    expect(PostMedia.tryParse(_image(width: 3000, height: 100))!.aspectRatio, 1.8);
  });

  test('같은 값이면 같다 — 화면이 목록을 비교해 바뀐 것만 보낸다', () {
    expect(PostMedia.tryParse(_image()), PostMedia.tryParse(_image()));
    expect(PostMedia.tryParse(_image()), isNot(PostMedia.tryParse(_image(id: 9))));
  });
}
