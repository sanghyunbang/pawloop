// 동네 고르기 화면 — 이슈 #342.
//
// 세 단계와 검색을 함께 두는 이유가 "둘 중 하나만 두면 반대쪽 사람이 헤맨다" 라서,
// 두 길이 **각각 끝까지 간다**는 것을 잰다. "현재 위치로 찾기" 는 후보만 주고 고르는 것은
// 사람이라는 것도 여기서 잠근다 — 자동으로 정하면 중심점 거리 때문에 옆 동이 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/neighborhood_store.dart';
import 'package:heat_trip_flutter/v2/data/region_catalog.dart';
import 'package:heat_trip_flutter/v2/screens/neighborhood_picker_screen.dart';

const _sample = '''
{
 "version":"test",
 "source":"통계청 SGIS 행정동 경계 · CC BY 4.0",
 "sido":[{"c":"11","n":"서울특별시"},{"c":"26","n":"부산광역시"}],
 "sigungu":[{"c":"11200","s":"11","n":"성동구"},{"c":"26110","s":"26","n":"중구"}],
 "dong":[
   {"c":"1120052000","g":"11200","n":"왕십리2동","lat":37.56146,"lng":127.02732},
   {"c":"1120068000","g":"11200","n":"성수1가제1동","lat":37.54554,"lng":127.04425},
   {"c":"2611051000","g":"26110","n":"중앙동","lat":35.10175,"lng":129.03528}]
}
''';

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

NeighborhoodStore _store(List<http.Request> sent) => NeighborhoodStore(
      client: AuthedClient(
        inner: MockClient((request) async {
          sent.add(request);
          return http.Response('{"id":1}', 200,
              headers: const {'content-type': 'application/json; charset=utf-8'});
        }),
        baseUrl: 'https://api.example.test',
        store: _Tokens(),
      ),
      baseUrl: 'https://api.example.test',
    );

Future<List<http.Request>> _pump(
  WidgetTester tester, {
  Future<({double lat, double lng})?> Function()? locate,
}) async {
  final sent = <http.Request>[];
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: NeighborhoodPickerScreen(
      catalog: RegionCatalog.parse(_sample),
      store: _store(sent),
      locate: locate,
    ),
  ));
  await tester.pumpAndSettle();
  return sent;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('시도 → 시군구 → 동 세 단계로 고른다', (tester) async {
    final sent = await _pump(tester);

    expect(find.text('어느 시·도인가요'), findsOneWidget);
    await tester.tap(find.text('서울특별시'));
    await tester.pumpAndSettle();

    expect(find.text('어느 시·군·구인가요'), findsOneWidget);
    await tester.tap(find.text('성동구'));
    await tester.pumpAndSettle();

    expect(find.text('어느 동인가요'), findsOneWidget);
    await tester.tap(find.text('성동구 성수1가제1동'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: '고르면 그 자리에서 저장한다');
    expect(await NeighborhoodStore(client: null).read(), isNotNull);
  });

  testWidgets('검색만으로도 끝까지 간다 — 단계를 안 밟아도 된다', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), '성수');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과'), findsOneWidget);
    expect(find.text('성동구 성수1가제1동'), findsOneWidget);
    expect(find.text('어느 시·도인가요'), findsNothing,
        reason: '검색 중에는 단계 목록이 자리를 비켜 준다');
  });

  testWidgets('현재 위치로 찾기는 후보만 준다 — 고르는 것은 사람이다', (tester) async {
    final sent = await _pump(tester, locate: () async => (lat: 37.5455, lng: 127.0443));

    await tester.tap(find.text('현재 위치로 찾기'));
    await tester.pumpAndSettle();

    expect(find.text('현재 위치 근처'), findsOneWidget);
    expect(find.text('성동구 성수1가제1동'), findsOneWidget);
    expect(sent, isEmpty,
        reason: '후보를 띄웠을 뿐이다 — 자동으로 정하면 중심점 거리 때문에 옆 동이 된다');
  });

  testWidgets('위치를 못 잡아도 목록으로 고를 수 있다', (tester) async {
    await _pump(tester, locate: () async => null);

    await tester.tap(find.text('현재 위치로 찾기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('위치를 잡지 못했어요'), findsOneWidget);
    expect(find.text('어느 시·도인가요'), findsOneWidget);
  });

  testWidgets('출처 한 줄이 화면에 있다 — CC BY 4.0 이 요구한다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('SGIS'), findsOneWidget);
    expect(find.textContaining('CC BY'), findsOneWidget);
  });

  testWidgets('좌표는 화면 밖으로 안 나간다 — 요청 본문에 코드만 있다', (tester) async {
    final sent = await _pump(tester, locate: () async => (lat: 37.5455, lng: 127.0443));

    await tester.tap(find.text('현재 위치로 찾기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('성동구 성수1가제1동'));
    await tester.pumpAndSettle();

    expect(sent.single.body, contains('1120068000'));
    expect(sent.single.body, isNot(contains('37.5')));
    expect(sent.single.body, isNot(contains('127.0')));
  });
}
