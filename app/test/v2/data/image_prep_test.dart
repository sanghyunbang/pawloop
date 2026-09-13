// 올리기 전 다시 인코딩 — **나간 바이트에 촬영 좌표가 없다** 를 값으로 잰다 (#429).
//
// 대조군이 있다: 같은 사진을 `image` 패키지로 디코드→인코드만 하면 GPS 가 **살아남는다**.
// 그래야 "지웠다" 는 단언이 무엇을 잡는지 분명하다 — `ImagePrep.prepareSync` 에서
// `sized.exif = img.ExifData()` 한 줄을 빼면 아래 두 번째 테스트가 빨간불이다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:heat_trip_flutter/v2/data/image_prep.dart';

import '../support/gps_jpeg.dart';

void main() {
  test('대조군 — 디코드→인코드만 하면 GPS 가 살아남는다 (이 테스트가 아래 단언의 근거다)', () {
    final original = gpsJpeg();
    expect(exifOf(original).gpsIfd.isEmpty, isFalse, reason: '재료에 GPS 가 들어 있어야 한다');

    final naive = img.encodeJpg(img.decodeJpg(original)!);
    final exif = exifOf(naive);
    expect(exif.gpsIfd.isEmpty, isFalse,
        reason: '인코더는 exif 가 비어 있지 않으면 그대로 쓴다 — 그래서 명시적으로 지워야 한다');
    expect(exif.gpsIfd['GPSLatitude']?.toInt(), gpsFixtureLatitude);
  });

  test('prepare 를 지난 JPEG 에는 GPS IFD 도, 다른 EXIF 도 없다', () {
    final out = ImagePrep.prepareSync(gpsJpeg());

    final exif = exifOf(out.bytes);
    expect(exif.gpsIfd.isEmpty, isTrue, reason: '촬영 좌표가 단말을 떠나면 안 된다 (#235 A안)');
    expect(exif.imageIfd.hasOrientation, isFalse, reason: '회전은 픽셀에 굽고 태그는 버린다');
    expect(exif.imageIfd['Make'], isNull, reason: '기기 모델도 안 나간다');
    expect(exif.isEmpty, isTrue);
  });

  test('orientation 6 은 픽셀을 실제로 돌린다 — 가로 40×24 가 세로 24×40 으로', () {
    final out = ImagePrep.prepareSync(gpsJpeg(width: 40, height: 24, orientation: 6));
    expect((out.width, out.height), (24, 40));

    final decoded = img.decodeJpg(out.bytes)!;
    expect((decoded.width, decoded.height), (24, 40), reason: '보고한 크기와 바이트의 크기가 같다');
  });

  test('orientation 1 이면 크기가 그대로다', () {
    final out = ImagePrep.prepareSync(gpsJpeg(width: 40, height: 24, orientation: 1));
    expect((out.width, out.height), (40, 24));
  });

  test('긴 변이 1600 을 넘으면 비율을 지키며 1600 으로 줄인다', () {
    final big = img.Image(width: 4000, height: 3000);
    img.fill(big, color: img.ColorRgb8(10, 20, 30));
    final out = ImagePrep.prepareSync(img.encodeJpg(big, quality: 50));

    expect(out.width, ImagePrep.maxLongEdge);
    expect(out.height, 1200, reason: '4:3 이 유지된다');
    final decoded = img.decodeJpg(out.bytes)!;
    expect((decoded.width, decoded.height), (1600, 1200));
  });

  test('긴 변이 1600 이하면 키우지 않는다', () {
    final out = ImagePrep.prepareSync(gpsJpeg(width: 800, height: 600, orientation: 1));
    expect((out.width, out.height), (800, 600));
  });

  test('사진이 아니면 ImagePrepException — 화면이 그 칸에 이유를 쓴다', () {
    expect(
      () => ImagePrep.prepareSync(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<ImagePrepException>()),
    );
  });

  test('PNG 도 받아서 JPEG 로 낸다 — 갤러리에는 스크린샷도 있다', () {
    final png = img.Image(width: 30, height: 20);
    img.fill(png, color: img.ColorRgb8(0, 200, 0));
    final out = ImagePrep.prepareSync(img.encodePng(png));

    expect(out.bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG SOI 마커');
    expect((out.width, out.height), (30, 20));
  });
}
