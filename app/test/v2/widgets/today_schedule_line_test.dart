// 홈의 "오늘 할 일" 한 줄 — 이슈 #420.
//
// ## 여기서 가장 중요한 것
//
// **없으면 줄 자체가 없는 것**이다. "오늘 할 일 0" 은 자리만 차지한다 — 홈은 이미 카드가
// 여럿이라, 아무것도 안 말하는 줄이 하나 더 붙으면 사용자는 그만큼 아래로 밀린 것을 못 본다.
// 그리고 그건 **화면을 안 보면 안 잡힌다** — 위젯이 그려지긴 하니까.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/domain/schedule.dart';
import 'package:heat_trip_flutter/v2/widgets/today_schedule_line.dart';

const _base = 'https://api.example.test';

final _today = DateTime(2026, 10, 15);

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

Map<String, Object?> _schedule({
  required int id,
  required String title,
  String kind = 'vet',
  String status = 'planned',
  Object? assignee,
}) =>
    {
      'id': id,
      'ownerKind': 'group',
      'ownerRef': 3,
      'dogId': null,
      'kind': kind,
      'title': title,
      'memo': null,
      'onDate': '2026-10-15',
      'atTime': '10:30:00',
      'assignee': assignee,
      'status': status,
      'doneAt': null,
      'version': 0,
      'updatedBy': null,
      'updatedAt': null,
    };

({ScheduleRepository repo, List<http.Request> sent}) fixture(
    {List<Map<String, Object?>> items = const [], int status = 200}) {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      return status == 200 ? _json(items) : _json({'error': {}}, status: status);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: ScheduleRepository(baseUrl: _base, client: client), sent: sent);
}

Future<void> pump(WidgetTester tester,
    ({ScheduleRepository repo, List<http.Request> sent}) f) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TodayScheduleLine(repository: f.repo, today: _today),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.authenticated;
  });
  tearDown(AuthState.resetForTest);

  testWidgets('게스트에게는 아예 안 묻는다 — 401 과 12초 타이머만 남는다', (tester) async {
    AuthState.status.value = AuthStatus.unauthenticated;
    final f = fixture(items: [_schedule(id: 1, title: '보리 병원')]);
    await pump(tester, f);

    expect(f.sent, isEmpty);
    expect(find.textContaining('할 일'), findsNothing);
  });

  testWidgets('오늘 할 일이 있으면 개수와 종류가 한 줄로 나온다', (tester) async {
    final f = fixture(items: [
      _schedule(id: 1, title: '보리 병원', assignee: {'userId': 11, 'nickname': '아빠'}),
      _schedule(id: 2, title: '주말 목욕', kind: 'bath'),
    ]);
    await pump(tester, f);

    expect(find.text('할 일 2 · 병원(아빠) · 목욕'), findsOneWidget);
  });

  testWidgets('오늘 것만 물어본다 — from 과 to 가 같은 날이다', (tester) async {
    final f = fixture();
    await pump(tester, f);

    final q = f.sent.single.url.queryParameters;
    expect(q['from'], '2026-10-15');
    expect(q['to'], '2026-10-15');
  });

  testWidgets('없으면 줄 자체가 없다 — "할 일 0" 은 자리만 차지한다', (tester) async {
    final f = fixture();
    await pump(tester, f);

    expect(find.textContaining('할 일'), findsNothing);
    final box = tester.renderObject<RenderBox>(find.byType(TodayScheduleLine));
    expect(box.size.height, 0,
        reason: '높이가 남으면 아래 카드들이 그만큼 밀린다 — 텍스트만 재면 못 잡는다');
  });

  testWidgets('이미 한 것과 건너뛴 것은 할 일이 아니다', (tester) async {
    final f = fixture(items: [
      _schedule(id: 1, title: '보리 병원', status: 'done'),
      _schedule(id: 2, title: '심장사상충', kind: 'med', status: 'skipped'),
      _schedule(id: 3, title: '저녁 산책', kind: 'walk'),
    ]);
    await pump(tester, f);

    expect(find.text('할 일 1 · 산책'), findsOneWidget);
  });

  testWidgets('전부 끝냈으면 줄이 사라진다', (tester) async {
    final f = fixture(items: [_schedule(id: 1, title: '보리 병원', status: 'done')]);
    await pump(tester, f);

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('못 불러와도 조용하다 — 지나가다 보는 줄이라 못 봐도 잃는 것이 없다', (tester) async {
    final f = fixture(status: 500);
    await pump(tester, f);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('불러오지'), findsNothing);
    expect(find.textContaining('할 일'), findsNothing);
  });

  testWidgets('일정이 바뀌었다는 신호를 들으면 다시 읽는다 — 케어 카드가 완료로 바꾼 뒤 이 줄이 낡으면 안 된다 (#741)',
      (tester) async {
    final f = fixture(items: [_schedule(id: 1, title: '보리 병원')]);
    await pump(tester, f);
    expect(f.sent, hasLength(1));

    kScheduleRev.value++;
    await tester.pumpAndSettle();

    expect(f.sent, hasLength(2),
        reason: '바로 위 카드가 병원 일정을 완료로 바꿨는데 "할 일 1 · 병원" 이 남으면 안 끝난 것처럼 보인다');
  });

  group('요약 문장', () {
    Schedule at(int id, String kind, String title, {String? who}) => Schedule.tryParse(
        _schedule(
            id: id,
            kind: kind,
            title: title,
            assignee: who == null ? null : {'userId': 1, 'nickname': who}))!;

    test('셋을 넘으면 앞의 둘만 적는다 — 개수는 이미 맨 앞에 있다', () {
      final line = TodayScheduleLine.summarize([
        at(1, 'vet', '보리 병원'),
        at(2, 'bath', '목욕'),
        at(3, 'walk', '산책'),
        at(4, 'med', '약'),
      ]);

      expect(line, '할 일 4 · 병원 · 목욕');
    });

    test('제목이 아니라 종류를 적는다 — 제목은 길이를 알 수 없다', () {
      final line = TodayScheduleLine.summarize([
        at(1, 'vet', '보리 광견병 접종하러 강남 동물병원 다녀오기'),
      ]);

      expect(line, '할 일 1 · 병원');
    });
  });
}
