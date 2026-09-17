// 홈 안전 지수 카드 — 없으면 없고, 있으면 한 줄과 근거, 누르면 7초 룰 (#336).
//
// ## 여기서 재는 가장 중요한 것 (#682)
//
// **서버로 나가는 격자가 어디서 나왔는가.** 예전에는 단말이 잰 좌표에서 나왔다 — 위경도는
// 안 실렸지만 값의 출처가 기기의 관측이라, 원스토어 '수집정보' 의 "대략적인 위치 정보
// (3㎢ 이상 영역)" 에 그대로 들어맞았다. 지금은 **사용자가 목록에서 고른 행정동의 중심**
// 에서 나온다. 그래서 여기서는 나가는 nx·ny 를 **값으로** 잰다 — 격자가 붙었는지만 보면
// 엉뚱한 동네의 값이 그대로 통과한다.
import 'dart:convert';

import 'package:flutter/material.dart';
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

/// 진짜 자산(`assets/regions/hangjeongdong.json`)의 값 그대로다. 중심 좌표를 지어내면
/// 아래 nx·ny 도 지어낸 값이 되어, 이 검사가 자기 자신과만 맞는다.
const _wangsimni = Neighborhood(
  code: '1120052000',
  sigunguCode: '11200',
  sido: '서울특별시',
  sigungu: '성동구',
  dong: '왕십리2동',
  lat: 37.56146,
  lng: 127.02732,
);

/// 격자가 확실히 갈리는 먼 동네 — 부산이다.
const _udong = Neighborhood(
  code: '2635051000',
  sigunguCode: '26350',
  sido: '부산광역시',
  sigungu: '해운대구',
  dong: '우1동',
  lat: 35.17355,
  lng: 129.15594,
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

/// 동네 저장소. `save` 가 `PUT /auth/me` 를 치므로 목을 물린다 — 기기에 적고
/// `kNeighborhoodRev` 를 올리는 **운영과 같은 길**로 동네를 바꾸기 위해서다.
NeighborhoodStore _hood() => NeighborhoodStore(
      client: AuthedClient(
        inner: MockClient((_) async => http.Response('{"id":1}', 200,
            headers: const {'content-type': 'application/json; charset=utf-8'})),
        baseUrl: _base,
        store: _Tokens(),
      ),
      baseUrl: _base,
    );

Map<String, Object?> _body({double temp = 22}) => {
      'tempC': temp,
      'humidity': 49,
      'rain1hMm': 0.0,
      'precipType': 0,
      'pm10': null,
      'pm25': null,
      'station': null,
      'observedAt': '2026-09-07T05:10:00Z',
    };

({WalkSafetyRepository repo, List<Uri> calls}) _fixture({double temp = 22, int status = 200}) {
  final calls = <Uri>[];
  final client = MockClient((req) async {
    calls.add(req.url);
    return http.Response(
      jsonEncode(status == 200
          ? _body(temp: temp)
          : {'error': {'code': 'UPSTREAM', 'message': '지금 기상 정보를 받지 못했습니다.'}}),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return (
    repo: WalkSafetyRepository(client: client, baseUrl: _base, now: () => DateTime(2026, 9, 7, 14, 10)),
    calls: calls,
  );
}

/// 고른 동네가 있는 기기로 시작한다. `null` 이면 안 고른 사람이다.
void _seed(Neighborhood? mine) => SharedPreferences.setMockInitialValues(
      mine == null ? <String, Object>{} : {NeighborhoodStore.key: jsonEncode(mine.toJson())},
    );

Future<void> _pump(
  WidgetTester t,
  WalkSafetyRepository repo, {
  NeighborhoodStore? hood,
  Future<void> Function(BuildContext context)? onPick,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WalkSafetyCard(
        repository: repo,
        neighborhoods: hood ?? _hood(),
        now: () => DateTime(2026, 9, 7, 14, 10),
        onPick: onPick,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    _seed(_wangsimni);
    WalkSafetyStore.clear();
    kMyDog.value = null;
  });

  testWidgets('고른 동네의 중심에서 격자가 나온다 — 왕십리2동이면 nx=61 · ny=127', (t) async {
    final f = _fixture();
    await _pump(t, f.repo);

    final url = f.calls.single;
    expect(url.queryParameters, {'nx': '61', 'ny': '127'},
        reason: '동네 중심(37.56146, 127.02732)의 기상청 5km 격자다. 엉뚱한 값이면 '
            '단말 좌표가 다시 끼어든 것이다');
    expect(url.toString(), isNot(contains('37.5')));
    expect(url.toString(), isNot(contains('127.0')), reason: '위경도는 어디에도 안 실린다');
    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
  });

  testWidgets('동네를 안 고르면 요청이 한 번도 안 나가고 고르기 줄이 뜬다', (t) async {
    _seed(null);
    final f = _fixture();
    await _pump(t, f.repo);

    expect(f.calls, isEmpty, reason: '고른 동네가 없으면 보낼 격자도 없다');
    expect(find.byKey(const Key('walk-safety-pick-neighborhood')), findsOneWidget);
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('동네를 바꾸면 그 동네 격자로 다시 잰다 — 부산 우1동이면 nx=99 · ny=76', (t) async {
    final f = _fixture();
    final hood = _hood();
    await _pump(t, f.repo, hood: hood);
    expect(f.calls.single.queryParameters, {'nx': '61', 'ny': '127'});

    // 고르기 화면이 하는 일과 같은 것 — 기기에 적고 `kNeighborhoodRev` 를 올린다.
    await hood.save(_udong);
    await t.pumpAndSettle();

    expect(f.calls, hasLength(2), reason: '동네가 바뀌면 30분 TTL 을 건너뛴다 — 다른 하늘이다');
    expect(f.calls.last.queryParameters, {'nx': '99', 'ny': '76'});
  });

  testWidgets('서버가 503 이면 카드가 없다 — 가짜를 놓지 않는다', (t) async {
    await _pump(t, _fixture(status: 503).repo);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.textContaining('°C'), findsNothing);
    expect(find.byKey(const Key('walk-safety-pick-neighborhood')), findsNothing,
        reason: '동네는 골랐다 — 사용자가 할 수 있는 일이 없으면 비운다');
  });

  testWidgets('값이 오면 한 줄과 근거 — "지금 나가기 좋아요 · 22°C · 미세먼지는 못 받았어요"', (t) async {
    await _pump(t, _fixture().repo);

    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
    expect(find.text('22°C · 미세먼지는 못 받았어요'), findsOneWidget);
    expect(find.textContaining('24°C'), findsNothing, reason: '하드코딩이 아니다');
  });

  testWidgets('누르면 7초 룰과 시간대, 그리고 "참고" 라는 말이 뜬다', (t) async {
    await _pump(t, _fixture(temp: 31).repo);

    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
    await t.tap(find.text('지금은 피하고 저녁 7시 뒤에'));
    await t.pumpAndSettle();

    expect(find.textContaining('7초'), findsOneWidget);
    expect(find.textContaining('오전 10시 전'), findsOneWidget);
    expect(find.textContaining('참고 기준'), findsOneWidget);
    expect(find.text('습도 49%'), findsOneWidget);
  });

  testWidgets('22°C 가을 낮에는 아스팔트도 시간대도 안 나온다 — 조언 자리가 빈다 (#669)', (t) async {
    await _pump(t, _fixture().repo);

    await t.tap(find.text('지금 나가기 좋아요'));
    await t.pumpAndSettle();

    // 여기 세 줄이 `const` 이던 때는 22°C 에도 "아스팔트는 기온보다 최대 33°C" 가 떴다.
    expect(find.textContaining('아스팔트'), findsNothing);
    expect(find.textContaining('7초'), findsNothing);
    expect(find.textContaining('오전 10시 전'), findsNothing);
    expect(find.textContaining('단두종'), findsNothing);
    // 그래도 출처와 면책은 남는다 — 조언이 없다고 시트가 빈 것은 아니다.
    expect(find.textContaining('기상청 초단기실황'), findsOneWidget);
    expect(find.byKey(const Key('walk-safety-disclaimer')), findsOneWidget);
  });

  testWidgets('출처와 면책이 갈라져 있다 — 수의사 얘기가 날씨 문단에 안 붙는다 (#669)', (t) async {
    await _pump(t, _fixture().repo);

    await t.tap(find.text('지금 나가기 좋아요'));
    await t.pumpAndSettle();

    final source = t.widget<Text>(find.textContaining('기상청 초단기실황')).data!;
    expect(source, isNot(contains('수의사')));

    final notice = find.descendant(
      of: find.byKey(const Key('walk-safety-disclaimer')),
      matching: find.textContaining('수의사'),
    );
    expect(notice, findsOneWidget);
    expect(t.widget<Text>(notice).data, isNot(contains('기상청')));
  });

  testWidgets('아이가 바뀌면 같은 값으로 다시 판정한다 — 퍼그면 27°C 낮에 피하세요', (t) async {
    await _pump(t, _fixture(temp: 27).repo);
    expect(find.text('짧게 다녀오세요 · 바닥 7초 룰 확인'), findsOneWidget);

    kMyDog.value = const DogProfile(serverId: 2, name: 'Pug', breed: '퍼그', size: DogSize.small, ageMonths: 30);
    await t.pumpAndSettle();

    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
  });

  testWidgets('앱으로 돌아오면 다시 부른다 — 서버가 못 주던 자리', (t) async {
    var up = false;
    final repo = WalkSafetyRepository(
      client: MockClient((_) async => up
          ? http.Response(jsonEncode(_body()), 200,
              headers: const {'content-type': 'application/json; charset=utf-8'})
          : http.Response('{"error":{"code":"UPSTREAM"}}', 503,
              headers: const {'content-type': 'application/json; charset=utf-8'})),
      baseUrl: _base,
      now: () => DateTime(2026, 9, 7, 14, 10),
    );
    await _pump(t, repo);
    expect(find.textContaining('°C'), findsNothing);

    up = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
  });
}
