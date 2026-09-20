// 급할 때 — 가까운 병원 셋, 전화 버튼, 위치가 없을 때 (#337).
// 그리고 **바로 열리는가 · 한 장만 뜨는가** (#663).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/emergency_vets_sheet.dart';
import 'package:heat_trip_flutter/v2/widgets/place_sheet.dart';
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
///
/// [failure] 를 주면 목록 대신 그 실패를 던진다 — 저장소가 실패를 말하는 길(#515).
Future<void> _open(
  WidgetTester t, {
  required List<PetPlace> places,
  bool located = true,
  PlaceFailure? failure,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => EmergencyVets.open(
            context,
            locate: () async => located ? (lat: 37.5445, lng: 127.0410) : null,
            load: (lat, lng) async {
              if (failure != null) throw failure;
              return places;
            },
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
  final originalCanOpen = ExternalMaps.canOpen;

  setUp(() {
    launched.clear();
    // 네이버 지도가 "있다" 고 답하는 기기로 둔다 — 안 그러면 길찾기가 웹으로 간다(2026-09-21).
    ExternalMaps.canOpen = (_) async => true;
    ExternalMaps.launcher = (uri) async {
      launched.add(uri);
      return true;
    };
  });

  tearDown(() {
    ExternalMaps.launcher = original;
    ExternalMaps.canOpen = originalCanOpen;
  });

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

  // ───────────── 못 받은 것과 없는 것은 다르다 (#515) ─────────────

  testWidgets('목록을 못 받으면 "못 받았어요" 다 — 급할 때 "못 찾았어요" 는 거짓말이다', (t) async {
    await _open(t, places: const [], failure: const PlaceFailure(PlaceFailureKind.network));

    expect(find.byKey(const Key('emergency-vets-empty')), findsOneWidget);
    expect(find.textContaining('목록을 못 받았어요'), findsOneWidget);
    expect(find.textContaining('가까운 병원을 못 찾았어요'), findsNothing,
        reason: '못 받은 것을 "없다" 로 말하면 사람이 병원이 없다고 믿고 다른 길을 찾는다');
  });

  testWidgets('정말 없을 때는 예전 문구 그대로다', (t) async {
    await _open(t, places: const []);

    expect(find.textContaining('가까운 병원을 못 찾았어요'), findsOneWidget);
    expect(find.textContaining('목록을 못 받았어요'), findsNothing);
  });

  // ───────────── 바로 열리는가 · 한 장만 뜨는가 (#663) ─────────────

  testWidgets('누르면 위치를 기다리지 않고 바로 열린다 — 찾는 중이라고 말한다', (t) async {
    // 위치를 **영영 안 주는** 상황을 만든다. 예전 코드는 이 동안 시트를 아예 안 열었고,
    // 그래서 화면에 아무 변화가 없었다. 실기기에서는 GPS 를 잡는 몇 초가 이 상태다.
    final stuck = Completer<({double lat, double lng})?>();
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    unawaited(EmergencyVets.open(
      ctx,
      locate: () => stuck.future,
      load: (lat, lng) async => [_vet('가까운 병원')],
    ));
    // 시트가 뜨는 데 필요한 만큼만 돌린다. pumpAndSettle 은 위치를 영영 안 주므로 못 쓴다.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(find.byType(EmergencyVetsSheet), findsOneWidget,
        reason: '위치를 못 잡은 동안에도 시트는 이미 떠 있어야 한다 — 그게 이 이슈다');
    expect(find.byKey(const Key('emergency-vets-searching')), findsOneWidget);
    expect(find.textContaining('못 찾았어요'), findsNothing,
        reason: '아직 안 찾아봤다. 찾는 중을 "없어요" 로 말하면 안 된다');

    stuck.complete((lat: 37.5445, lng: 127.0410));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('emergency-vets-searching')), findsNothing);
    expect(find.text('가까운 병원'), findsOneWidget);
  });

  testWidgets('연타해도 시트는 한 장이다 — 예전에는 누른 만큼 겹쳐서 그만큼 닫아야 했다', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    // 세 번의 탭이 **한 프레임 안에** 들어온 상황. 시트가 그려지기 전이라 두 번째·세 번째
    // 탭은 아직 막을 것이 화면에 없다 — 자물쇠가 없으면 셋 다 끝까지 달린다.
    for (var i = 0; i < 3; i++) {
      unawaited(EmergencyVets.open(
        ctx,
        locate: () async => (lat: 37.5445, lng: 127.0410),
        load: (lat, lng) async => [_vet('가까운 병원')],
      ));
    }
    await t.pumpAndSettle();

    expect(find.byType(EmergencyVetsSheet), findsOneWidget,
        reason: '세 번 눌렀으면 예전에는 세 장이 겹쳤다');
  });

  testWidgets('닫고 다시 누르면 또 열린다 — 자물쇠가 안 풀리면 영영 안 열린다', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    Future<void> openOnce() => EmergencyVets.open(
          ctx,
          locate: () async => (lat: 37.5445, lng: 127.0410),
          load: (lat, lng) async => [_vet('가까운 병원')],
        );

    unawaited(openOnce());
    await t.pumpAndSettle();
    expect(find.byType(EmergencyVetsSheet), findsOneWidget);

    Navigator.of(ctx).pop();
    await t.pumpAndSettle();
    expect(find.byType(EmergencyVetsSheet), findsNothing);

    unawaited(openOnce());
    await t.pumpAndSettle();
    expect(find.byType(EmergencyVetsSheet), findsOneWidget);
  });

  // ───────────── 병원 카드를 누르면 상세가 열린다 (#664) ─────────────

  testWidgets('병원 카드를 누르면 상세가 열린다 — 예전에는 눌러도 아무 일도 안 났다', (t) async {
    await _open(t, places: [_vet('서울숲동물병원')]);

    await t.tap(find.text('서울숲동물병원'));
    await t.pumpAndSettle();

    expect(find.byType(PlaceSheet), findsOneWidget);
    // 지도 탭과 같은 상세다 — 주소와 길찾기가 거기 있다.
    expect(find.text('서울특별시 성동구 뚝섬로 273'), findsOneWidget);
    expect(find.byKey(const Key('place-action-길찾기')), findsOneWidget);
  });

  testWidgets('길찾기가 지도 앱을 연다 — 급할 때 주소를 손으로 옮겨 적지 않는다', (t) async {
    await _open(t, places: [_vet('서울숲동물병원')]);
    await t.tap(find.text('서울숲동물병원'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('place-action-길찾기')));
    await t.pumpAndSettle();

    expect(launched, isNotEmpty);
    expect(launched.first.toString(), contains('37.5445'));
  });

  testWidgets('전화 버튼은 상세를 거치지 않는다 — 홈에서 두 번 만에 전화다 (#337)', (t) async {
    await _open(t, places: [_vet('서울숲동물병원', tel: '02-123-4567')]);

    await t.tap(find.byIcon(Icons.call_rounded));
    await t.pumpAndSettle();

    expect(find.byType(PlaceSheet), findsNothing,
        reason: '전화가 한 단계 멀어지면 이 시트의 뜻이 달라진다');
    expect(launched.single.scheme, 'tel');
  });

  testWidgets('영업시간을 지어내지 않는다 — 우리에게 그 데이터가 없다', (t) async {
    await _open(t, places: [_vet('행복한 동물병원')]);
    await t.tap(find.text('행복한 동물병원'));
    await t.pumpAndSettle();

    expect(find.textContaining('영업'), findsNothing);
    expect(find.textContaining('진료시간'), findsNothing);
  });
}
