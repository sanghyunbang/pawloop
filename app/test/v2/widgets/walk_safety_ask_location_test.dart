// 설명 없이 권한을 묻지 않는다 — 이슈 #517.
//
// 예전에는 홈에 들어오는 순간 카드가 `LocationService.locate()` 를 불렀고, 그 안에서 OS
// 권한 대화상자가 떴다. 사용자는 **왜 묻는지 모르는 채** 대화상자를 만나고, 거기서 한 번
// 거부하면 안드로이드는 두 번째 거부에서 영구 거부로 굳힌다 — 그 뒤로는 앱이 다시 물을
// 수도 없다.
//
// 지금은 묻지 않고, 대신 **왜 카드가 없는지 말하고 길을 준다.** 누르면 설명 시트가 먼저다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_safety_card.dart';

WalkSafetyRepository _repo() => WalkSafetyRepository(
      client: MockClient((req) async => http.Response(
            jsonEncode({
              'tempC': 22.0,
              'humidity': 49,
              'rain1hMm': 0.0,
              'precipType': 0,
              'pm10': null,
              'pm25': null,
              'station': null,
              'observedAt': '2026-09-07T05:10:00Z',
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          )),
      baseUrl: 'https://api.example.test',
      now: () => DateTime(2026, 9, 7, 14, 10),
    );

LocationFix _fix() => LocationFix.found(Position(
      latitude: 37.5445,
      longitude: 127.0410,
      timestamp: DateTime(2026, 9, 7, 14, 10),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));

final _ask = find.byKey(const Key('walk-safety-ask-location'));

Future<void> _pump(
  WidgetTester t, {
  required Future<LocationFix> Function() locate,
  Future<bool> Function(BuildContext context)? onAskLocation,
  String? fontFamily,
}) async {
  await t.pumpWidget(MaterialApp(
    theme: fontFamily == null ? null : ThemeData(fontFamily: fontFamily),
    home: Scaffold(
      // 홈 화면이 이 카드를 좌우 22 여백 안에 둔다(today_screen.dart:250). 그 여백이 없으면
      // 글자가 쓸 폭이 실제보다 넓어져, 한 줄인지 재는 검사가 아무것도 못 잡는다.
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: WalkSafetyCard(
          repository: _repo(),
          locate: locate,
          now: () => DateTime(2026, 9, 7, 14, 10),
          onAskLocation: onAskLocation,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyStore.clear();
    kMyDog.value = null;
    LocationService.consented.value = false;
  });

  tearDown(() => LocationService.consented.value = false);

  testWidgets('권한이 없으면 "위치를 켜면…" 한 줄이 뜬다 — 카드가 말없이 사라지지 않는다', (t) async {
    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.denied),
        onAskLocation: (_) async => false);

    expect(_ask, findsOneWidget);
    expect(find.text('지금 산책하기 좋은지 알려드려요'), findsOneWidget);
    expect(find.textContaining('°C'), findsNothing);
  });

  // 360dp 폰에서 **한 줄**에 들어야 한다 (#658). 예전 문구는 마지막 '요' 한 글자만
  // 다음 줄로 떨어져 카드가 어색했다.
  //
  // 두 가지를 갖춰야 이 검사가 뜻을 가진다. 기본 표면(800dp)에서는 어떤 문구든 한 줄이라
  // 재도 소용없고, 테스트 폰트는 글자 하나가 폰트 크기만큼 넓어 실제보다 빨리 접힌다.
  // 그래서 폭을 360 으로 두고 **진짜 Pretendard** 를 물린다.
  testWidgets('그 한 줄이 360dp 에서 정말 한 줄이다 — 진짜 폰트로 잰다', (t) async {
    final loader = FontLoader('Pretendard');
    for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$w.otf'));
    }
    await loader.load();

    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.denied),
        onAskLocation: (_) async => false,
        fontFamily: 'Pretendard');

    final label = find.text('지금 산책하기 좋은지 알려드려요');
    expect(label, findsOneWidget);
    expect(t.getSize(label).height, lessThan(13.5 * 1.6),
        reason: '두 줄이 되면 마지막 글자만 떨어져 보인다 — 문구를 줄이거나 자리를 넓혀야 한다');
  });

  testWidgets('동의 전이면 안내를 안 띄운다 — 그건 동의 화면이 받는 자리다', (t) async {
    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.notConsented),
        onAskLocation: (_) async => true);

    expect(_ask, findsNothing);
  });

  testWidgets('사용자가 스스로 중단한 것에는 잔소리하지 않는다', (t) async {
    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.pausedByUser),
        onAskLocation: (_) async => true);

    expect(_ask, findsNothing);
  });

  testWidgets('"허용" 을 누르면 설명을 먼저 띄우는 손이 불리고, 허용되면 카드가 나온다', (t) async {
    var asked = 0;
    var allowed = false;
    await _pump(t,
        locate: () async => allowed ? _fix() : const LocationFix.denied(LocationDenial.denied),
        onAskLocation: (_) async {
          asked++;
          allowed = true;
          return true;
        });
    expect(_ask, findsOneWidget);

    await t.tap(find.text('허용'));
    await t.pumpAndSettle();

    expect(asked, 1, reason: 'OS 에 바로 묻지 않는다 — 설명하는 자리를 지난다');
    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
    expect(_ask, findsNothing);
  });

  testWidgets('안내 손을 안 꽂으면 줄도 안 그린다 — 누를 곳 없는 안내는 안 띄운다', (t) async {
    await _pump(t, locate: () async => const LocationFix.denied(LocationDenial.denied));

    expect(_ask, findsNothing);
  });
}
