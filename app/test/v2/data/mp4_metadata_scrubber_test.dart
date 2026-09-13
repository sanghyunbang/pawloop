// 영상의 위치 상자 덮기 — **나간 파일에 촬영 좌표가 없다** 를 바이트로 잰다 (#429).
//
// 대조군이 있다: 재료 파일에는 `©xyz`·`loci`·`ISO6709` 가 들어 있고 스캔이 그것을 잡는다. 그래야
// "없다" 는 단언이 무엇을 잡는지 분명하다. `Mp4MetadataScrubber._neutralize` 에서 0 으로 덮는
// 줄을 빼면 아래 둘째 테스트가 빨간불이다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/mp4_metadata_scrubber.dart';

import '../support/mp4_fixture.dart';

String _text(Uint8List bytes) => latin1.decode(bytes);

List<String> _types(List<Mp4Box> boxes) => [for (final b in boxes) b.type];

/// `moov` 바로 아래 상자들.
List<Mp4Box> _moovChildren(Uint8List bytes) {
  final moov = Mp4MetadataScrubber.parseBoxes(bytes, 0, bytes.length).firstWhere((b) => b.type == 'moov');
  return Mp4MetadataScrubber.parseBoxes(bytes, moov.payloadOffset, moov.end);
}

void main() {
  test('대조군 — 재료에 위치가 셋 들어 있고 스캔이 그것을 잡는다', () {
    final fixture = mp4Fixture();
    final text = _text(fixture);

    expect(text, contains(mp4FixtureLocation));
    expect(text, contains(mp4FixtureAppleKey));
    expect(_types(_moovChildren(fixture)), ['mvhd', 'trak', 'udta', 'meta']);

    final traces = Mp4MetadataScrubber.findLocationTraces(fixture);
    expect(traces, containsAll(['moov/trak/udta', 'moov/udta', 'moov/meta', '문자열 ISO6709']),
        reason: '스캔이 재료의 위치를 못 보면 아래 "없다" 는 아무것도 아니다');
  });

  test('덮으면 위치 문자열도 상자 타입도 없고 — 크기·ftyp·mdat 은 그대로다', () {
    final original = mp4Fixture();
    final out = Uint8List.fromList(original);

    final report = Mp4MetadataScrubber.scrubBytes(out);

    expect(_types(report.neutralized)..sort(), ['meta', 'udta', 'udta'],
        reason: 'trak 안의 udta 하나 · moov 의 udta · moov 의 meta');

    final text = _text(out);
    expect(text, isNot(contains(mp4FixtureLocation)), reason: '촬영 좌표가 단말을 떠나면 안 된다 (#235 A안)');
    expect(text, isNot(contains(mp4FixtureAppleKey)));
    expect(text, isNot(contains('loci')));
    expect(text, isNot(contains('©xyz')));
    expect(Mp4MetadataScrubber.findLocationTraces(out), isEmpty);

    // 크기를 안 바꾼다 — stco/co64 의 청크 오프셋이 그대로여야 영상이 산다.
    expect(out.length, original.length);
    final tops = Mp4MetadataScrubber.parseBoxes(out, 0, out.length);
    expect(_types(tops), ['ftyp', 'moov', 'mdat']);
    final ftyp = tops[0];
    final mdat = tops[2];
    expect(out.sublist(ftyp.offset, ftyp.end), original.sublist(ftyp.offset, ftyp.end));
    expect(out.sublist(mdat.offset, mdat.end), original.sublist(mdat.offset, mdat.end), reason: 'mdat 은 손대지 않는다');

    // moov 안 — 자리는 같고 타입만 free 다. mvhd·tkhd 는 그대로.
    final before = _moovChildren(original);
    final after = _moovChildren(out);
    expect([for (final b in after) (b.offset, b.size)], [for (final b in before) (b.offset, b.size)]);
    expect(_types(after), ['mvhd', 'trak', 'free', 'free']);
    final mvhd = after[0];
    expect(out.sublist(mvhd.offset, mvhd.end), original.sublist(mvhd.offset, mvhd.end));
    final trakChildren = Mp4MetadataScrubber.parseBoxes(out, after[1].payloadOffset, after[1].end);
    expect(_types(trakChildren), ['tkhd', 'free']);
    expect(out.sublist(trakChildren[0].offset, trakChildren[0].end),
        original.sublist(trakChildren[0].offset, trakChildren[0].end));
    // 덮인 상자의 안은 전부 0 이다.
    final freed = after[2];
    expect(out.sublist(freed.payloadOffset, freed.end).every((b) => b == 0), isTrue);
  });

  test('파일에서도 같다 — moov 자리만 다시 쓰고 결과는 버퍼 버전과 바이트까지 같다', () async {
    final dir = await Directory.systemTemp.createTemp('mp4-scrub-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/clip.mp4';
    await File(path).writeAsBytes(mp4Fixture());

    final report = await Mp4MetadataScrubber.scrubFile(path);
    final fromFile = await File(path).readAsBytes();

    final viaBuffer = Uint8List.fromList(mp4Fixture());
    Mp4MetadataScrubber.scrubBytes(viaBuffer);
    expect(fromFile, viaBuffer);
    expect(report.neutralized.length, 3);
    expect(await Mp4MetadataScrubber.findLocationTracesInFile(path), isEmpty);
  });

  test('위치가 없는 파일은 안 건드린다 — 보고도 비어 있다', () async {
    final clean = mp4Fixture(withLocation: false);
    final out = Uint8List.fromList(clean);

    final report = Mp4MetadataScrubber.scrubBytes(out);

    expect(report.changedAnything, isFalse);
    expect(out, clean);
    expect(Mp4MetadataScrubber.findLocationTraces(clean), isEmpty);
  });

  test('moov 가 없으면 Mp4FormatException — 재인코더가 낸 파일이 이 모양이면 올리지 않는다', () async {
    final noMoov = Uint8List.fromList([...mp4Box('ftyp', [1, 2, 3, 4]), ...mp4Box('mdat', [9, 9, 9])]);
    expect(() => Mp4MetadataScrubber.scrubBytes(Uint8List.fromList(noMoov)), throwsA(isA<Mp4FormatException>()));

    final dir = await Directory.systemTemp.createTemp('mp4-scrub-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/nomoov.mp4';
    await File(path).writeAsBytes(noMoov);
    await expectLater(Mp4MetadataScrubber.scrubFile(path), throwsA(isA<Mp4FormatException>()));
  });

  test('큰 상자(size=1, 8바이트 크기) 도 읽는다 — 4GB 넘는 mdat 이 이 모양이다', () {
    final fixture = mp4Fixture(largeMdat: true);
    final tops = Mp4MetadataScrubber.parseBoxes(fixture, 0, fixture.length);

    expect(_types(tops), ['ftyp', 'moov', 'mdat']);
    expect(tops[2].headerSize, 16);
    expect(tops[2].end, fixture.length);

    final out = Uint8List.fromList(fixture);
    expect(Mp4MetadataScrubber.scrubBytes(out).neutralized.length, 3);
    expect(Mp4MetadataScrubber.findLocationTraces(out), isEmpty);
  });

  test('끝을 넘는 상자를 만나면 거기서 멈춘다 — 예외가 아니라 "여기까지"', () {
    final fixture = mp4Fixture();
    final truncated = fixture.sublist(0, fixture.length - 100);

    final tops = Mp4MetadataScrubber.parseBoxes(truncated, 0, truncated.length);
    expect(_types(tops), ['ftyp', 'moov'], reason: '잘린 mdat 은 목록에서 빠진다');
  });

  test('위치 문자열이 위치 상자가 아닌 곳에 숨어 있어도 스캔이 잡는다 — 덮기로는 못 지우는 자리', () {
    final sneaky = Uint8List.fromList(mp4Fixture(withLocation: false, hiddenMarkerInMvhd: true));

    Mp4MetadataScrubber.scrubBytes(sneaky);

    // 키 하나가 두 표식(`com.apple.quicktime.location` 과 `ISO6709`)을 다 품는다 — 둘 다 잡힌다.
    expect(Mp4MetadataScrubber.findLocationTraces(sneaky),
        containsAll(['문자열 com.apple.quicktime.location', '문자열 ISO6709']),
        reason: '이 파일은 올리면 안 된다 — VideoPrep 이 이 답을 보고 멈춘다');
  });
}
