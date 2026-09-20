// "오늘의 케어" 카드와 오늘 일정의 연결 — 이슈 #741 (사장님 A).
//
// 카드에서 병원·산책·투약을 눌러 기록해도 일정 탭의 오늘 같은 종류 일정은 그대로 열려 있었다 —
// 케어 → 일정 방향이 없어서. 이제 기록하기 **전에** 한 장 묻고, "완료로" 면 일정을 PATCH 한다.
// 서버가 그 일정의 케어 기록을 스스로 남기므로(`ScheduleService.syncCareLog`) 카드는 POST 를
// **안 한다** — 여기서 그 둘(PATCH 하나 · POST 없음)을 잠근다. 서버 쪽 통합 테스트는 "완료로
// 바꾸면 케어 기록이 생긴다" 를 잠그지만, 앱이 한 번 더 보내는 것은 어느 백엔드 테스트도
// 못 잡는다 — 그 자리가 이 파일이다.
//
// `today_care_card_test.dart` 와 같은 방식이다 — 진짜 저장소 둘에 MockClient 하나를 꽂는다.
// 그래야 경로·쿼리(`?version=`)·본문·409 분류까지 한 번에 지난다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/domain/schedule.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

/// 테스트가 보는 "오늘". 일정의 `onDate` 와 같은 날이어야 한다.
final _today = DateTime(2026, 10, 15);

const _mungchi = DogProfile(
    serverId: 1, name: '뭉치', breed: '푸들', size: DogSize.small, ageMonths: 24);
const _nuri = DogProfile(
    serverId: 2, name: '누리', breed: '시바', size: DogSize.medium, ageMonths: 48);

class _Tokens implements AuthTokenStore {
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

/// 오늘 10:30 뭉치 병원 — 광견병 접종. 안 준 것은 그 값이다.
Map<String, Object?> _schedule({
  required int id,
  String kind = 'vet',
  String title = '광견병 접종',
  Object? atTime = '10:30:00',
  int? dogId = 1,
  String status = 'planned',
  int version = 2,
  Object? updatedBy,
}) =>
    {
      'id': id,
      'ownerKind': 'group',
      'ownerRef': 3,
      'dogId': dogId,
      'kind': kind,
      'title': title,
      'memo': null,
      'onDate': '2026-10-15',
      'atTime': atTime,
      'assignee': null,
      'status': status,
      'doneAt': null,
      'version': version,
      'updatedBy': updatedBy,
      'updatedAt': null,
    };

Map<String, Object?> _log({
  required int id,
  required String type,
  String who = '아빠',
  int userId = 22,
  String at = '2026-10-15T08:10:00',
}) =>
    {
      'id': id,
      'dogId': 1,
      'groupId': 3,
      'type': type,
      'doneBy': {'userId': userId, 'nickname': who},
      'occurredAt': at,
      'memo': null,
    };

/// 서버가 받은 것. 무엇을 몇 번 보냈는지가 이 파일의 단언이다.
class _Server {
  final List<http.Request> carePosts = [];
  final List<http.Request> patches = [];
  final List<http.Request> scheduleReads = [];
  int careLogReads = 0;
}

({FamilyRepository family, ScheduleRepository schedules, _Server server}) fixture({
  List<Map<String, Object?>> schedules = const [],
  List<Map<String, Object?>> logs = const [],
  int schedulesStatus = 200,
  http.Response Function(http.Request request)? onPatch,
}) {
  final server = _Server();
  final client = AuthedClient(
    inner: MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/groups/me') {
        return _json({'id': 3, 'name': '뭉치네', 'roomId': 9, 'members': []});
      }
      // 항목 목록은 비워 둔다 — 카드가 기본 일곱(종류 있는 칸)으로 그린다.
      if (path.endsWith('/care-items')) return _json(const []);
      if (path == '/api/groups/3/care-logs') {
        if (request.method == 'POST') {
          server.carePosts.add(request);
          return _json(_log(id: 99, type: 'vet', who: '나', userId: 11), status: 201);
        }
        server.careLogReads++;
        return _json(logs);
      }
      if (path == '/api/schedules') {
        server.scheduleReads.add(request);
        return schedulesStatus == 200
            ? _json(schedules)
            : _json({'error': {}}, status: schedulesStatus);
      }
      if (path.startsWith('/api/schedules/') && request.method == 'PATCH') {
        server.patches.add(request);
        if (onPatch != null) return onPatch(request);
        return _json(_schedule(id: int.parse(path.split('/').last), status: 'done', version: 3));
      }
      return _json({'error': {}}, status: 404);
    }),
    baseUrl: _base,
    store: _Tokens(),
  );
  return (
    family: FamilyRepository(baseUrl: _base, client: client),
    schedules: ScheduleRepository(baseUrl: _base, client: client),
    server: server,
  );
}

Future<void> pumpCard(
  WidgetTester tester,
  ({FamilyRepository family, ScheduleRepository schedules, _Server server}) f,
) async {
  // 진짜 기기 폭 — 칸 일곱이 두 줄로 접히는 그 폭이다.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TodayCareCard(
        repository: f.family,
        scheduleRepository: f.schedules,
        today: _today,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> tapCell(WidgetTester tester, String slug) async {
  await tester.tap(find.byKey(Key('care-cell-$slug')));
  await tester.pumpAndSettle();
}

Finder get _question => find.text('일정을 완료로 할까요?');

void main() {
  setUp(() {
    AuthState.signInForTest(const AuthUser(id: 11, nickname: '나'));
    replacePets(const [_mungchi, _nuri]);
    selectPet(0);
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
  });

  testWidgets('병원 칸 + 오늘 열린 병원 일정 → 묻고, "완료로" 면 PATCH 하나 · 케어 POST 없음 · 카드가 다시 읽는다',
      (tester) async {
    final f = fixture(schedules: [_schedule(id: 5)]);
    await pumpCard(tester, f);
    expect(f.server.careLogReads, 1);

    await tapCell(tester, 'vet');

    expect(_question, findsOneWidget);
    expect(find.text('오늘 10:30 뭉치 병원 — 광견병 접종 일정이 있어요.'), findsOneWidget,
        reason: '시각 · 아이 · 종류 · 제목 순이다 — 제목만 적으면 "병원" 이라는 사실이 그 안에 없을 수 있다');
    expect(find.byKey(const Key('care-schedule-record-only')), findsOneWidget);
    expect(find.byKey(const Key('care-schedule-done')), findsOneWidget);
    expect(f.server.patches, isEmpty, reason: '고르기 전에는 보내지 않는다');
    expect(f.server.carePosts, isEmpty);
    final rev = kScheduleRev.value;

    await tester.tap(find.byKey(const Key('care-schedule-done')));
    await tester.pumpAndSettle();

    expect(f.server.patches, hasLength(1));
    expect(f.server.patches.single.url.path, '/api/schedules/5');
    expect(f.server.patches.single.url.queryParameters['version'], '2',
        reason: 'version 이 빠지면 서버가 400 이고, 틀리면 409 다');
    expect(jsonDecode(f.server.patches.single.body)['status'], 'done');
    expect(f.server.carePosts, isEmpty,
        reason: '서버가 일정의 케어 기록을 스스로 남긴다(syncCareLog) — 여기서 또 보내면 두 번 남는다');
    expect(f.server.careLogReads, greaterThan(1),
        reason: '그 기록이 칸에 보여야 사용자가 "됐다" 를 안다');
    expect(kScheduleRev.value, rev + 1, reason: '홈의 할 일 줄이 이 신호를 듣고 다시 읽는다');
    expect(_question, findsNothing);
  });

  testWidgets('"아니요 · 기록만" 이면 지금 흐름 그대로다 — 케어 POST 하나, PATCH 없음', (tester) async {
    final f = fixture(schedules: [_schedule(id: 5)]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');
    await tester.tap(find.byKey(const Key('care-schedule-record-only')));
    await tester.pumpAndSettle();

    expect(f.server.carePosts, hasLength(1));
    expect(f.server.carePosts.single.url.path, '/api/groups/3/care-logs');
    expect(jsonDecode(f.server.carePosts.single.body), {'type': 'vet', 'dogId': 1});
    expect(f.server.patches, isEmpty, reason: '일정은 그대로 열려 있어야 한다 — 사용자가 그렇게 골랐다');
  });

  testWidgets('오늘 일정이 없으면 안 묻고 바로 기록한다', (tester) async {
    final f = fixture();
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(_question, findsNothing,
        reason: '아무 때나 물으면 사람은 곧 읽지 않고 누른다 — 그러면 진짜 물어야 할 때도 안 읽는다');
    expect(f.server.carePosts, hasLength(1));
    expect(f.server.patches, isEmpty);
  });

  testWidgets('다른 아이의 병원 일정이면 안 묻는다 — 누리 병원을 뭉치 카드에서 완료하면 안 된다', (tester) async {
    final f = fixture(schedules: [_schedule(id: 5, dogId: 2)]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(_question, findsNothing);
    expect(f.server.carePosts, hasLength(1));
    expect(f.server.patches, isEmpty);
  });

  testWidgets('아이 없는 가족 일정은 묻는다 — 이름 없이', (tester) async {
    final f = fixture(schedules: [_schedule(id: 5, dogId: null)]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(find.text('오늘 10:30 병원 — 광견병 접종 일정이 있어요.'), findsOneWidget,
        reason: '"병원" 만 적어 둔 가족 일정도 오늘 병원에 다녀온 것이다 — 아이 이름을 지어내지 않는다');
  });

  testWidgets('이미 완료했거나 건너뛴 일정이면 안 묻는다', (tester) async {
    final f = fixture(schedules: [
      _schedule(id: 5, status: 'done'),
      _schedule(id: 6, status: 'skipped', title: '재진'),
    ]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(_question, findsNothing, reason: '끝난 일정을 또 완료로 묻는 것은 잔소리다');
    expect(f.server.carePosts, hasLength(1));
    expect(f.server.patches, isEmpty);
  });

  testWidgets('물 칸은 일정이 있어도 안 묻는다 — 물·밥·배변·마킹에는 일정 짝이 없다', (tester) async {
    final f = fixture(schedules: [
      _schedule(id: 5),
      _schedule(id: 6, kind: 'walk', title: '저녁 산책'),
      _schedule(id: 7, kind: 'med', title: '심장사상충'),
    ]);
    await pumpCard(tester, f);

    await tapCell(tester, 'water');

    expect(_question, findsNothing);
    expect(f.server.carePosts, hasLength(1));
    expect(jsonDecode(f.server.carePosts.single.body)['type'], 'water');
    expect(f.server.patches, isEmpty);
  });

  testWidgets('종류 짝이 맞아야 묻는다 — 투약 칸에 병원 일정만 있으면 안 묻는다', (tester) async {
    final f = fixture(schedules: [_schedule(id: 5)]);
    await pumpCard(tester, f);

    await tapCell(tester, 'med');

    expect(_question, findsNothing, reason: '병원 일정을 투약 칸에서 완료하면 병원이 안 다녀온 채 닫힌다');
    expect(f.server.carePosts, hasLength(1));
    expect(f.server.patches, isEmpty);
  });

  for (final (slug, kind, label) in [('walk', 'walk', '산책'), ('med', 'med', '투약')]) {
    testWidgets('$label 칸 + 오늘 열린 $label 일정 → 묻는다 — 병원만의 일이 아니다', (tester) async {
      final f = fixture(schedules: [_schedule(id: 5, kind: kind, title: '')]);
      await pumpCard(tester, f);

      await tapCell(tester, slug);

      expect(_question, findsOneWidget);
      expect(find.text('오늘 10:30 뭉치 $label 일정이 있어요.'), findsOneWidget);
    });
  }

  testWidgets('/api/schedules 가 500 이어도 카드는 그대로 기록한다 — 빈 화면도 오류 문구도 없다',
      (tester) async {
    final f = fixture(schedulesStatus: 500);
    await pumpCard(tester, f);

    expect(find.text('아직'), findsNWidgets(7), reason: '일정은 곁다리다 — 케어 칸이 사라지면 안 된다');
    expect(find.textContaining('불안정'), findsNothing);
    expect(tester.takeException(), isNull);

    await tapCell(tester, 'vet');

    expect(_question, findsNothing);
    expect(f.server.carePosts, hasLength(1));
  });

  testWidgets('하루 종일 일정은 시각 없이 묻는다', (tester) async {
    final f = fixture(schedules: [_schedule(id: 5, atTime: null, title: '')]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(find.text('오늘 뭉치 병원 일정이 있어요.'), findsOneWidget,
        reason: '"하루 종일" 에 00:00 을 적으면 자정 일정이 된다');
  });

  testWidgets('같은 종류가 둘이면 시각이 빠른 것 하나만 묻는다 — 그것을 완료로 보낸다', (tester) async {
    final f = fixture(schedules: [
      _schedule(id: 6, atTime: '14:00:00', title: '재진'),
      _schedule(id: 5),
    ]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(_question, findsOneWidget);
    expect(find.text('오늘 10:30 뭉치 병원 — 광견병 접종 일정이 있어요.'), findsOneWidget);
    expect(find.textContaining('재진'), findsNothing);

    await tester.tap(find.byKey(const Key('care-schedule-done')));
    await tester.pumpAndSettle();

    expect(f.server.patches.single.url.path, '/api/schedules/5');
  });

  testWidgets('오늘 하루치만 묻는다 — from 과 to 가 같은 날이고 아이로 안 거른다', (tester) async {
    final f = fixture();
    await pumpCard(tester, f);

    final q = f.server.scheduleReads.single.url.queryParameters;
    expect(q['from'], '2026-10-15');
    expect(q['to'], '2026-10-15');
    expect(q.containsKey('dogId'), isFalse,
        reason: '서버에서 아이로 거르면 아이 없는 가족 일정이 빠진다 — 아이는 누를 때 가른다');
  });

  testWidgets('바깥을 눌러 닫으면 아무것도 안 한다 — 기록도 완료도 사용자가 고른 것이어야 한다',
      (tester) async {
    final f = fixture(schedules: [_schedule(id: 5)]);
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');
    expect(_question, findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(_question, findsNothing);
    expect(f.server.carePosts, isEmpty);
    expect(f.server.patches, isEmpty);
  });

  group('완료로가 실패하면', () {
    testWidgets('409 면 최신 값으로 바꾸고 누가 고쳤는지 한 줄 — 케어 POST 는 없고 카드는 다시 읽는다',
        (tester) async {
      final f = fixture(
        schedules: [_schedule(id: 5)],
        onPatch: (_) => _json({
          'error': {'code': 'CONFLICT', 'message': '다른 사람이 먼저 고쳤습니다.'},
          'current': _schedule(
              id: 5, status: 'done', version: 3, updatedBy: {'userId': 22, 'nickname': '아빠'}),
        }, status: 409),
      );
      await pumpCard(tester, f);

      await tapCell(tester, 'vet');
      await tester.tap(find.byKey(const Key('care-schedule-done')));
      await tester.pumpAndSettle();

      expect(find.text('아빠님이 방금 고쳤어요. 최신 내용으로 바꿨어요.'), findsOneWidget,
          reason: '일정 탭과 같은 말이다');
      expect(f.server.carePosts, isEmpty);
      expect(f.server.careLogReads, greaterThan(1),
          reason: '아빠가 완료했으면 서버가 케어 기록도 남겼다 — 칸이 바뀌어야 한다');
    });

    testWidgets('연결이 안 되면 문구 한 줄 — 기록도 완료도 없다', (tester) async {
      final f = fixture(
        schedules: [_schedule(id: 5)],
        onPatch: (_) => http.Response('boom', 500),
      );
      await pumpCard(tester, f);

      await tapCell(tester, 'vet');
      await tester.tap(find.byKey(const Key('care-schedule-done')));
      await tester.pumpAndSettle();

      expect(find.text('연결이 불안정해요. 잠시 뒤 다시 해 주세요.'), findsOneWidget);
      expect(f.server.carePosts, isEmpty,
          reason: '완료가 안 됐다고 기록으로 바꿔치기하면 사용자는 완료된 줄 안다');
      expect(find.text('아직'), findsNWidgets(7), reason: '실패해도 카드는 그대로다');
    });
  });

  testWidgets('일정 물음이 "다음 기록" 물음보다 먼저다 — 기록만 고르면 그다음에 그 물음이 온다',
      (tester) async {
    final f = fixture(
      schedules: [_schedule(id: 5)],
      logs: [_log(id: 1, type: 'vet')],
    );
    await pumpCard(tester, f);

    await tapCell(tester, 'vet');

    expect(_question, findsOneWidget);
    expect(find.text('다음 기록을 남길까요?'), findsNothing);

    await tester.tap(find.byKey(const Key('care-schedule-record-only')));
    await tester.pumpAndSettle();

    expect(find.text('다음 기록을 남길까요?'), findsOneWidget);
    expect(f.server.carePosts, isEmpty, reason: '두 번째 물음의 답을 듣기 전이다');
  });

  group('짝과 문구 (위젯 없이)', () {
    Schedule at(int id, {String kind = 'vet', int? dogId = 1, String status = 'planned',
            Object? atTime = '10:30:00', String title = '광견병 접종'}) =>
        Schedule.tryParse(_schedule(
            id: id, kind: kind, dogId: dogId, status: status, atTime: atTime, title: title))!;

    test('케어 종류 → 일정 종류는 서버의 careWire 와 같은 셋뿐이다', () {
      expect(scheduleKindOf(ServerCareType.walk), ScheduleKind.walk);
      expect(scheduleKindOf(ServerCareType.vet), ScheduleKind.vet);
      expect(scheduleKindOf(ServerCareType.med), ScheduleKind.med);
      for (final type in [
        ServerCareType.water,
        ServerCareType.meal,
        ServerCareType.poop,
        ServerCareType.pee,
        null,
      ]) {
        expect(scheduleKindOf(type), isNull, reason: '$type 에는 일정 짝이 없다');
      }
    });

    test('같은 종류 · 열림 · 고른 아이(또는 아이 없음) — 셋 다 봐야 짝이다', () {
      final today = [
        at(1, kind: 'walk'),
        at(2, status: 'done'),
        at(3, dogId: 2),
        at(4, dogId: null, atTime: null),
        at(5, atTime: '15:00:00'),
        at(6),
      ];

      expect(openScheduleFor(ServerCareType.vet, today, dogId: 1)?.id, 6,
          reason: '열린 병원 일정 셋(4 · 5 · 6) 중 시각이 빠른 것 — 하루 종일(4)은 뒤다');
      expect(openScheduleFor(ServerCareType.vet, today, dogId: 2)?.id, 3);
      expect(openScheduleFor(ServerCareType.vet, today, dogId: null)?.id, 4,
          reason: '아이를 한 마리도 안 등록한 집은 아이 없는 일정만 짝이다');
      expect(openScheduleFor(ServerCareType.walk, today, dogId: 1)?.id, 1);
      expect(openScheduleFor(ServerCareType.med, today, dogId: 1), isNull);
      expect(openScheduleFor(ServerCareType.water, today, dogId: 1), isNull);
    });

    test('문구 — 시각과 이름은 있을 때만, 종류 다음에 제목', () {
      expect(scheduleDoneQuestion(at(1), dogName: '뭉치'),
          '오늘 10:30 뭉치 병원 — 광견병 접종 일정이 있어요.');
      expect(scheduleDoneQuestion(at(1, atTime: null, title: ''), dogName: '뭉치'),
          '오늘 뭉치 병원 일정이 있어요.');
      expect(scheduleDoneQuestion(at(1, title: '')), '오늘 10:30 병원 일정이 있어요.');
      expect(scheduleDoneQuestion(at(1, atTime: null), dogName: '뭉치'),
          '오늘 뭉치 병원 — 광견병 접종 일정이 있어요.');
      expect(scheduleDoneQuestion(at(1, kind: 'med', title: '  '), dogName: '뭉치'),
          '오늘 10:30 뭉치 투약 일정이 있어요.', reason: '빈칸뿐인 제목은 없는 것이다');
    });
  });
}
