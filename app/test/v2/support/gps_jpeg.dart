// 테스트용 사진 — 촬영 좌표(GPS IFD)와 회전(orientation 6)을 EXIF 에 실은 JPEG.
//
// 폰 카메라가 찍은 사진의 모양을 흉내 낸다: 픽셀은 가로(40×24)인데 "세로로 보여라" 가 적혀
// 있고, 좌표가 들어 있다. `ImagePrep` 이 이 둘을 어떻게 다루는지를 **값으로** 재는 재료다.
//
// 왜 진짜 사진 파일을 assets 에 두지 않나: 좌표가 든 파일을 저장소에 넣는 것이 바로 이 기능이
// 막으려는 일이다. 여기서 만든 좌표는 지어낸 값이다.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 지어낸 좌표. 실제 장소가 아니다.
const gpsFixtureLatitude = 37;
const gpsFixtureLongitude = 127;

/// 가로 [width]×[height] 픽셀에 orientation 6(시계 방향 90°) 과 GPS 를 실은 JPEG.
Uint8List gpsJpeg({int width = 40, int height = 24, int orientation = 6}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 120, 80));
  image.exif.imageIfd.orientation = orientation;
  image.exif.imageIfd['Make'] = 'Pawloop Test Camera';
  image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(gpsFixtureLatitude, 1);
  image.exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('E');
  image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational(gpsFixtureLongitude, 1);
  return img.encodeJpg(image, quality: 90);
}

/// JPEG 바이트에서 EXIF 를 다시 읽는다. 못 읽으면 실패 — 테스트가 그걸 잡는다.
img.ExifData exifOf(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) throw StateError('JPEG 가 아니다');
  return decoded.exif;
}
