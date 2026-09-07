// 급할 때 — 가까운 병원 셋, 전화 버튼, 위치가 없을 때 (#337).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/emergency_vets_sheet.dart';
import 'package:heat_trip_flutter/v2/widgets/vet_badge.dart';

PetPlace _vet(String title, {double dist = 100, String tel = '02-1234-5678'}) => PetPlace(
      contentId: title,
      title: title,
      source: 'vet',
      category: 'vet',
      contentTypeId: '',
      addr: '서울특별시 성동구 뚝섬로 273',
      image: '',
      tel: tel,
      lat: 37.5445,
      lng: 127.0410,
      distM: dist,
    );

/// 홈의 "급할 때" 를 눌렀을 때와 같은 길로 연다 — 위치와 목록을 꽂는다.
Future<void> _open(
  WidgetTester t, {
  required List<PetPlace> places,
  bool located = true,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => EmergencyVets.open(
            context,
            locate: () async => located ? (lat: 37.5445, lng: 127.0410) : null,
            load: (lat, lng) async => places,
          ),
          child: const Text('열기'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
}

void main() {
  final launched = <Uri>[];
  final original = ExternalMaps.launcher;

  setUp(() {
    launched.clear();
    ExternalMaps.launcher = (uri) async {
      launched.add(uri);
      return true;
    };
  });

  tearDown(() => ExternalMaps.launcher = original);

  testWidgets('가까운 셋만 보여 준다 — 넷째는 없다', (t) async {
    await _open(t, places: [
      _vet('가까운 병원', dist: 120),
      _vet('중간 병원', dist: 400),
      _vet('먼 병원', dist: 900),
      _vet('더 먼 병원', dist: 1500),
    ]);

    expect(find.text('가까운 병원'), findsOneWidget);
    expect(find.text('중간 병원'), findsOneWidget);
    expect(find.text('먼 병원'), findsOneWidget);
    expect(find.text('더 먼 병원'), findsNothing);
  });

  testWidgets('전화 버튼이 tel: 로 건다 — 급할 때 필요한 것은 목록이 아니라 전화다', (t) async {
    await _open(t, places: [_vet('서울숲동물병원', tel: '02-123-4567')]);

    await t.tap(find.byIcon(Icons.call_rounded));
    await t.pumpAndSettle();

    expect(launched, hasLength(1));
    expect(launched.single.scheme, 'tel');
    expect(launched.single.path, '021234567');
  });

  testWidgets('이름에 24시가 있으면 배지 — "이름 기준" 이라고 함께 적는다', (t) async {
    await _open(t, places: [_vet('24시 성수동물의료센터'), _vet('행복한 동물병원')]);

    expect(find.byType(VetTwentyFourBadge), findsOneWidget);
    expect(find.text(VetTwentyFourBadge.label), findsOneWidget);
  });

  testWidgets('위치가 없으면 목록 대신 켜 달라고 말한다 — 빈 목록을 가까운 곳인 척하지 않는다', (t) async {
    await _open(t, places: [_vet('가까운 병원')], located: false);

    expect(find.textContaining('위치를 켜면'), findsOneWidget);
    expect(find.text('가까운 병원'), findsNothing);
  });

  testWidgets('위치는 있는데 병원이 없으면 지도 탭으로 안내한다', (t) async {
    await _open(t, places: const []);

    expect(find.textContaining('못 찾았어요'), findsOneWidget);
  });
}
