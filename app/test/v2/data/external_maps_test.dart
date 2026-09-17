// 전화·길찾기 — 어느 앱을 어떤 순서로 여는가 (#328).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/external_maps.dart';

void main() {
  final original = ExternalMaps.launcher;
  tearDown(() => ExternalMaps.launcher = original);

  test('전화는 tel: 에 숫자만 남긴다', () async {
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return true;
    };

    expect(await ExternalMaps.call('02-123-4567'), isTrue);
    expect(opened.single.toString(), 'tel:021234567');
    expect(await ExternalMaps.call(' - '), isFalse, reason: '숫자가 없으면 열지 않는다');
  });

  test('길찾기는 네이버 지도 앱을 먼저 연다', () async {
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return true;
    };

    final ok = await ExternalMaps.directions(lat: 37.5445, lng: 127.0374, name: '서울숲');

    expect(ok, isTrue);
    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'nmap');
    expect(opened.single.queryParameters['dlat'], '37.5445');
    expect(opened.single.queryParameters['dname'], '서울숲');
    expect(opened.single.queryParameters['appname'], 'app.pawloop');
  });

  test('네이버 지도가 없으면 geo:, 그것도 없으면 웹 — 던져도 다음 후보로', () async {
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      if (uri.scheme == 'nmap') throw Exception('no activity');
      if (uri.scheme == 'geo') return false;
      return true;
    };

    final ok = await ExternalMaps.directions(lat: 37.5, lng: 127.0, name: '병원');

    expect(ok, isTrue);
    expect(opened.map((u) => u.scheme).toList(), ['nmap', 'geo', 'https']);
    expect(opened.last.host, 'map.naver.com');
  });

  test('전부 실패하면 false — 화면이 "지도 앱을 열 수 없어요" 를 말할 수 있게', () async {
    ExternalMaps.launcher = (_) async => false;
    expect(await ExternalMaps.directions(lat: 0, lng: 0, name: 'x'), isFalse);
  });
}
