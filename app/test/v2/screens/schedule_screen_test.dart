// 일정표 화면 — 달력 · 그날 목록 · 필터 · 충돌 (이슈 #419).
//
// `family_screen_test` 와 같은 방식이다 — 저장소를 목으로 갈아끼우지 않고 **진짜
// ScheduleRepository 에 MockClient 를 꽂는다.** 그래야 JSON 파싱·쿼리 파라미터·실패
// 분류까지 한 번에 지난다. 목을 앱이 읽는 키로 만들면 테스트가 버그에 동의한다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/dog_avatar.dart';
import 'package:heat_trip_flutter/v2/domain/schedule_reminder.dart';
import 'package:heat_trip_flutter/v2/screens/schedule_screen.dart';
import 'package:heat_trip_flutter/v2/theme/member_colors.dart';
import 'package:heat_trip_flutter/v2/widgets/aurora.dart';
import 'package:heat_trip_flutter/v2/widgets/form_kit.dart';

const _base = 'https://api.example.test';

/// 테스트가 보는 "오늘". 달이 바뀌어도 같은 것을 재기 위해 고정한다.
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

Map<String, Object?> schedule({
  required int id,
  required String title,
  String onDate = '2026-10-20',
  Object? atTime = '10:30:00',
  int? dogId,
  String kind = 'vet',
  String status = 'planned',
  int version = 0,
  Object? assignee,
  Object? updatedBy,
  String ownerKind = 'group',
  int ownerRef = 3,
  Object? memo,
}) =>
    {
      'id': id,
      'ownerKind': ownerKind,
      'ownerRef': ownerRef,
      'dogId': dogId,
      'kind': kind,
      'title': title,
      'memo': memo,
      'onDate': onDate,
      'atTime': atTime,
      'assignee': assignee,
      'status': status,
      'doneAt': null,
      'version': version,
      'updatedBy': updatedBy,
      'updatedAt': null,
    };

/// 서버 하나. [items] 가 기간 조회의 답이고, [onPatch]·[onPost] 로 쓰기를 가로챈다.
({ScheduleRepository repo, FamilyRepository family, List<http.Request> sent}) fixture({
  List<Map<String, Object?>> items = const [],
  bool hasGroup = true,
  List<Map<String, Object?>> members = const [],
  http.Response Function(http.Request request)? onPatch,
  http.Response Function(http.Request request)? onPost,
}) {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      if (request.url.path == '/api/groups/me') {
        return hasGroup
            ? _json({'id': 3, 'name': '보리네 가족', 'roomId': 9, 'members': members})
            : _json({'error': {}}, status: 404);
      }
      if (request.url.path.startsWith('/api/schedules')) {
        if (request.method == 'PATCH') {
          return onPatch?.call(request) ?? _json(items.first);
        }
        if (request.method == 'POST') {
          return onPost?.call(request) ?? _json(items.first, status: 201);
        }
        // 목록. dogId 필터는 서버가 하므로 여기서도 흉내 낸다.
        final dogId = request.url.queryParameters['dogId'];
        final filtered = dogId == null
            ? items
            : items.where((s) => '${s['dogId']}' == dogId).toList();
        return _json(filtered);
      }
      return _json(const []);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    repo: ScheduleRepository(baseUrl: _base, client: client),
    family: FamilyRepository(baseUrl: _base, client: client),
    sent: sent,
  );
}

/// 알림을 실제로 걸지 않고 받아만 둔다. 진짜 싱크는 `flutter_local_notifications` 를
/// 부르고, 테스트 바인딩에는 그 채널이 없어 던진다.
class _ThrowingSink implements ScheduleReminderSink {
  @override
  Future<void> replaceAll(List<ScheduleReminder> reminders) async {
    throw StateError('알림 채널이 없다');
  }
}

class _RecordingSink implements ScheduleReminderSink {
  final List<List<ScheduleReminder>> calls = [];

  @override
  Future<void> replaceAll(List<ScheduleReminder> reminders) async {
    calls.add(reminders);
  }
}

Future<void> pumpScreen(
  WidgetTester tester,
  ({ScheduleRepository repo, FamilyRepository family, List<http.Request> sent}) f, {
  ScheduleReminderSink? sink,
}) async {
  // 달력 + 목록이 한 번에 만들어지도록 키 큰 뷰포트를 준다. 800×600 에서는 아래쪽
  // 목록이 아예 안 만들어져 "없다" 와 "화면 밖이다" 가 구별되지 않는다.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: ScheduleScreen(
      repository: f.repo,
      familyRepository: f.family,
      today: _today,
      reminderSink: sink,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    kMyPets.value = const [
      DogProfile(
          name: '보리', serverId: 7, breed: '푸들', size: DogSize.small, ageMonths: 30),
      DogProfile(
          name: '초코', serverId: 8, breed: '시바', size: DogSize.medium, ageMonths: 48),
    ];
  });
  tearDown(() => kMyPets.value = const []);

  testWidgets('날짜를 누르면 그날 목록이 나온다 — 다른 날 일정은 안 섞인다', (tester) async {
    final f = fixture(items: [
      schedule(id: 1, title: '보리 병원', onDate: '2026-10-20'),
      schedule(id: 2, title: '심장사상충', onDate: '2026-10-25', atTime: null),
    ]);
    await pumpScreen(tester, f);

    // 오늘(15일)에는 아무것도 없다. 이 달에는 있으므로 "없다" 가 아니라 "이 날은 비었다" 다.
    expect(find.text('10월 15일은 비어 있어요'), findsOneWidget);
    expect(find.text('아직 적어 둔 일정이 없어요'), findsNothing,
        reason: '20일에 적어 둔 사람이 15일을 눌렀을 때 "없어요" 를 보면 사라진 줄 안다');

    await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
    await tester.pumpAndSettle();

    expect(find.text('보리 병원'), findsOneWidget);
    expect(find.text('심장사상충'), findsNothing,
        reason: '25일 일정이 20일 목록에 있으면 달력이 날짜를 안 가르는 것이다');
  });

  testWidgets('하루 종일은 시각 있는 것 뒤에 묶인다', (tester) async {
    final f = fixture(items: [
      schedule(id: 1, title: '주말 목욕', onDate: '2026-10-20', atTime: null),
      schedule(id: 2, title: '보리 병원', onDate: '2026-10-20', atTime: '10:30:00'),
    ]);
    await pumpScreen(tester, f);
    await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 2건'));
    await tester.pumpAndSettle();

    expect(find.text('하루 종일'), findsOneWidget);
    final timed = tester.getTopLeft(find.text('보리 병원')).dy;
    final allDay = tester.getTopLeft(find.text('주말 목욕')).dy;
    expect(timed, lessThan(allDay),
        reason: '시각 없는 것이 위로 올라오면 그날의 순서가 뒤집힌다');
  });

  testWidgets('시각 없는 일정에 00:00 이라고 적지 않는다', (tester) async {
    final f = fixture(items: [
      schedule(id: 1, title: '주말 목욕', onDate: '2026-10-20', atTime: null),
    ]);
    await pumpScreen(tester, f);
    await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
    await tester.pumpAndSettle();

    expect(find.textContaining('00:00'), findsNothing,
        reason: '사용자가 안 정한 시각을 정한 것처럼 그리면 안 된다');
  });

  testWidgets('크루 일정은 "크루" 와 시간대 메모가 함께 적힌다 — 그날 아침에 언제인지가 보여야 한다',
      (tester) async {
    final f = fixture(items: [
      // 품앗이를 맡으면 서버가 남기는 줄이다(#417) — 시각 대신 시간대가 메모에 산다.
      schedule(
          id: 1,
          title: '보리 봐 주기',
          onDate: '2026-10-20',
          atTime: null,
          ownerKind: 'room',
          ownerRef: 9,
          memo: '오후 · 두 시간만 부탁드려요',
          assignee: {'userId': 2, 'nickname': '이웃'}),
      schedule(id: 2, title: '보리 병원', onDate: '2026-10-20', memo: '간식 챙기기'),
    ]);
    await pumpScreen(tester, f);
    await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 2건'));
    await tester.pumpAndSettle();

    expect(find.text('크루 · 오후 · 두 시간만 부탁드려요'), findsOneWidget,
        reason: '내 아이 일정 사이에 "보리 봐 주기" 만 있으면 누구 것인지, 언제인지 모른다');
    expect(find.text('이웃 담당'), findsOneWidget, reason: '담당은 태그로 — 같은 줄에 산다(#736)');
    expect(find.textContaining('간식 챙기기'), findsNothing,
        reason: '메모를 줄에 적는 것은 크루 일정뿐이다 — 시간대가 거기 살아서다');
  });

  testWidgets('필터 칩이 아이별로 가른다 — 서버에 dogId 를 보낸다', (tester) async {
    final f = fixture(items: [
      schedule(id: 1, title: '보리 병원', onDate: '2026-10-20', dogId: 7),
      schedule(id: 2, title: '초코 목욕', onDate: '2026-10-20', dogId: 8),
    ]);
    await pumpScreen(tester, f);
    await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 2건'));
    await tester.pumpAndSettle();
    expect(find.text('보리 병원'), findsOneWidget);
    expect(find.text('초코 목욕'), findsOneWidget);

    await tester.tap(find.widgetWithText(GestureDetector, '보리').first);
    await tester.pumpAndSettle();

    final last = f.sent.lastWhere((r) => r.method == 'GET');
    expect(last.url.queryParameters['dogId'], '7');
    expect(find.text('보리 병원'), findsOneWidget);
    expect(find.text('초코 목욕'), findsNothing);
  });

  testWidgets('아이 목록이 늦게 와도 필터 칩과 이름이 따라온다', (tester) async {
    // 아이 목록은 셸의 PetLoader 가 채운다(#159) — 이 화면보다 늦게 올 수 있다. 값을 한 번만
    // 읽으면 그날 처음 연 사람에게는 칩이 영영 "전체" 하나뿐이다.
    kMyPets.value = const [];
    final f = fixture(items: [
      schedule(id: 1, title: '보리 병원', onDate: '2026-10-20', dogId: 7),
    ]);
    await pumpScreen(tester, f);
    await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
    await tester.pumpAndSettle();

    expect(find.text('보리'), findsNothing);

    kMyPets.value = const [
      DogProfile(
          name: '보리', serverId: 7, breed: '푸들', size: DogSize.small, ageMonths: 30),
    ];
    await tester.pumpAndSettle();

    expect(find.text('보리'), findsWidgets, reason: '필터 칩과 목록의 아이 이름이 함께 살아난다');
  });

  testWidgets('아이 필터 칩에 그 아이의 사진이 붙는다 — 없으면 종 이모지, 있으면 사진 (#448)', (tester) async {
    kMyPets.value = const [
      DogProfile(
          name: '보리', serverId: 7, breed: '푸들', size: DogSize.small, ageMonths: 30,
          photoUrl: 'https://cdn.example.test/profiles/1/bori.jpg'),
      DogProfile(
          name: '초코', serverId: 8, breed: '시바', size: DogSize.medium, ageMonths: 48),
    ];
    final f = fixture();
    await pumpScreen(tester, f);

    final bori = find.ancestor(of: find.text('보리'), matching: find.byType(DogAvatar));
    expect(find.descendant(of: find.ancestor(of: find.text('보리'), matching: find.byType(Row)).first,
            matching: find.byType(DogAvatar)),
        findsOneWidget, reason: '홈·내 정보와 같은 사진이 칩에도');
    expect(find.descendant(of: find.ancestor(of: find.text('보리'), matching: find.byType(Row)).first,
            matching: find.byKey(const Key('dog-photo'))),
        findsOneWidget, reason: '사진이 있는 아이는 사진');
    expect(find.descendant(of: find.ancestor(of: find.text('초코'), matching: find.byType(Row)).first,
            matching: find.byKey(const Key('dog-photo'))),
        findsNothing, reason: '사진이 없는 아이는 이모지');
    expect(find.descendant(of: find.ancestor(of: find.text('전체'), matching: find.byType(Row)).first,
            matching: find.byType(DogAvatar)),
        findsNothing, reason: '"전체" 칩에는 아이가 없다');
    expect(bori, findsNothing);
  });

  testWidgets('빈 상태가 무엇을 하면 되는지 말한다', (tester) async {
    final f = fixture();
    await pumpScreen(tester, f);

    expect(find.text('아직 적어 둔 일정이 없어요'), findsOneWidget);
    expect(find.text('병원 예약부터 적어 볼까요'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '일정 적기'), findsOneWidget,
        reason: '"없다" 만 말하고 길을 안 주면 화면이 막다른 길이 된다');
  });

  // ── 폼 부품 (#445 · #453) — 화면이 머티리얼 기본 위젯이 아니라 우리 부품을 쓰는지
  group('폼 부품', () {
    testWidgets('떠 있는 + 는 없고 머리말의 둥근 버튼 하나뿐이다 — 빈 상태 버튼과 안 겹친다', (tester) async {
      final f = fixture();
      await pumpScreen(tester, f);

      expect(find.byType(FloatingActionButton), findsNothing,
          reason: '떠 있는 + 가 "일정 적기" 카드에 겹쳤다(#453)');
      expect(find.byTooltip('일정 추가'), findsOneWidget);
      expect(find.byType(GlassCard), findsWidgets, reason: '달력과 빈 상태는 홈과 같은 반투명 카드다');
    });

    testWidgets('시트는 흰 입력칸 · 고르기 상자 · 그라데이션 버튼이다 — 아웃라인·OutlinedButton 이 없다', (tester) async {
      final f = fixture();
      await pumpScreen(tester, f);
      await tester.tap(find.byTooltip('일정 추가'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassField), findsNWidgets(2), reason: '제목 · 메모');
      expect(find.byType(PickerButton), findsNWidgets(2), reason: '날짜 · 시각');
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.widgetWithText(PrimaryButton, '저장'), findsOneWidget);
      for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(field.decoration!.border, InputBorder.none,
            reason: '머티리얼 아웃라인이 하나라도 남으면 시트의 결이 갈린다');
      }
    });
  });

  testWidgets('시트로 만들면 목록에 바로 보인다 — 다시 안 불러온다', (tester) async {
    final f = fixture(
      onPost: (request) => _json(
          schedule(id: 9, title: '보리 광견병', onDate: '2026-10-18', atTime: '11:00:00'),
          status: 201),
    );
    await pumpScreen(tester, f);

    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '보리 광견병');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('보리 광견병'), findsOneWidget);
    final posted = jsonDecode(f.sent.lastWhere((r) => r.method == 'POST').body) as Map;
    expect(posted['ownerKind'], 'group',
        reason: '가족이 있으면 가족이 함께 보는 일정이다 — 주인을 사용자에게 묻지 않는다');
    expect(posted['ownerRef'], 3);
  });

  testWidgets('가족이 없으면 아이 소유가 되고 시트가 그것을 말한다', (tester) async {
    final f = fixture(
      hasGroup: false,
      onPost: (request) =>
          _json(schedule(id: 9, title: '보리 병원', onDate: '2026-10-18'), status: 201),
    );
    await pumpScreen(tester, f);

    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();

    expect(find.text('이 일정은 나만 봅니다'), findsOneWidget,
        reason: '가시성을 고르게 하지 않되 숨기지도 않는다');

    await tester.enterText(find.byType(TextField).first, '보리 병원');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final posted = jsonDecode(f.sent.lastWhere((r) => r.method == 'POST').body) as Map;
    expect(posted['ownerKind'], 'dog');
    expect(posted['ownerRef'], 7, reason: '가족이 없으면 첫 아이가 주인이다');
  });

  testWidgets('제목이 비면 저장하지 않는다', (tester) async {
    final f = fixture();
    await pumpScreen(tester, f);

    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('제목을 적어 주세요'), findsOneWidget);
    expect(f.sent.where((r) => r.method == 'POST'), isEmpty);
  });

  group('편집 충돌', () {
    testWidgets('409 를 받으면 최신 값을 보여 준다 — 조용히 덮어쓰지 않는다', (tester) async {
      final f = fixture(
        items: [schedule(id: 1, title: '보리 병원', onDate: '2026-10-20', atTime: '10:30:00')],
        onPatch: (_) => _json({
          'error': {'code': 'CONFLICT', 'message': '다른 사람이 먼저 고쳤습니다.'},
          'current': schedule(
            id: 1,
            title: '보리 병원(오후로)',
            onDate: '2026-10-20',
            atTime: '14:00:00',
            version: 1,
            updatedBy: {'userId': 11, 'nickname': '아빠'},
          ),
        }, status: 409),
      );
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('완료로'));
      await tester.pumpAndSettle();

      expect(find.text('아빠님이 방금 고쳤어요. 최신 내용으로 바꿨어요.'), findsOneWidget);
      expect(find.text('보리 병원(오후로)'), findsOneWidget,
          reason: '최신 값이 화면에 없으면 사용자는 자기 옛 화면을 계속 믿는다');
      expect(find.text('보리 병원'), findsNothing);
    });

    testWidgets('최신 값이 안 와도 사람을 지어내지 않는다', (tester) async {
      final f = fixture(
        items: [schedule(id: 1, title: '보리 병원', onDate: '2026-10-20')],
        onPatch: (_) => _json({'error': {'code': 'CONFLICT'}}, status: 409),
      );
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('완료로'));
      await tester.pumpAndSettle();

      expect(find.text('다른 분이 방금 고쳤어요. 최신 내용으로 바꿨어요.'), findsOneWidget);
    });

    testWidgets('충돌이 아니면 완료 표시가 그대로 반영된다', (tester) async {
      final f = fixture(
        items: [schedule(id: 1, title: '보리 병원', onDate: '2026-10-20')],
        onPatch: (_) => _json(schedule(
            id: 1, title: '보리 병원', onDate: '2026-10-20', status: 'done', version: 1)),
      );
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('완료로'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('아직 안 함으로'), findsOneWidget);
      final patched = f.sent.lastWhere((r) => r.method == 'PATCH');
      expect(patched.url.queryParameters['version'], '0');
      expect(jsonDecode(patched.body)['status'], 'done');
    });
  });

group('반복과 고치기 (#421)', () {
    testWidgets('펼친 하루를 누르면 "이 날만 / 앞으로 전부" 를 먼저 묻는다', (tester) async {
      final f = fixture(items: [
        {...schedule(id: 1, title: '목욕', onDate: '2026-10-20'),
          'repeatKind': 'weekly', 'occurrence': true},
      ]);
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('목욕'));
      await tester.pumpAndSettle();

      expect(find.text('되풀이하는 일정이에요'), findsOneWidget);
      expect(find.text('10월 20일만 고치기'), findsOneWidget);
      expect(find.text('앞으로 전부 고치기'), findsOneWidget);
    });

    testWidgets('"이 날만" 을 고르면 ?date= 가 붙고 반복 칸이 안 보인다', (tester) async {
      final f = fixture(
        items: [
          {...schedule(id: 1, title: '목욕', onDate: '2026-10-20'),
            'repeatKind': 'weekly', 'occurrence': true},
        ],
        onPatch: (_) => _json(schedule(id: 9, title: '목욕(옮김)', onDate: '2026-10-20')),
      );
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('목욕'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10월 20일만 고치기'));
      await tester.pumpAndSettle();

      expect(find.text('10월 20일 하루만 바꿉니다'), findsOneWidget);
      expect(find.text('반복'), findsNothing,
          reason: '하루짜리 행이 될 것이라 규칙이 없다');

      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();

      final patched = f.sent.lastWhere((r) => r.method == 'PATCH');
      expect(patched.url.queryParameters['date'], '2026-10-20');
      expect(jsonDecode(patched.body).containsKey('repeatKind'), isFalse,
          reason: '안 보내면 서버가 반복을 안 바꾼다');
    });

    testWidgets('"앞으로 전부" 를 고르면 ?date= 가 없고 반복을 고칠 수 있다', (tester) async {
      final f = fixture(
        items: [
          {...schedule(id: 1, title: '목욕', onDate: '2026-10-20'),
            'repeatKind': 'weekly', 'occurrence': true},
        ],
        onPatch: (_) => _json(schedule(id: 1, title: '목욕', onDate: '2026-10-20')),
      );
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('목욕'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('앞으로 전부 고치기'));
      await tester.pumpAndSettle();

      expect(find.text('반복'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();

      final patched = f.sent.lastWhere((r) => r.method == 'PATCH');
      expect(patched.url.queryParameters.containsKey('date'), isFalse);
      expect(jsonDecode(patched.body)['repeatKind'], 'weekly');
    });

    testWidgets('되풀이하는 줄은 목록에 그렇다고 적힌다', (tester) async {
      final f = fixture(items: [
        {...schedule(id: 1, title: '심장사상충', onDate: '2026-10-20', kind: 'med'),
          'repeatKind': 'monthly', 'occurrence': true},
      ]);
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();

      expect(find.textContaining('매월'), findsOneWidget,
          reason: '안 적으면 "왜 매달 있지" 를 사용자가 푼다');
    });

    testWidgets('평범한 일정은 안 묻고 바로 고치기로 간다', (tester) async {
      final f = fixture(items: [schedule(id: 1, title: '보리 병원', onDate: '2026-10-20')]);
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('보리 병원'));
      await tester.pumpAndSettle();

      expect(find.text('되풀이하는 일정이에요'), findsNothing);
      expect(find.text('일정 고치기'), findsOneWidget);
    });
  });

  group('담당자 (#421)', () {
    testWidgets('가족 구성원을 담당으로 고를 수 있다', (tester) async {
      final f = fixture(
        members: [
          {'userId': 11, 'nickname': '아빠'},
          {'userId': 12, 'nickname': '엄마'},
        ],
        onPost: (_) => _json(schedule(id: 9, title: '보리 병원'), status: 201),
      );
      await pumpScreen(tester, f);

      await tester.tap(find.byTooltip('일정 추가'));
      await tester.pumpAndSettle();
      expect(find.text('담당'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '보리 병원');
      await tester.tap(find.widgetWithText(GestureDetector, '엄마').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();

      final posted = jsonDecode(f.sent.lastWhere((r) => r.method == 'POST').body) as Map;
      expect(posted['assignee'], 12);
    });

    testWidgets('가족이 없으면 담당 칸 자체가 없다 — 물을 사람이 없다', (tester) async {
      final f = fixture(hasGroup: false);
      await pumpScreen(tester, f);

      await tester.tap(find.byTooltip('일정 추가'));
      await tester.pumpAndSettle();

      expect(find.text('담당'), findsNothing);
    });
  });

  testWidgets('되풀이로 저장하면 서버에 다시 물어본다 — 안 그러면 시작일 하루만 보인다', (tester) async {
    // 저장 응답은 규칙 한 줄뿐이다. 그것만 목록에 끼워 넣으면 달력에 시작일 하루만 점이
    // 찍힌다 — 매주로 저장했는데 다음 주가 안 보인다(에뮬레이터에서 눈으로 잡았다).
    final expanded = [
      {...schedule(id: 9, title: '보리 목욕', onDate: '2026-10-07'),
        'repeatKind': 'weekly', 'occurrence': true},
      {...schedule(id: 9, title: '보리 목욕', onDate: '2026-10-14'),
        'repeatKind': 'weekly', 'occurrence': true},
    ];
    var posted = false;
    final f = fixture(
      items: expanded,
      onPost: (_) {
        posted = true;
        return _json({...schedule(id: 9, title: '보리 목욕', onDate: '2026-10-07'),
          'repeatKind': 'weekly'}, status: 201);
      },
    );
    await pumpScreen(tester, f);
    final before = f.sent.where((r) => r.method == 'GET').length;

    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '보리 목욕');
    await tester.tap(find.widgetWithText(GestureDetector, '매주').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(f.sent.where((r) => r.method == 'GET').length, greaterThan(before),
        reason: '저장 뒤 그 달을 다시 물어야 펼쳐진 날이 보인다');
    await tester.tap(find.bySemanticsLabel('10월 14일 · 일정 1건'));
    await tester.pumpAndSettle();
    expect(find.text('보리 목욕'), findsOneWidget);
  });

  group('알림 (#420)', () {
    testWidgets('설정이 "없음" 이면 하나도 안 건다 — 기본값이다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sink = _RecordingSink();
      final f = fixture(items: [schedule(id: 1, title: '보리 병원', onDate: '2026-10-20')]);
      await pumpScreen(tester, f, sink: sink);

      expect(sink.calls.single, isEmpty,
          reason: '묻지 않고 알림을 보내는 앱이 되면 안 된다');
    });

    testWidgets('켜 두면 이 달의 앞으로 할 일에 예약이 걸린다', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'v2.schedule_reminder': '{"when":"morning_of"}'});
      final sink = _RecordingSink();
      final f = fixture(items: [
        schedule(id: 1, title: '보리 병원', onDate: '2026-10-20'),
        schedule(id: 2, title: '지난 병원', onDate: '2026-10-01'),
        schedule(id: 3, title: '끝낸 것', onDate: '2026-10-22', status: 'done'),
      ]);
      await pumpScreen(tester, f, sink: sink);

      final planned = sink.calls.last;
      expect(planned.map((r) => r.body), ['보리 병원 · 10:30'],
          reason: '지나간 것과 이미 한 것은 안 건다');
    });

    testWidgets('싱크가 던져도 달력은 그대로 그려진다 — 알림은 곁다리다', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'v2.schedule_reminder': '{"when":"morning_of"}'});
      final f = fixture(items: [schedule(id: 1, title: '보리 병원', onDate: '2026-10-20')]);
      await pumpScreen(tester, f, sink: _ThrowingSink());

      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 1건'));
      await tester.pumpAndSettle();
      expect(find.text('보리 병원'), findsOneWidget);
    });

    testWidgets('남의 담당 일정은 이 기기에서 안 건다 — 내 담당과 담당 없는 것만 (#734)', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'v2.schedule_reminder': '{"when":"morning_of"}'});
      AuthState.signInForTest(const AuthUser(id: 5, nickname: '엄마'));
      addTearDown(AuthState.resetForTest);
      final sink = _RecordingSink();
      final f = fixture(items: [
        schedule(id: 1, title: '아빠 담당 병원', onDate: '2026-10-20',
            assignee: {'userId': 6, 'nickname': '아빠'}),
        schedule(id: 2, title: '내 담당 미용', onDate: '2026-10-21', kind: 'groom',
            assignee: {'userId': 5, 'nickname': '엄마'}),
        schedule(id: 3, title: '가족 목욕', onDate: '2026-10-22', kind: 'bath', atTime: null),
      ]);
      await pumpScreen(tester, f, sink: sink);

      expect(sink.calls.last.map((r) => r.body), ['내 담당 미용 · 10:30 · 내 담당', '가족 목욕'],
          reason: '아빠 담당 병원이 엄마 폰에서 울리면 담당이라는 말이 알림에서는 없는 셈이다');
    });
  });

  group('내 담당 갈래와 사람 색 (#736)', () {
    const members = [
      {'userId': 5, 'nickname': '엄마'},
      {'userId': 6, 'nickname': '아빠'},
    ];
    final items = [
      schedule(id: 1, title: '아빠 담당 병원', onDate: '2026-10-20',
          assignee: {'userId': 6, 'nickname': '아빠'}),
      schedule(id: 2, title: '내 담당 미용', onDate: '2026-10-20', kind: 'groom',
          assignee: {'userId': 5, 'nickname': '엄마'}),
      schedule(id: 3, title: '가족 목욕', onDate: '2026-10-20', kind: 'bath', atTime: null),
    ];

    testWidgets('"내 담당" 을 고르면 담당이 나인 일정만 남는다 — 서버는 그대로, 앱에서 거른다',
        (tester) async {
      AuthState.signInForTest(const AuthUser(id: 5, nickname: '엄마'));
      addTearDown(AuthState.resetForTest);
      final f = fixture(items: items, members: members);
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 3건'));
      await tester.pumpAndSettle();
      expect(find.text('아빠 담당 병원'), findsOneWidget);

      await tester.tap(find.byKey(const Key('schedule-filter-mine')));
      await tester.pumpAndSettle();

      expect(find.text('내 담당 미용'), findsOneWidget);
      expect(find.text('아빠 담당 병원'), findsNothing);
      expect(find.text('가족 목욕'), findsNothing, reason: '담당이 없는 것은 "내 것" 이 아니다');
      expect(find.bySemanticsLabel('10월 20일 · 일정 1건'), findsOneWidget,
          reason: '달력의 건수도 갈래를 따른다 — 구글 캘린더처럼');
      final last = f.sent.lastWhere(
          (r) => r.method == 'GET' && r.url.path.startsWith('/api/schedules'));
      expect(last.url.queryParameters.keys, isNot(contains('assignee')),
          reason: '목록 API 에 담당 조건이 없다 — 이 달은 이미 받아 두었으니 앱에서 거른다');
    });

    testWidgets('담당자 태그는 사람마다 색이 다르다 — 가족 순서로', (tester) async {
      final f = fixture(items: items, members: members);
      await pumpScreen(tester, f);
      await tester.tap(find.bySemanticsLabel('10월 20일 · 일정 3건'));
      await tester.pumpAndSettle();

      Color tagColor(int id) {
        final box = tester.widget<Container>(find.byKey(Key('assignee-tag-$id')));
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(find.text('아빠 담당'), findsOneWidget);
      expect(find.text('엄마 담당'), findsOneWidget);
      expect(tagColor(2), memberColor(0).withAlpha(0x1F), reason: '엄마는 가족 첫째');
      expect(tagColor(1), memberColor(1).withAlpha(0x1F), reason: '아빠는 가족 둘째');
      expect(tagColor(1), isNot(tagColor(2)));
      expect(find.byKey(const Key('assignee-tag-3')), findsNothing,
          reason: '담당 없는 일정에는 태그가 없다');
    });

    testWidgets('가족이 없거나 내가 누군지 모르면 "내 담당" 갈래가 없다', (tester) async {
      // 가족 없음 — 담당을 정할 사람이 없다.
      final alone = fixture(hasGroup: false, items: [schedule(id: 1, title: '보리 병원')]);
      await pumpScreen(tester, alone);
      expect(find.byKey(const Key('schedule-filter-mine')), findsNothing);

      // 가족은 있는데 로그인 상태를 모른다(테스트 기본) — "나" 를 못 가르니 갈래를 안 그린다.
      final family = fixture(items: items, members: members);
      await pumpScreen(tester, family);
      expect(find.byKey(const Key('schedule-filter-mine')), findsNothing);
    });

    testWidgets('만들기 시트의 담당 칩도 그 사람 색이다 — 목록의 태그와 같은 색', (tester) async {
      final f = fixture(members: members);
      await pumpScreen(tester, f);
      await tester.tap(find.byTooltip('일정 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GestureDetector, '아빠').first);
      await tester.pumpAndSettle();

      final chip = tester.widget<PillChip>(find.widgetWithText(PillChip, '아빠'));
      expect(chip.selected, isTrue);
      expect(chip.color, memberColor(1));
      expect(tester.widget<PillChip>(find.widgetWithText(PillChip, '엄마')).color, memberColor(0));
    });
  });

  testWidgets('달을 넘기면 그 달을 다시 물어본다', (tester) async {
    final f = fixture();
    await pumpScreen(tester, f);

    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();

    expect(find.text('2026년 11월'), findsOneWidget);
    final last = f.sent.lastWhere((r) => r.method == 'GET');
    expect(last.url.queryParameters['from'], '2026-11-01');
    expect(last.url.queryParameters['to'], '2026-11-30');
  });
}
