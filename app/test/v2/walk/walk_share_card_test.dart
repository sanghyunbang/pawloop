// 산책 공유 카드 — 이슈 #344.
//
// ## 여기서 재는 가장 중요한 것
//
// **양 끝이 잘렸는가.** 이 카드는 남에게 보내는 것이고 시작점은 대개 집 앞이다. 자르는
// 규칙은 코스 공개(#339)와 같은 `trimCourseEnds` 하나를 쓴다 — 두 벌이 되면 그중 하나가
// 언젠가 안 자른다.
//
// 그리고 **자를 것이 없으면 선을 안 그린다.** "짧으니까 그냥 그리자" 가 정확히 집 앞을
// 그리는 길이다.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/walk/walk_share.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';

/// 성수동에서 북쪽으로 [meters] m 쯤 뻗은 직선. 5m 간격이라 실제 트랙과 비슷하다.
List<List<double>> _line(double meters) {
  const step = 5.0;
  final n = (meters / step).round() + 1;
  return [for (var i = 0; i < n; i++) [127.0374, 37.5445 + i * step / 111000]];
}

WalkShareCard _card({List<List<double>>? path, String? place}) => WalkShareCard(
      dogName: '보리',
      accent: const Color(0xFFFF8F63),
      dateLabel: '2026.09.08 14:20 출발',
      distanceLabel: '1.2km',
      timeLabel: '00:24',
      paceLabel: "20'00\"",
      placeName: place,
      lngLat: path,
    );

void main() {
  group('양 끝 자르기', () {
    test('1km 를 걸으면 800m 만 남는다 — 앞뒤 100m 는 버린다', () {
      final card = _card(path: _line(1000));

      expect(card.hasRoute, isTrue);
      final trimmed = card.trimmedPath!;
      expect(trimmed.length, lessThan(_line(1000).length));
      // 첫 점이 원래 첫 점보다 북쪽이다 — 앞에서 잘렸다는 뜻.
      expect(trimmed.first[1], greaterThan(37.5445));
    });

    test('250m 짜리 산책은 선이 없다 — 자르고 남는 것이 100m 미만이다', () {
      final card = _card(path: _line(250));

      expect(card.hasRoute, isFalse,
          reason: '짧으니까 그냥 그리자는 것이 집 앞을 그리는 길이다');
    });

    test('서버에서 받은 기록에는 선이 아예 없다 — A안(#235)', () {
      expect(_card().hasRoute, isFalse);
      expect(_card(path: const []).hasRoute, isFalse);
    });
  });

  group('그림', () {
    test('선이 있는 카드가 PNG 로 나온다', () async {
      final png = await WalkShareImage.renderPng(_card(path: _line(1000)), size: const Size(300, 375));

      expect(png, isNotEmpty);
      // PNG 시그니처 — 다른 포맷이 나오면 공유 앱이 못 읽는다.
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });

    test('선이 없어도 카드가 나온다 — 숫자만 있는 한 장', () async {
      final png = await WalkShareImage.renderPng(_card(), size: const Size(300, 375));

      expect(png, isNotEmpty);
    });

    test('선이 있는 카드와 없는 카드는 다른 그림이다', () async {
      final withRoute = await WalkShareImage.renderPng(_card(path: _line(1000)), size: const Size(300, 375));
      final without = await WalkShareImage.renderPng(_card(), size: const Size(300, 375));

      expect(withRoute, isNot(equals(without)),
          reason: '같으면 선을 안 그리고 있는 것이다');
    });
  });

  group('공유', () {
    tearDown(WalkShare.resetForTest);

    test('카드를 그려 공유 시트에 넘긴다 — 곁들이는 글에 위치가 없다', () async {
      Uint8List? sent;
      String? text;
      String? name;
      WalkShare.sender = (png, n, t) async {
        sent = png;
        name = n;
        text = t;
      };

      await WalkShare.share(_card(path: _line(1000), place: '서울숲'));

      expect(sent, isNotEmpty);
      expect(name, endsWith('.png'));
      expect(text, '보리와 1.2km 걸었어요');
      expect(text, isNot(contains('서울숲')),
          reason: '위치는 카드 안에만 둔다 — 공유 앱 미리보기에 글만 남는 경우가 있다');
      expect(text, isNot(contains('14:20')), reason: '시각도 마찬가지다');
    });

    test('공유가 실패하면 WalkShareException 이다 — 화면이 문구를 고른다', () async {
      WalkShare.sender = (_, __, ___) async => throw StateError('공유 앱 없음');

      await expectLater(
        WalkShare.share(_card(path: _line(1000))),
        throwsA(isA<WalkShareException>()),
      );
    });
  });
}
