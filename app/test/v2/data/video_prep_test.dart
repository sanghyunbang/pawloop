// 영상 준비 — 재인코더가 무엇을 남기든 **나가는 파일에 위치 상자가 없다** (#429).
//
// 네이티브 재인코딩은 여기서 안 돈다. 가짜 재인코더가 픽스처 MP4(위치 상자 셋을 실은 것)를
// "결과" 로 내놓고, `VideoPrep` 이 그것을 덮고 확인하는지 잰다. 사진의 `post_media_field_test`
// 첫 테스트와 같은 자리다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:heat_trip_flutter/v2/data/mp4_metadata_scrubber.dart';
import 'package:heat_trip_flutter/v2/data/video_prep.dart';

import '../support/mp4_fixture.dart';

final _poster = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);

/// 재인코딩 대신 주어진 바이트를 새 파일로 쓴다.
class _FakeTranscoder implements VideoTranscoder {
  final Directory dir;
  final Uint8List output;
  final int? durationMs;
  final Uint8List? posterBytes;
  final probes = <String>[];
  final transcoded = <String>[];

  _FakeTranscoder(this.dir, {required this.output, this.durationMs = 12_000, Uint8List? poster})
      : posterBytes = poster;

  @override
  Future<VideoProbe> probe(String path) async {
    probes.add(path);
    return VideoProbe(width: 1280, height: 720, durationMs: durationMs, size: output.length);
  }

  @override
  Future<String> transcode(String path) async {
    final out = '${dir.path}/out-${transcoded.length}.mp4';
    await File(out).writeAsBytes(output);
    transcoded.add(out);
    return out;
  }

  @override
  Future<Uint8List?> poster(String path) async => posterBytes;
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('video-prep-'));
  tearDown(() => dir.delete(recursive: true));

  test('prepare 를 지난 파일에는 위치 상자가 없다 — 재인코더가 남겨도', () async {
    final transcoder = _FakeTranscoder(dir, output: mp4Fixture(), poster: _poster);
    final prep = VideoPrep(transcoder: transcoder);

    final out = await prep.run('${dir.path}/original.mov');

    final bytes = await File(out.path).readAsBytes();
    final text = latin1.decode(bytes);
    expect(text, isNot(contains(mp4FixtureLocation)), reason: '촬영 좌표가 단말을 떠나면 안 된다 (#235 A안)');
    expect(text, isNot(contains(mp4FixtureAppleKey)));
    expect(Mp4MetadataScrubber.findLocationTraces(bytes), isEmpty);
    expect(bytes.length, mp4Fixture().length, reason: '덮기는 크기를 안 바꾼다');

    expect(out.size, bytes.length, reason: '서버에 알리는 크기는 나가는 파일의 것이다');
    expect((out.width, out.height, out.durationMs), (1280, 720, 12_000));
    expect(out.poster, _poster);
    expect(out.contentType, 'video/mp4');
    expect(transcoder.probes.first, '${dir.path}/original.mov', reason: '길이는 원본에서 먼저 잰다');
    expect(transcoder.probes.last, out.path, reason: '크기·길이는 나가는 파일에서 다시 잰다');
  });

  test('60초를 넘으면 재인코딩 전에 멈춘다 — 1분 압축한 뒤에 거절하지 않는다', () async {
    final transcoder = _FakeTranscoder(dir, output: mp4Fixture(), durationMs: 60_001, poster: _poster);

    await expectLater(
      VideoPrep(transcoder: transcoder).run('x.mov'),
      throwsA(isA<VideoPrepException>().having((e) => e.message, 'message', '영상은 60초까지 올릴 수 있어요')),
    );
    expect(transcoder.transcoded, isEmpty);
  });

  test('길이를 모르면 올리지 않는다', () async {
    final transcoder = _FakeTranscoder(dir, output: mp4Fixture(), durationMs: null, poster: _poster);
    await expectLater(
      VideoPrep(transcoder: transcoder).run('x.mov'),
      throwsA(isA<VideoPrepException>()),
    );
    expect(transcoder.transcoded, isEmpty);
  });

  test('위치 문자열이 덮을 수 없는 자리에 남아 있으면 올리지 않는다 — 확인 스캔이 판정이다', () async {
    final sneaky = mp4Fixture(withLocation: false, hiddenMarkerInMvhd: true);
    final transcoder = _FakeTranscoder(dir, output: sneaky, poster: _poster);

    await expectLater(
      VideoPrep(transcoder: transcoder).run('x.mov'),
      throwsA(isA<VideoPrepException>()
          .having((e) => e.message, 'message', '위치 정보를 지우지 못해서 올리지 않아요')),
    );
  });

  test('상한보다 크면 올리지 않는다 — 크기는 압축 뒤의 파일로 잰다', () async {
    final transcoder = _FakeTranscoder(dir, output: mp4Fixture(), poster: _poster);

    await expectLater(
      VideoPrep(transcoder: transcoder, maxBytes: 100).run('x.mov'),
      throwsA(isA<VideoPrepException>().having((e) => e.message, 'message', contains('너무 커요'))),
    );
    expect(transcoder.transcoded, hasLength(1), reason: '압축은 했고, 그 결과가 커서 멈춘 것이다');
  });

  test('썸네일을 못 만들면 올리지 않는다 — 서버가 포스터 없는 영상을 안 받는다', () async {
    final transcoder = _FakeTranscoder(dir, output: mp4Fixture(), poster: null);
    await expectLater(
      VideoPrep(transcoder: transcoder).run('x.mov'),
      throwsA(isA<VideoPrepException>().having((e) => e.message, 'message', '썸네일을 만들지 못했어요')),
    );
  });

  test('재인코더가 상자 트리가 아닌 것을 내면 올리지 않는다', () async {
    final garbage = Uint8List.fromList(List<int>.filled(64, 7));
    final transcoder = _FakeTranscoder(dir, output: garbage, poster: _poster);
    await expectLater(
      VideoPrep(transcoder: transcoder).run('x.mov'),
      throwsA(isA<VideoPrepException>().having((e) => e.message, 'message', '영상 파일을 읽을 수 없어요')),
    );
  });

  test('openRead 는 기본으로 파일을 읽고, discard 는 그 파일을 지운다 — 없어도 조용하다', () async {
    final path = '${dir.path}/clip.mp4';
    await File(path).writeAsBytes([1, 2, 3, 4]);
    final video = PreparedVideo(path: path, size: 4, width: 1, height: 1, durationMs: 1, poster: _poster);

    final bytes = [for (final chunk in await video.openRead().toList()) ...chunk];
    expect(bytes, [1, 2, 3, 4]);

    await video.discard();
    expect(File(path).existsSync(), isFalse);
    await video.discard();
  });

  test('폭·높이는 포스터의 방향을 따른다 — 세로로 찍은 영상이 피드에서 16:9 로 잘리지 않게', () {
    expect(VideoProbe.sizeMatchingPoster(1280, 720, (24, 40)), (720, 1280), reason: '재인코더가 가로로 알려도 포스터가 세로면 세로');
    expect(VideoProbe.sizeMatchingPoster(720, 1280, (24, 40)), (720, 1280));
    expect(VideoProbe.sizeMatchingPoster(1280, 720, (40, 24)), (1280, 720));
    expect(VideoProbe.sizeMatchingPoster(1280, 720, (30, 30)), (1280, 720), reason: '정사각 포스터는 방향을 말해 주지 않는다');
    expect(VideoProbe.sizeMatchingPoster(1280, 720, null), (1280, 720), reason: '포스터를 못 읽으면 그대로');
    expect(VideoProbe.sizeMatchingPoster(null, null, (24, 40)), (null, null));
  });

  test('세로 포스터가 붙은 영상은 나가는 크기도 세로다 — 실제 파이프라인으로', () async {
    final portrait = img.Image(width: 24, height: 40);
    img.fill(portrait, color: img.ColorRgb8(0, 120, 0));
    final poster = img.encodeJpg(portrait, quality: 60);
    final transcoder = _FakeTranscoder(dir, output: mp4Fixture(), poster: poster);

    final out = await VideoPrep(transcoder: transcoder).run('${dir.path}/x.mov');

    expect(VideoPrep.posterSize(poster), (24, 40));
    expect((out.width, out.height), (720, 1280), reason: '가짜 재인코더는 1280×720 이라고 말한다');
  });

  test('상한 상수가 서버와 같다 — 60초 · 150MB · 한 글에 하나', () {
    expect(VideoLimits.maxDuration, const Duration(seconds: 60));
    expect(VideoLimits.maxBytes, 150 * 1024 * 1024);
    expect(VideoLimits.maxPerPost, 1);
  });
}
