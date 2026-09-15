// 지도 탐색 — 시트의 주 동작 · 산책로 머리와 먼 코스 안내 · 자리표시 카드 (#328).
//
// 리스트 뷰만 세운다(지도 SDK 는 테스트에 없다). 전화·길찾기는 `ExternalMaps.launcher` 를
// 갈아 끼워 어느 URI 를 열었는지 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

PetPlace _place(
  String id,
  String title, {
  String source = 'kto',
  String category = '',
  String contentTypeId = '',
  String tel = '',
  double distM = 0,
}) =>
    PetPlace(
      contentId: id,
      title: title,
      source: source,
      category: category,
      contentTypeId: contentTypeId,
      addr: '서울특별시 성동구',
      image: '',
      tel: tel,
      lat: 37.5445,
      lng: 127.0374,
      distM: distM,
    );

class _FakeRepo extends PetPlacesRepository {
  _FakeRepo()
      : super(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://unused',
        );

  @override
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async =>
      switch (contentTypeId) {
        'trail' => [
            // 동네 길(#346) — 관리기관 전화번호가 있고 선이 없다.
            _place('trail:lt9766bc9af8', '3.1운동길B',
                source: 'trail', category: 'trail', tel: '02-2148-1855', distM: 407),
            _place('trail:41', 'DMZ 평화의 길 4-1코스', source: 'trail', category: 'trail', distM: 19800),
          ],
        'vet' => [
            _place('vet:1', '성수 숲속 피부과 동물병원', source: 'vet', category: 'vet', tel: '02-123-4567', distM: 327),
          ],
        _ => [
            _place('vet:1', '성수 숲속 피부과 동물병원', source: 'vet', category: 'vet', tel: '02-123-4567', distM: 327),
            _place('100', '서울숲', contentTypeId: '12', distM: 354),
            _place('101', '문리', contentTypeId: '38', distM: 263),
          ],
      };
}

Finder _chip(String label) => find.text(label).first;

Future<void> _pumpWide(WidgetTester tester, Widget child, {double? width}) async {
  tester.view.physicalSize = width == null ? const Size(1600, 1200) : Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = width == null ? 1.0 : 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  // 지도가 내 동네를 기기에서 읽는다(#342). 목을 안 깔면 그 읽기가 안 끝나
  // 화면이 멈춘다 — pumpAndSettle 이 시간 초과로 죽는다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final original = ExternalMaps.launcher;
  tearDown(() => ExternalMaps.launcher = original);

  testWidgets('자리표시 "우리 동네 업체 자리" 카드가 없다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    expect(find.text('우리 동네 업체 자리'), findsNothing);
    expect(find.textContaining('제휴'), findsNothing);
    expect(find.textContaining('반려동반 가능 · 3곳'), findsOneWidget);
  });

  testWidgets('병원 시트: 전화 · 길찾기가 먼저, 글쓰기는 그 아래 — 전화는 tel: 을 연다', (tester) async {
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return true;
    };
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.tap(find.text('성수 숲속 피부과 동물병원'));
    await tester.pumpAndSettle();

    expect(find.text('전화'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('이 장소로 글쓰기'), findsOneWidget);
    expect(find.text('지도에서 보기'), findsNothing, reason: '병원은 선이 없다');

    await tester.tap(find.text('전화'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'tel:021234567');

    await tester.tap(find.text('길찾기'));
    await tester.pumpAndSettle();
    expect(opened.last.scheme, 'nmap');
    expect(opened.last.queryParameters['dname'], '성수 숲속 피부과 동물병원');
  });

  testWidgets('산책로 칩: 머리가 "가까운 산책로" 이고 8km 밖이면 그 말을 한다, 시트엔 지도에서 보기', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    expect(find.textContaining('가까운 산책로 · 2곳'), findsOneWidget);
    expect(find.textContaining('반려동반 가능 ·'), findsNothing);
    // 첫 항목이 407m 라 먼 코스 안내는 없다 — 목록은 거리순이다(#321).
    expect(find.textContaining('가장 가까운 코스는'), findsNothing);

    await tester.tap(find.text('DMZ 평화의 길 4-1코스'));
    await tester.pumpAndSettle();
    expect(find.text('지도에서 보기'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('전화'), findsNothing);
  });

  testWidgets('가까운 코스가 8km 안이면 안내가 없다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.tap(_chip('동물병원'));
    await tester.pumpAndSettle();

    expect(find.textContaining('동물병원 · 1곳'), findsOneWidget);
    expect(find.textContaining('밖이에요'), findsNothing);
  });

  testWidgets('동네 길 시트에는 "지도에서 보기" 가 없다 — 그릴 선이 없다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    // 원본(전국길관광정보표준데이터)에는 좌표가 없고 경로가 글이다. 눌러도 서버가
    // 404 를 준다 — 2026-09-08 에뮬레이터에서 실제로 그랬다.
    expect(find.text('지도에서 보기'), findsNothing);
    expect(find.text('전화'), findsOneWidget, reason: '관리기관 전화번호는 있다');
    expect(find.text('여기서 산책 시작'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('동네 길 · 지자체(공공데이터포털)'), findsOneWidget,
        reason: '두루누비라고 적으면 출처가 거짓이다');
  });

  testWidgets('두루누비 시트에는 그대로 "지도에서 보기" 가 있다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DMZ 평화의 길 4-1코스'));
    await tester.pumpAndSettle();

    expect(find.text('지도에서 보기'), findsOneWidget);
    expect(find.text('걷기여행길 · 두루누비(한국관광공사)'), findsOneWidget);
  });

  testWidgets('버튼이 넷이어도 393dp 에서 안 넘친다 — 자르지 않고 줄여 넣는다', (tester) async {
    // 칩까지는 넓은 화면에서 간다 — 393dp 에서는 칩 줄이 가로로 잘려 '산책로' 가
    // 아직 만들어지지도 않는다(가로 ListView 는 보이는 것만 짓는다).
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    // 시트를 열기 직전에만 좁힌다. 시트는 화면 폭을 그대로 쓴다.
    tester.view.physicalSize = const Size(393 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    expect(find.text('여기서 산책 시작'), findsOneWidget);
    expect(find.text('전화'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '동네 길은 전화번호가 있어 버튼이 하나 더 선다 — 393dp 에서 28px 넘쳤다');
  });

  testWidgets('버튼 여백이 셋 다 같다 — 긴 이름만 모서리에 닿으면 안 된다 (#535)', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(393 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    /// 칸의 왼쪽 끝부터 아이콘까지 · 글자 끝부터 칸의 오른쪽 끝까지.
    ({double left, double right}) padding(String label) {
      final box = find.byKey(Key('place-action-$label'));
      expect(box, findsOneWidget, reason: '$label 칸을 못 찾았다');
      final outer = tester.getRect(box);
      final icon = tester.getRect(find.descendant(of: box, matching: find.byType(Icon)));
      final text = tester.getRect(find.descendant(of: box, matching: find.byType(Text)));
      return (left: icon.left - outer.left, right: outer.right - text.right);
    }

    final pads = {for (final l in ['여기서 산책 시작', '전화', '길찾기']) l: padding(l)};

    for (final e in pads.entries) {
      expect(e.value.left, greaterThan(4),
          reason: '${e.key} 의 글자가 모서리에 닿는다 — 폭을 똑같이 나누면 긴 이름부터 그렇게 된다');
      expect(e.value.left, closeTo(e.value.right, 1.0),
          reason: '${e.key} 의 좌우가 다르다');
    }
    final first = pads['여기서 산책 시작']!.left;
    for (final e in pads.entries) {
      expect(e.value.left, closeTo(first, 1.0),
          reason: '한 줄에 선 칸들의 여백이 서로 다르면 한 칸만 꽉 차 보인다 — '
              '지금 ${pads.map((k, v) => MapEntry(k, v.left.toStringAsFixed(1)))}');
    }
  });

  testWidgets('이름이 길면 칸도 넓다 — 폭을 똑같이 나누지 않는다 (#535)', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(393 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    double widthOf(String label) => tester.getSize(find.byKey(Key('place-action-$label'))).width;

    expect(widthOf('여기서 산책 시작'), greaterThan(widthOf('길찾기')));
    expect(widthOf('길찾기'), greaterThan(widthOf('전화')),
        reason: '세 글자가 두 글자보다 넓어야 한다 — 같으면 폭을 n등분하고 있는 것이다');
  });
}
