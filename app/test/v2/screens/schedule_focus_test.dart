// 알림을 누르면 그 날, 그 줄 (#420 후속) — 달이 달라도 옮겨 가고, 물든 자리는 잠깐이다.
//
// `schedule_screen_test` 와 같은 방식이다 — 목 저장소가 아니라 **진짜 ScheduleRepository 에
// MockClient 를 꽂는다.** 그래야 달을 다시 읽는 조회까지 한 번에 지난다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/notification_route.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/domain/schedule_reminder.dart';
import 'package:heat_trip_flutter/v2/screens/schedule_screen.dart';

const _base = 'https://api.example.test';

/// 테스트가 보는 "오늘".
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
  required String onDate,
}) =>
    {
      'id': id,
      'ownerKind': 'dog',
      'ownerRef': 1,
      'dogId': null,
      'kind': 'vet',
      'title': title,
      'memo': null,
      'onDate': onDate,
      'atTime': '10:30:00',
      'assignee': null,
      'status': 'planned',
      'doneAt': null,
      'version': 0,
      'updatedBy': null,
      'updatedAt': null,
    };

/// 달마다 다른 답을 주는 서버 하나 — `from` 의 달로 고른다.
({ScheduleRepository repo, FamilyRepository family, List<Uri> asked}) _fixture(
    Map<int, List<Map<String, Object?>>> byMonth) {
  final asked = <Uri>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        // 가족이 없는 사람 — 그때 일정은 아이 소유다. 오류가 아니라 정상 경로다.
        return _json({'error': {}}, status: 404);
      }
      asked.add(request.url);
      final from = DateTime.parse(request.url.queryParameters['from']!);
      return _json(byMonth[from.month] ?? const []);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    repo: ScheduleRepository(baseUrl: _base, client: client),
    family: FamilyRepository(baseUrl: _base, client: client),
    asked: asked,
  );
}

/// 알림은 안 건다 — 진짜 싱크는 테스트 바인딩에 없는 채널을 부른다.
class _SilentSink implements ScheduleReminderSink {
  @override
  Future<void> replaceAll(List<ScheduleReminder> reminders) async {}
}

Future<void> _pump(WidgetTester tester, ScheduleRepository repo, FamilyRepository family) async {
  // 달력 아래의 그날 목록까지 한 화면에 들어오게 — 기본 창(800x600)에서는 목록이 아예 안 그려진다.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ScheduleScreen(
      repository: repo,
      familyRepository: family,
      reminderSink: _SilentSink(),
      today: _today,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScheduleFocusInbox.resetForTest();
  });
  tearDown(ScheduleFocusInbox.resetForTest);

  testWidgets('알림이 가리킨 날이 열리고 그 줄이 잠깐 물든다', (tester) async {
    final f = _fixture({
      10: [
        _schedule(id: 41, title: '보리 병원', onDate: '2026-10-20'),
        _schedule(id: 42, title: '미용', onDate: '2026-10-20'),
      ],
    });
    // 꺼져 있던 앱이 알림으로 떴다 — 화면이 뜨기 전에 이미 와 있다.
    ScheduleFocusInbox.offer(
        ScheduleFocus(scheduleId: 41, onDate: DateTime(2026, 10, 20)));

    await _pump(tester, f.repo, f.family);

    expect(find.text('10월 20일'), findsOneWidget, reason: '오늘(15일)이 아니라 알림이 말한 날이다');
    expect(find.text('보리 병원'), findsOneWidget);

    final focused = tester.widget<AnimatedContainer>(find.byKey(const Key('schedule-row-41')));
    final other = tester.widget<AnimatedContainer>(find.byKey(const Key('schedule-row-42')));
    expect((focused.decoration! as BoxDecoration).color,
        isNot((other.decoration! as BoxDecoration).color),
        reason: '그 줄 하나만 물든다 — 색으로만 말한다');

    // 잠깐이다. 계속 칠해 두면 사용자가 "고른 것" 으로 읽는다.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    final after = tester.widget<AnimatedContainer>(find.byKey(const Key('schedule-row-41')));
    expect((after.decoration! as BoxDecoration).color,
        (other.decoration! as BoxDecoration).color);
  });

  testWidgets('다음 달 일정이면 그 달을 다시 읽는다 — 옮기기만 하면 빈 날로 보인다', (tester) async {
    final f = _fixture({
      10: const [],
      11: [_schedule(id: 51, title: '예방접종', onDate: '2026-11-03')],
    });
    // **떠 있는 화면에** 알림이 온 경우로 잰다. 뜨기 전에 넣으면 첫 조회가 아직 달을 안 정한
    // 상태라, 다시 읽지 않아도 11월을 물어보게 되어 검사가 공허해진다(되돌려서 빨간불 F5).
    await _pump(tester, f.repo, f.family);
    expect(f.asked.map((u) => u.queryParameters['from']), ['2026-10-01']);

    ScheduleFocusInbox.offer(
        ScheduleFocus(scheduleId: 51, onDate: DateTime(2026, 11, 3)));
    await tester.pumpAndSettle();

    expect(find.text('예방접종'), findsOneWidget);
    expect(find.text('11월 3일'), findsOneWidget);
    expect(f.asked.map((u) => u.queryParameters['from']), contains('2026-11-01'),
        reason: '한 달치만 들고 있는 화면이라 그 달을 새로 물어야 한다');
  });

  testWidgets('한 번만 간다 — 가져간 뒤에는 상자가 비어 있다', (tester) async {
    final f = _fixture({
      10: [_schedule(id: 41, title: '보리 병원', onDate: '2026-10-20')],
    });
    ScheduleFocusInbox.offer(
        ScheduleFocus(scheduleId: 41, onDate: DateTime(2026, 10, 20)));

    await _pump(tester, f.repo, f.family);

    expect(ScheduleFocusInbox.pending.value, isNull,
        reason: '안 비우면 일정 탭에 올 때마다 그 날로 끌려간다');
  });

  testWidgets('앱이 떠 있는 동안 누른 알림도 따라간다', (tester) async {
    final f = _fixture({
      10: [_schedule(id: 41, title: '보리 병원', onDate: '2026-10-20')],
    });
    await _pump(tester, f.repo, f.family);
    expect(find.textContaining('10월 15일'), findsWidgets, reason: '처음에는 오늘이다');

    ScheduleFocusInbox.offer(
        ScheduleFocus(scheduleId: 41, onDate: DateTime(2026, 10, 20)));
    await tester.pumpAndSettle();

    expect(find.text('10월 20일'), findsOneWidget);
  });
}
