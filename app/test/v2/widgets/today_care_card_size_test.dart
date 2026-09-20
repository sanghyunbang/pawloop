// "오늘의 케어" 칸 일곱이 **상태와 상관없이 같은 크기**인가 — 이슈 #561.
//
// ## 무엇이 있었나
//
// 칸마다 그리는 줄 수가 달랐다.
//
// | 상태 | 줄 |
// |:---|:---|
// | 아직 | 아이콘 · 라벨 · "아직" |
// | 했음 | 아이콘 · 라벨 · 이름 · 시각 |
// | 산책(거리 있음) | 아이콘 · 라벨 · 이름 · 시각 · **0.6km** |
//
// `Row` 는 가장 높은 칸에 맞춰 늘어나고 나머지는 가운데로 모이므로, 한 줄 안에서 칸들이
// 서로 다른 높이로 앉았다. 거리 한 줄이 그 줄 전체를 밀어 올렸다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'a';
  @override
  Future<String?> readRefreshToken() async => 'r';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body), status,
      headers: const {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _log({
  required int id,
  required String type,
  String who = 'CrewOwner',
  String at = '2026-09-15T10:39:00',
  String? memo,
}) =>
    {
      'id': id,
      'dogId': null,
      'groupId': 3,
      'type': type,
      'doneBy': {'userId': 11, 'nickname': who},
      'occurredAt': at,
      'memo': memo,
    };

FamilyRepository _repo(List<Map<String, Object?>> logs) => FamilyRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          if (request.url.path == '/api/groups/me') {
            return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
          }
          return _json(logs);
        }),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

/// 사장님 화면 그대로 — 물 · 산책(거리 있음) · 투약 · 배변 · 마킹은 했고 밥 · 병원은 아직.
List<Map<String, Object?>> _mixed() => [
      _log(id: 1, type: 'water'),
      _log(id: 2, type: 'walk', memo: '0.6km'),
      _log(id: 3, type: 'med', at: '2026-09-15T10:25:00'),
      _log(id: 4, type: 'poop'),
      _log(id: 5, type: 'pee'),
    ];

Future<List<double>> _cellHeights(WidgetTester t,
    {List<Map<String, Object?>>? logs, double textScale = 1.0}) async {
  // **진짜 기기 폭으로 잰다.** 1080dp 로 재면 칸이 250dp 씩이라 아무것도 안 넘치고,
  // 넘침을 잡으려고 만든 검사가 언제나 초록이 된다. 1170px ÷ 3 = 390dp 는 흔한 폭이다.
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  // **실제 배치대로 스크롤 안에 둔다**(#570). 홈은 `_fitOrScroll` 의 `SingleChildScrollView`,
  // 우리 가족 화면은 `ListView` 라 카드가 화면보다 길어도 넘치지 않는다. 안 감싸고 재면
  // "오늘 한 일" 이 붙은 카드가 2.0배에서 화면을 넘겨서, **호스트 탓인 넘침**이 칸의
  // 결함처럼 잡힌다.
  //
  // 그래도 이 테스트가 잡는 것은 그대로다 — **칸 안의** 넘침은 여전히 예외를 던지고,
  // 그게 #561 이 잡으려던 실패다(거리 한 줄이 칸을 밀어 올리던 것).
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SingleChildScrollView(
            child: TodayCareCard(repository: _repo(logs ?? _mixed()))),
      ),
    ),
  ));
  await t.pumpAndSettle();

  return kCareCardColumns
      .map((type) => t.getSize(find.byKey(Key('care-cell-${type.wire}'))).height)
      .toList();
}

void main() {
  testWidgets('칸 일곱이 전부 같은 높이다 — 한 칸이 자라면 그 줄이 통째로 들쑥날쑥해진다 (#561)',
      (t) async {
    final heights = await _cellHeights(t);

    expect(heights, hasLength(7));
    expect(heights.toSet(), hasLength(1),
        reason: '높이가 $heights 다. 거리 한 줄이 더 붙은 산책 칸이 그 줄을 밀어 올린다');
  });

  testWidgets('아무것도 안 한 아침에도 같은 높이다 — 기록할수록 카드가 자라면 안 된다', (t) async {
    final empty = await _cellHeights(t, logs: const []);
    final mixed = await _cellHeights(t);

    expect(empty.toSet(), hasLength(1));
    expect(empty.first, mixed.first,
        reason: '"아직" 과 "누가·언제" 가 같은 자리를 쓴다 — 한 번 누를 때마다 칸이 커지면 '
            '두 줄이 서로 다른 박자로 움직인다');
  });

  testWidgets('글자 2.0배에서도 같은 높이다 — 넘치지도 않는다', (t) async {
    final heights = await _cellHeights(t, textScale: 2.0);

    expect(t.takeException(), isNull);
    expect(heights.toSet(), hasLength(1), reason: '높이가 $heights 다');
  });

  testWidgets('불러오는 중 줄도 글자 2.0배에서 안 넘친다 — 잠깐이라 아무도 못 봤을 뿐이다 (#561)',
      (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);

    // 문을 열어 줄 때까지 응답을 안 주는 클라이언트 — 그동안 카드가 "불러오는 중" 에 머문다.
    final gate = Completer<void>();
    final client = AuthedClient(
      inner: MockClient((request) async {
        await gate.future;
        return request.url.path == '/api/groups/me'
            ? _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []})
            : _json(const []);
      }),
      baseUrl: _base,
      store: _Tokens(),
    );
    final repo = FamilyRepository(baseUrl: _base, client: client);
    // 카드가 #741 부터 오늘 일정도 읽는다 — 같은 문 뒤의 같은 목을 꽂는다. 안 꽂으면 기본
    // 저장소가 진짜 클라이언트로 나가고, 문을 연 직후 트리를 지우는 이 검사에는 그 요청의
    // 9초 타임아웃 타이머가 남아 "Timer is still pending" 으로 죽는다.
    final schedules = ScheduleRepository(baseUrl: _base, client: client);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Scaffold(
            body: TodayCareCard(repository: repo, scheduleRepository: schedules)),
      ),
    ));
    await t.pump();

    expect(find.textContaining('불러오는 중'), findsOneWidget);
    expect(t.takeException(), isNull,
        reason: '게스트 줄과 실패 줄은 Expanded 인데 이 줄만 아니었다 — 노란 줄무늬가 떴다');

    // 스피너의 애니메이션을 끊는다 — 안 끊으면 "Pending timers" 로 테스트가 죽는다.
    gate.complete();
    await t.pumpWidget(const SizedBox.shrink());
  });
}
