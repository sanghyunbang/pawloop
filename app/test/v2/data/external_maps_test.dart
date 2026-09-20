// 전화·길찾기 — 어느 앱을 어떤 순서로 여는가 (#328), 그리고 **취소는 실패가 아니다** (2026-09-21).
//
// 사장님이 폰에서 본 것: "지도 앱으로 길 안내" 뒤 iOS 가 "'네이버 지도'에서 열까요?" 를 물었고,
// 취소를 눌렀는데 사파리의 네이버 지도가 떴다. `launchUrl` 이 취소를 false 로 돌려주는데, 그것을
// "앱이 없다" 로 읽고 다음 후보(웹)를 열었기 때문이다. 이제 열 수 있는지를 먼저 묻고, 열 수 있다고
// 한 앱이 false 를 주면 거기서 멈춘다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/external_maps.dart';

void main() {
  final originalLauncher = ExternalMaps.launcher;
  final originalCanOpen = ExternalMaps.canOpen;
  tearDown(() {
    ExternalMaps.launcher = originalLauncher;
    ExternalMaps.canOpen = originalCanOpen;
  });

  /// 연 것을 기록하고 [answer] 를 돌려주는 launcher.
  List<Uri> record({bool answer = true}) {
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return answer;
    };
    return opened;
  }

  test('전화는 tel: 에 숫자만 남긴다', () async {
    final opened = record();

    expect(await ExternalMaps.call('02-123-4567'), isTrue);
    expect(opened.single.toString(), 'tel:021234567');
    expect(await ExternalMaps.call(' - '), isFalse, reason: '숫자가 없으면 열지 않는다');
  });

  test('길찾기는 네이버 지도 앱을 먼저 연다', () async {
    ExternalMaps.canOpen = (_) async => true;
    final opened = record();

    final result = await ExternalMaps.directions(lat: 37.5445, lng: 127.0374, name: '서울숲');

    expect(result, ExternalOpen.opened);
    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'nmap');
    expect(opened.single.queryParameters['dlat'], '37.5445');
    expect(opened.single.queryParameters['dname'], '서울숲');
    expect(opened.single.queryParameters['appname'], 'app.pawloop');
  });

  test('열 수 있다고 한 앱이 안 열리면 거기서 멈춘다 — iOS 의 "열까요?" 에서 취소한 사람을 웹으로 데려가지 않는다',
      () async {
    ExternalMaps.canOpen = (uri) async => uri.scheme == 'nmap';
    final opened = record(answer: false);

    final result = await ExternalMaps.directions(lat: 37.5445, lng: 127.0374, name: '서울숲');

    expect(result, ExternalOpen.declined);
    expect(opened.map((u) => u.scheme).toList(), ['nmap'],
        reason: '취소 뒤에 geo: 도 웹도 열면 안 된다 — 그 false 는 사람의 답이다');
  });

  test('네이버 지도가 없으면 묻지도 않고 geo:, 그것도 없으면 웹을 그냥 연다', () async {
    ExternalMaps.canOpen = (_) async => false;
    final opened = record();

    final result = await ExternalMaps.directions(lat: 37.5, lng: 127.0, name: '병원');

    expect(result, ExternalOpen.opened);
    expect(opened.map((u) => u.scheme).toList(), ['https'],
        reason: '없다고 한 앱은 열어 보지 않는다. 웹은 마지막 후보라 묻지 않는다');
    expect(opened.last.host, 'map.naver.com');
  });

  test('열다가 던지면 다음 후보로 — 앱이 그새 지워졌거나 OS 오류다, 사람의 답이 아니다', () async {
    ExternalMaps.canOpen = (_) async => true;
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      if (uri.scheme == 'nmap') throw Exception('no activity');
      return true;
    };

    final result = await ExternalMaps.directions(lat: 37.5, lng: 127.0, name: '병원');

    expect(result, ExternalOpen.opened);
    expect(opened.map((u) => u.scheme).toList(), ['nmap', 'geo']);
  });

  test('canLaunchUrl 이 던져도 "없다" 로 본다 — 플러그인이 없는 자리에서 죽지 않는다', () async {
    ExternalMaps.canOpen = (_) async => throw StateError('no plugin');
    final opened = record();

    expect(await ExternalMaps.directions(lat: 0, lng: 0, name: 'x'), ExternalOpen.opened);
    expect(opened.map((u) => u.scheme).toList(), ['https']);
  });

  test('열 것이 하나도 없으면 unavailable — 화면이 "지도 앱을 열 수 없어요" 를 말할 수 있게', () async {
    ExternalMaps.canOpen = (_) async => false;
    ExternalMaps.launcher = (_) async => false;

    expect(await ExternalMaps.directions(lat: 0, lng: 0, name: 'x'), ExternalOpen.unavailable);
  });
}
