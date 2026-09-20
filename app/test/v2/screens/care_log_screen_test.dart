// 케어 기록 — 날짜별 화면. 이슈 #737.
//
// 진짜 `FamilyRepository` 에 `MockClient`. 여기서 재는 것.
//   - 서버에 **그날**을 `?date=` 로 묻는다 · 아이별로 묶고 · 묶음 안은 이른 것부터
//   - 요약 줄은 건수와 항목별 수
//   - ‹ 는 어제, › 는 오늘을 넘지 않는다
//   - 없는 날 · 실패 · 항목 목록을 못 읽은 날
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/care_log_screen.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';
  @override
  Future<String?> readRefreshToken() async => 'refresh-token';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _item(int id, String name, String icon, String? type, int order) => {
      'id': id,
      'dogId': null,
      'name': name,
      'icon': icon,
      'systemType': type,
      'dailyTarget': null,
      'sortOrder': order,
      'archivedAt': null,
    };

final _items = [
  _item(1, '물', 'water', 'water', 1),
  _item(2, '밥', 'meal', 'meal', 2),
  _item(3, '병원', 'vet', 'vet', 3),
  _item(9, '양치', 'tooth', null, 4),
];

Map<String, Object?> _log({
  required int id,
  required String? type,
  required int careItemId,
  required String who,
  required String at,
  int? dogId,
  int userId = 11,
}) =>
    {
      'id': id,
      'dogId': dogId,
      'groupId': 3,
      'careItemId': careItemId,
      'type': type,
      'doneBy': {'userId': userId, 'nickname': who},
      'occurredAt': at,
      'memo': null,
    };

/// 9월 20일 — 보리 밥(07:30 CrewOwner) · 뭉치 물(08:50 CrewMate) · 뭉치 병원(11:26 CrewOwner) ·
/// 아이 없는 양치(12:00 CrewMate).
///
/// **일부러 시각 순이 아니다** — 화면이 서버 순서에 기대지 않고 스스로 이른 것부터 놓는지를 잰다.
final _sunday = [
  _log(id: 3, type: 'vet', careItemId: 3, who: 'CrewOwner', at: '2026-09-20T11:26:00', dogId: 8),
  _log(id: 2, type: 'water', careItemId: 1, who: 'CrewMate', at: '2026-09-20T08:50:00', dogId: 8),
  _log(id: 1, type: 'meal', careItemId: 2, who: 'CrewOwner', at: '2026-09-20T07:30:00', dogId: 7),
  _log(id: 4, type: null, careItemId: 9, who: 'CrewMate', at: '2026-09-20T12:00:00'),
];

class _Fixture {
  final FamilyRepository repo;
  final List<http.Request> requests;
  _Fixture(this.repo, this.requests);
}

_Fixture _fixture({
  Map<String, List<Map<String, Object?>>> logsByDate = const {},
  int logsStatus = 200,
  int itemsStatus = 200,
}) {
  final requests = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path == '/api/groups/3/care-items') {
        return itemsStatus == 200 ? _json(_items) : _json({'error': {}}, status: itemsStatus);
      }
      if (path == '/api/groups/3/care-logs') {
        if (logsStatus != 200) return _json({'error': {}}, status: logsStatus);
        return _json(logsByDate[request.url.queryParameters['date']] ?? const []);
      }
      return _json(const []);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return _Fixture(FamilyRepository(baseUrl: _base, client: client), requests);
}

Iterable<http.Request> _logRequests(_Fixture f) =>
    f.requests.where((r) => r.url.path == '/api/groups/3/care-logs');

Future<void> _pump(WidgetTester tester, _Fixture f) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: CareLogScreen(groupId: 3, repository: f.repo, today: DateTime(2026, 9, 20)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    kMyPets.value = const [
      DogProfile(name: '보리', serverId: 7, breed: '푸들', size: DogSize.small, ageMonths: 30),
      DogProfile(name: '뭉치', serverId: 8, breed: '시바', size: DogSize.medium, ageMonths: 48),
    ];
  });
  tearDown(() => kMyPets.value = const []);

  test('CareLogEntry 가 어느 아이의 기록인지를 읽는다 — 없으면 null', () {
    expect(CareLogEntry.tryParse(_sunday[0])!.dogId, 8);
    expect(CareLogEntry.tryParse(_sunday[3])!.dogId, isNull);
  });

  testWidgets('오늘을 ?date= 로 묻고, 아이별로 묶어 이른 것부터 그린다 — 요약 줄은 건수와 항목별 수',
      (tester) async {
    final f = _fixture(logsByDate: {'2026-09-20': _sunday});
    await _pump(tester, f);

    expect(_logRequests(f).single.url.queryParameters['date'], '2026-09-20');
    expect(_logRequests(f).single.url.queryParameters.containsKey('dogId'), isFalse,
        reason: '가족의 하루라 어느 아이 것이든 다 온다');

    expect(find.text('오늘 · 9월 20일 (일)'), findsOneWidget);
    expect(find.text('4건 · 물 1 · 밥 1 · 병원 1 · 양치 1'), findsOneWidget,
        reason: '항목 순서는 그 집이 카드에 늘어놓은 순서');

    // 아이별 묶음 — 내 아이 순서(보리 → 뭉치), 아이 안 적힌 것은 맨 끝.
    Offset top(Key key) => tester.getTopLeft(find.byKey(key));
    expect(find.byKey(const Key('care-log-dog-7')), findsOneWidget);
    expect(find.byKey(const Key('care-log-dog-8')), findsOneWidget);
    expect(find.byKey(const Key('care-log-dog-none')), findsOneWidget);
    expect(find.text('아이 안 정함'), findsOneWidget);
    expect(top(const Key('care-log-dog-7')).dy, lessThan(top(const Key('care-log-dog-8')).dy));
    expect(top(const Key('care-log-dog-8')).dy, lessThan(top(const Key('care-log-dog-none')).dy));

    // 묶음 안은 이른 것부터 — 뭉치의 08:50 물이 11:26 병원 위에.
    expect(top(const Key('care-log-line-2')).dy, lessThan(top(const Key('care-log-line-3')).dy),
        reason: '하루를 아침부터 밤으로 읽는다 — 홈 카드(최근 순)와 반대다');
    expect(find.text('08:50'), findsOneWidget);
    expect(find.text('CrewMate'), findsNWidgets(2));
    expect(find.text('양치'), findsWidgets, reason: '직접 만든 항목은 칸 이름으로');
  });

  testWidgets('‹ 는 어제를 묻고 › 는 오늘을 넘지 않는다', (tester) async {
    final f = _fixture(logsByDate: {
      '2026-09-20': _sunday,
      '2026-09-19': [
        _log(id: 10, type: 'meal', careItemId: 2, who: 'CrewOwner', at: '2026-09-19T18:00:00', dogId: 7),
      ],
    });
    await _pump(tester, f);
    expect(tester.widget<IconButton>(find.byKey(const Key('care-log-next'))).onPressed, isNull,
        reason: '내일의 기록은 없고, 있는 것처럼 보이면 "안 했다" 로 읽힌다');

    await tester.tap(find.byKey(const Key('care-log-prev')));
    await tester.pumpAndSettle();

    expect(_logRequests(f).last.url.queryParameters['date'], '2026-09-19');
    expect(find.text('어제 · 9월 19일 (토)'), findsOneWidget);
    expect(find.text('1건 · 밥 1'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('08:50'), findsNothing, reason: '오늘 것이 어제 화면에 섞이면 안 된다');

    await tester.tap(find.byKey(const Key('care-log-next')));
    await tester.pumpAndSettle();
    expect(_logRequests(f).last.url.queryParameters['date'], '2026-09-20');
    expect(find.text('오늘 · 9월 20일 (일)'), findsOneWidget);
  });

  testWidgets('기록이 없는 날은 그렇다고 말한다', (tester) async {
    final f = _fixture();
    await _pump(tester, f);

    expect(find.byKey(const Key('care-log-empty')), findsOneWidget);
    expect(find.text('이날은 기록이 없어요'), findsOneWidget);
    expect(find.byKey(const Key('care-log-summary')), findsNothing);
  });

  testWidgets('실패하면 빈 화면이 아니라 다시 시도를 그린다 — 빈 화면은 "아무도 안 했다" 로 읽힌다',
      (tester) async {
    final f = _fixture(logsStatus: 500);
    await _pump(tester, f);

    expect(find.text('연결이 불안정해요'), findsOneWidget);
    expect(find.byKey(const Key('care-log-empty')), findsNothing);

    await tester.tap(find.byKey(const Key('care-log-retry')));
    await tester.pumpAndSettle();
    expect(_logRequests(f).length, 2);
  });

  testWidgets('항목 목록을 못 읽어도 종류 이름으로 적는다 — 종류도 없으면 "케어"', (tester) async {
    final f = _fixture(logsByDate: {'2026-09-20': _sunday}, itemsStatus: 500);
    await _pump(tester, f);

    expect(find.text('4건 · 밥 1 · 물 1 · 병원 1 · 케어 1'), findsOneWidget,
        reason: '항목 목록이 없으면 처음 한 시각 순 — 서버가 준 순서(뒤섞임)가 아니다');
    expect(find.text('양치'), findsNothing);
  });
}
