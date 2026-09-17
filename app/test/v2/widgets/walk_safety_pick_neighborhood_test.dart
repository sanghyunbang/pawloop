// 카드가 없을 때 무엇을 말하는가 — #517 이 세운 규칙, #682 가 옮긴 자리.
//
// ## 이 파일의 내력
//
// 처음에는 위치 권한 안내였다(#517). 홈에 들어오는 순간 카드가 `LocationService.locate()`
// 를 불렀고, 그 안에서 OS 권한 대화상자가 떴다 — 사용자는 **왜 묻는지 모르는 채** 만나고,
// 안드로이드는 두 번째 거부에서 영구 거부로 굳힌다. 그래서 묻지 않고 **왜 카드가 없는지
// 말하고 길을 주는** 줄을 그 자리에 뒀다.
//
// 지금 이 카드는 위치를 아예 안 쓴다(#682). 격자를 고른 동네의 중심에서 뽑기 때문이다.
// 그래서 그 자리가 말하는 것도 바뀌었다 — **동네를 고르러 가는 길**이다. 규칙은 그대로다:
// **"할 수 있는 일이 있으면 말하고, 없으면 비운다."**
//
// 파일 이름을 바꾼 것은 안내 줄이 사라져서가 아니라 무엇을 안내하는지가 바뀌어서다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/neighborhood_store.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/neighborhood.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_safety_card.dart';

const _base = 'https://api.example.test';

const _wangsimni = Neighborhood(
  code: '1120052000',
  sigunguCode: '11200',
  sido: '서울특별시',
  sigungu: '성동구',
  dong: '왕십리2동',
  lat: 37.56146,
  lng: 127.02732,
);

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT';
  @override
  Future<String?> readRefreshToken() async => 'RT';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

NeighborhoodStore _hood() => NeighborhoodStore(
      client: AuthedClient(
        inner: MockClient((_) async => http.Response('{"id":1}', 200,
            headers: const {'content-type': 'application/json; charset=utf-8'})),
        baseUrl: _base,
        store: _Tokens(),
      ),
      baseUrl: _base,
    );

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
      baseUrl: _base,
      now: () => DateTime(2026, 9, 7, 14, 10),
    );

final _pickRow = find.byKey(const Key('walk-safety-pick-neighborhood'));

void _seed(Neighborhood? mine) => SharedPreferences.setMockInitialValues(
      mine == null ? <String, Object>{} : {NeighborhoodStore.key: jsonEncode(mine.toJson())},
    );

Future<void> _pump(
  WidgetTester t, {
  NeighborhoodStore? hood,
  Future<void> Function(BuildContext context)? onPick,
  String? fontFamily,
}) async {
  await t.pumpWidget(MaterialApp(
    theme: fontFamily == null ? null : ThemeData(fontFamily: fontFamily),
    home: Scaffold(
      // 홈 화면이 이 카드를 좌우 22 여백 안에 둔다(today_screen.dart). 그 여백이 없으면
      // 글자가 쓸 폭이 실제보다 넓어져, 한 줄인지 재는 검사가 아무것도 못 잡는다.
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: WalkSafetyCard(
          repository: _repo(),
          neighborhoods: hood ?? _hood(),
          now: () => DateTime(2026, 9, 7, 14, 10),
          onPick: onPick,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    _seed(null);
    WalkSafetyStore.clear();
    kMyDog.value = null;
  });

  testWidgets('동네를 안 골랐으면 한 줄이 뜬다 — 카드가 말없이 사라지지 않는다', (t) async {
    await _pump(t);

    expect(_pickRow, findsOneWidget);
    expect(find.text('산책하기 좋은지 알려드려요'), findsOneWidget);
    expect(find.text('동네 고르기'), findsOneWidget);
    expect(find.textContaining('°C'), findsNothing);
  });

  // 360dp 폰에서 **한 줄**에 들어야 한다 (#658 에서 배운 것이다). 예전 문구는 마지막 '요'
  // 한 글자만 다음 줄로 떨어져 카드가 어색했다.
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

    await _pump(t, fontFamily: 'Pretendard');

    final label = find.text('산책하기 좋은지 알려드려요');
    expect(label, findsOneWidget);
    expect(t.getSize(label).height, lessThan(13.5 * 1.6),
        reason: '두 줄이 되면 마지막 글자만 떨어져 보인다 — 문구를 줄이거나 버튼 글자를 줄여야 한다');
    // 버튼도 같이 잰다. 두 글자('허용')에서 다섯 글자로 늘린 자리라, 버튼이 접히면
    // 위의 한 줄 검사만으로는 안 걸린다.
    expect(t.getSize(find.text('동네 고르기')).height, lessThan(13.5 * 1.6));
  });

  testWidgets('"동네 고르기" 를 누르면 고르는 화면으로 간다', (t) async {
    var opened = 0;
    await _pump(t, onPick: (_) async => opened++);

    await t.tap(find.text('동네 고르기'));
    await t.pumpAndSettle();

    expect(opened, 1, reason: '누를 곳이 없는 안내는 안내가 아니다');
  });

  testWidgets('동네가 있으면 이 줄은 없다 — 고른 사람에게 또 고르라고 하지 않는다', (t) async {
    _seed(_wangsimni);
    await _pump(t);

    expect(_pickRow, findsNothing);
    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
  });

  testWidgets('고르고 나면 줄이 사라지고 지수가 그 자리에 온다', (t) async {
    final hood = _hood();
    await _pump(t, hood: hood, onPick: (_) async => hood.save(_wangsimni));
    expect(_pickRow, findsOneWidget);

    await t.tap(find.text('동네 고르기'));
    await t.pumpAndSettle();

    expect(_pickRow, findsNothing);
    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
  });
}
