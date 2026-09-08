// 카드에 실제로 그려진 선이 **잘린 선**인가 — 이슈 #344 완료 조건 2.
//
// ## 왜 바이트 골든이 아닌가
//
// `matchesGoldenFile` 은 blessed 파일과 바이트를 맞춥니다. 이 저장소에는 골든이 하나도
// 없고, 카드에는 글자가 있습니다. 위젯 테스트의 기본 폰트는 실기기와 다르고 래스터라이즈는
// OS 마다 다르므로, 바이트 골든은 **다른 기계에서 늘 빨간불**이 됩니다. 잡고 싶은 것은
// "픽셀이 한 개 달라졌다" 가 아니라 **"집 앞이 그려졌다"** 입니다.
//
// 그래서 그린 그림을 디코드해서 강조색 픽셀의 바운딩 박스를 재고, 그 모양이
// **자른 선의 모양**인지 봅니다. 자르기를 빼면 모양이 원본 쪽으로 돌아가 빨간불이 납니다.
//
// ## 어떻게 구분되는가
//
// 직선을 쓰면 안 됩니다 — `RouteProjection.fit` 이 박스에 꽉 채우므로 자르든 안 자르든
// 똑같은 세로선이 나옵니다. 그래서 **ㄱ 자**를 씁니다: 동쪽 500m 뒤 북쪽 300m.
// 원본 비율은 500:300, 앞뒤 100m 를 버리면 400:200 이라 가로세로비가 달라집니다.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';

const _lat0 = 37.5445;
const _lng0 = 127.0374;
const _mPerDegLat = 111000.0;
double _mPerDegLng(double lat) => 111320.0 * math.cos(lat * math.pi / 180.0);

/// 동쪽 [east] m 를 간 뒤 북쪽 [north] m — ㄱ 자. 5m 간격.
List<List<double>> _ell(double east, double north) {
  const step = 5.0;
  final dLng = step / _mPerDegLng(_lat0);
  final dLat = step / _mPerDegLat;
  final pts = <List<double>>[];
  for (var i = 0; i <= (east / step).round(); i++) {
    pts.add([_lng0 + i * dLng, _lat0]);
  }
  final lngEnd = pts.last[0];
  for (var i = 1; i <= (north / step).round(); i++) {
    pts.add([lngEnd, _lat0 + i * dLat]);
  }
  return pts;
}

const _accent = Color(0xFFFF8F63);

WalkShareCard _card(List<List<double>> path) => WalkShareCard(
      dogName: '보리',
      accent: _accent,
      dateLabel: '2026.09.08 14:20 출발',
      distanceLabel: '0.8km',
      timeLabel: '00:16',
      paceLabel: "20'00\"",
      lngLat: path,
    );

/// 경로 영역(카드 높이의 20%~70% — 그림이 그려지는 자리) 안에서 강조색으로 칠해진
/// 픽셀들의 바운딩 박스.
///
/// **영역을 좁히는 이유.** 강조색은 카드에 세 군데 쓰인다 — 머리의 아이 색 막대, 경로 선,
/// 꼬리의 Pawloop 마크. 온 화면을 훑으면 막대부터 마크까지가 한 상자로 묶여 경로 모양이
/// 사라진다(처음에 그렇게 재서 가로세로비가 0.77 로 나왔다).
///
/// 글로우(반투명)와 시작·끝 점(흰·초록·먹)은 색이 달라 안 걸린다 — 걸리는 것은 선 자체다.
Future<Rect> _routeBox(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final bytes = data.buffer.asUint8List();
  final w = image.width, h = image.height;

  double? minX, minY, maxX, maxY;
  final from = (h * 0.20).round(), to = (h * 0.70).round();
  for (var y = from; y < to; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      // 안티에일리어싱 가장자리를 빼려고 정확히 맞는 픽셀만 센다.
      if (bytes[i] == 0xFF && bytes[i + 1] == 0x8F && bytes[i + 2] == 0x63 && bytes[i + 3] == 0xFF) {
        minX = minX == null ? x.toDouble() : (x < minX ? x.toDouble() : minX);
        maxX = maxX == null ? x.toDouble() : (x > maxX ? x.toDouble() : maxX);
        minY = minY == null ? y.toDouble() : (y < minY ? y.toDouble() : minY);
        maxY = maxY == null ? y.toDouble() : (y > maxY ? y.toDouble() : maxY);
      }
    }
  }
  image.dispose();
  if (minX == null) return Rect.zero;
  return Rect.fromLTRB(minX, minY!, maxX!, maxY!);
}

void main() {
  test('그려진 선은 자른 선의 모양이다 — 원본 모양이면 집 앞이 그려진 것이다', () async {
    final full = _ell(500, 300);
    final card = _card(full);

    // 자르기가 살아 있다는 것부터 — 이 줄이 초록이어야 아래 비율 비교가 의미를 갖는다.
    expect(card.hasRoute, isTrue);
    expect(card.trimmedPath!.length, lessThan(full.length));

    final box = await _routeBox(
      await WalkShareImage.renderPng(card, size: const Size(720, 900)),
    );
    expect(box, isNot(Rect.zero), reason: '강조색 선이 아예 안 그려졌다');

    final drawn = box.width / box.height;
    const fullAspect = 500 / 300; // 1.67 — 안 자른 모양
    const trimmedAspect = 400 / 200; // 2.00 — 앞뒤 100m 를 버린 모양

    expect(
      (drawn - trimmedAspect).abs(),
      lessThan((drawn - fullAspect).abs()),
      reason: '그린 선의 가로세로비($drawn)가 안 자른 모양($fullAspect)에 더 가깝다 — '
          '자르기가 빠졌다(#339 의 trimCourseEnds)',
    );
  });

  test('아주 짧은 산책은 선을 한 픽셀도 안 그린다', () async {
    // 앞뒤 100m 씩 버리면 남는 것이 없는 길이.
    final box = await _routeBox(
      await WalkShareImage.renderPng(_card(_ell(120, 80)), size: const Size(720, 900)),
    );

    expect(box, Rect.zero,
        reason: '자를 것이 없는데 경로 영역에 강조색이 있다 — 집 앞을 그리고 있다');
  });
}
