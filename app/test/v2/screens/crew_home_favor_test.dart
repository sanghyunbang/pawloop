// 크루 홈의 품앗이 · 방장 넘기기 · 크루 지우기 (이슈 #417, 서버는 PR #428).
//
// `crew_section_test.dart` 와 같은 방식이다 — 리포지토리를 목으로 갈아끼우지 않고 **진짜
// CrewRepository 에 MockClient 를 꽂는다.** 그래야 경로·본문·실패 분류까지 한 번에 지난다.
//
// ## 여기서 가장 중요한 것
//
// **버튼이 권한과 같은 모양인 것**이다. 내 부탁에는 거둬들이기만, 맡은 것에는 무르기만, 남의
// 열린 부탁에만 "제가 할게요" — 서버가 403·400 으로 거절할 버튼을 화면이 먼저 안 그린다.
// 그리고 **방장 자리의 버튼이 하나뿐인 것** — 혼자면 지우기, 둘 이상이면 넘기기다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/crew_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/domain/schedule.dart';
import 'package:heat_trip_flutter/v2/screens/crew_home_screen.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'RT-1';

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

http.Response _error(int status, String code, String message) =>
    _json({'error': {'code': code, 'message': message}}, status: status);

const _me = {'userId': 1, 'nickname': '나', 'role': 'OWNER'};
const _neighbor = {'userId': 2, 'nickname': '이웃', 'role': 'MEMBER'};

Map<String, Object?> _crew({
  bool mine = true,
  bool owner = false,
  List<Object?> members = const [_neighbor, _me],
}) =>
    {
      'id': 4,
      'roomId': 9,
      'name': '성수동 아침 산책',
      'intro': null,
      'neighborhoodCode': '1120052000',
      'visibility': 'public',
      'capacity': 20,
      'memberCount': members.length,
      'mine': mine,
      'owner': owner,
      'members': members,
      'createdAt': '2026-09-10T02:20:00Z',
    };

Map<String, Object?> _favor({
  int id = 12,
  String onDate = '2026-09-20',
  String slot = 'afternoon',
  Object? note = '두 시간만 부탁드려요',
  String status = 'open',
  Object? askedBy = const {'userId': 3, 'nickname': '성수아빠'},
  Object? takenBy,
  Object? dog = const {'dogId': 7, 'name': '보리'},
  bool mine = false,
  bool takenByMe = false,
  Object? scheduleId,
}) =>
    {
      'id': id,
      'onDate': onDate,
      'slot': slot,
      'note': note,
      'status': status,
      'askedBy': askedBy,
      'takenBy': takenBy,
      'dog': dog,
      'mine': mine,
      'takenByMe': takenByMe,
      'scheduleId': scheduleId,
      'createdAt': '2026-09-13T02:20:00Z',
    };

/// 서버 하나. 크루와 부탁 목록은 **바꿀 수 있다** — 화면이 낡은 상태를 재려면 서버가 그 사이
/// 달라져 있어야 한다. 쓰기는 [onWrite] 가 받는다.
class _Server {
  Map<String, Object?> crew;
  List<Map<String, Object?>> favors;
  http.Response Function(http.Request request)? onWrite;
  final List<http.Request> sent = [];

  late final CrewRepository repo = CrewRepository(
    baseUrl: _base,
    client: AuthedClient(
      inner: MockClient(_handle),
      baseUrl: _base,
      store: _FakeTokenStore(),
    ),
  );

  _Server({required this.crew, this.favors = const [], this.onWrite});

  Future<http.Response> _handle(http.Request request) async {
    sent.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/crews/4') return _json(crew);
    if (request.method == 'GET' && path == '/api/crews/4/favors') return _json(favors);
    return onWrite?.call(request) ?? http.Response('', 204);
  }

  Iterable<http.Request> get favorLoads =>
      sent.where((r) => r.method == 'GET' && r.url.path == '/api/crews/4/favors');

  Iterable<http.Request> get writes => sent.where((r) => r.method != 'GET');
}

/// 카드가 여럿이라 800×600 에서는 아래쪽이 안 만들어진다 — "없다" 와 "화면 밖이다" 를 가르려면
/// 키 큰 뷰포트가 필요하다.
Future<void> pumpHome(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // 한 테스트에서 두 번 띄우면 같은 자리의 State 가 재사용된다 — 첫 서버의 크루가 그대로
  // 남는다. 키를 새로 줘서 화면을 새로 만든다.
  await tester.pumpWidget(MaterialApp(
      home: CrewHomeScreen(key: UniqueKey(), crewId: 4, repository: server.repo)));
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('crew-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    kMyPets.value = const [
      DogProfile(name: '보리', serverId: 7, breed: '푸들', size: DogSize.small, ageMonths: 30),
    ];
  });
  tearDown(() => kMyPets.value = const []);

  group('품앗이 목록', () {
    testWidgets('든 크루의 홈에 부탁이 서버에서 온다 — 언제 · 누구 · 상태를 그린다', (tester) async {
      final server = _Server(crew: _crew(), favors: [
        _favor(id: 12),
        _favor(
            id: 13,
            onDate: '2026-09-21',
            slot: 'evening',
            status: 'taken',
            takenBy: const {'userId': 2, 'nickname': '이웃'},
            dog: null,
            note: null),
      ]);
      await pumpHome(tester, server);

      expect(find.text('9월 20일 (일) 오후'), findsOneWidget);
      expect(find.text('보리 · 두 시간만 부탁드려요'), findsOneWidget);
      expect(find.text('성수아빠 님의 부탁'), findsOneWidget);
      expect(find.byKey(const Key('crew-favor-take-12')), findsOneWidget,
          reason: '남의 열린 부탁에는 "제가 할게요" 가 있다');

      expect(find.text('9월 21일 (월) 저녁'), findsOneWidget);
      expect(find.text('성수아빠 님의 부탁 · 이웃 님이 맡았어요'), findsOneWidget);
      expect(find.byKey(const Key('crew-favor-take-13')), findsNothing,
          reason: '남이 맡은 부탁에는 버튼이 없다 — 눌러도 409 다');
      expect(find.byKey(const Key('crew-favor-release-13')), findsNothing);
      expect(find.byKey(const Key('crew-favor-cancel-13')), findsNothing);
    });

    testWidgets('안 든 공개 크루에서는 부탁을 아예 안 묻는다 — 서버도 404 다', (tester) async {
      final server = _Server(crew: _crew(mine: false, members: const []));
      await pumpHome(tester, server);

      expect(find.byKey(const Key('crew-join-headline')), findsOneWidget);
      expect(find.text('품앗이'), findsNothing);
      expect(server.favorLoads, isEmpty,
          reason: '부탁에는 아이 이름과 "그날 집을 비운다" 가 적힌다 — 인원 수까지가 공개다');
    });

    testWidgets('못 불러오면 빈 목록이 아니라 이유와 다시 시도가 뜬다', (tester) async {
      // 부탁 목록만 처음에 실패한다 — 크루는 잘 온다.
      var failing = true;
      final sent = <http.Request>[];
      final client = AuthedClient(
        inner: MockClient((request) async {
          sent.add(request);
          if (request.url.path == '/api/crews/4/favors') {
            if (failing) return _error(500, 'INTERNAL', '잠시 문제가 있습니다.');
            return _json([_favor()]);
          }
          return _json(_crew());
        }),
        baseUrl: _base,
        store: _FakeTokenStore(),
      );
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: CrewHomeScreen(
              crewId: 4, repository: CrewRepository(baseUrl: _base, client: client))));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crew-favors-failure')), findsOneWidget);
      expect(find.byKey(const Key('crew-favors-empty')), findsNothing,
          reason: '빈 목록은 "부탁이 없다" 로 읽힌다 — 서버가 죽은 것을 아무도 모른다');

      failing = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('9월 20일 (일) 오후'), findsOneWidget);
      expect(sent.where((r) => r.url.path == '/api/crews/4').length, 1,
          reason: '부탁만 다시 받는다 — 크루는 그대로다');
    });
  });

  group('맡기 · 무르기 · 거둬들이기', () {
    testWidgets('"제가 할게요" 를 누르면 맡기가 나가고 카드가 "내가 맡았어요" 로 바뀐다 — 목록을 다시 안 받는다',
        (tester) async {
      final server = _Server(
        crew: _crew(),
        favors: [_favor()],
        onWrite: (_) => _json(_favor(
            status: 'taken',
            takenByMe: true,
            takenBy: const {'userId': 1, 'nickname': '나'},
            scheduleId: 99)),
      );
      await pumpHome(tester, server);

      await tester.tap(find.byKey(const Key('crew-favor-take-12')));
      await tester.pumpAndSettle();

      final write = server.writes.single;
      expect(write.method, 'POST');
      expect(write.url.path, '/api/crews/4/favors/12/take');
      expect(find.text('성수아빠 님의 부탁 · 내가 맡았어요 · 달력에 남았어요'), findsOneWidget);
      expect(find.byKey(const Key('crew-favor-release-12')), findsOneWidget,
          reason: '맡은 뒤에는 무르기다 — "제가 할게요" 가 남아 있으면 두 번 맡는다');
      expect(find.byKey(const Key('crew-favor-take-12')), findsNothing);
      expect(find.text('맡았어요 · 크루 달력에 남겼어요'), findsOneWidget);
      expect(server.favorLoads.length, 1, reason: '답에 그 부탁이 온다 — 목록을 다시 받을 이유가 없다');
    });

    testWidgets('그 사이 남이 맡았으면(409) 그렇다고 말하고 목록을 다시 받는다', (tester) async {
      final server = _Server(
        crew: _crew(),
        favors: [_favor()],
        onWrite: (_) => _error(409, 'CONFLICT', '이미 다른 분이 맡았습니다.'),
      );
      await pumpHome(tester, server);
      // 서버는 그 사이 달라져 있다.
      server.favors = [
        _favor(status: 'taken', takenBy: const {'userId': 2, 'nickname': '이웃'}),
      ];

      await tester.tap(find.byKey(const Key('crew-favor-take-12')));
      await tester.pumpAndSettle();

      expect(find.text('이미 다른 분이 맡았어요. 목록을 새로 받았어요.'), findsOneWidget);
      expect(server.favorLoads.length, 2, reason: '화면이 낡은 것이다 — 서버가 다시 답하게 한다');
      expect(find.text('성수아빠 님의 부탁 · 이웃 님이 맡았어요'), findsOneWidget);
      expect(find.byKey(const Key('crew-favor-take-12')), findsNothing);
    });

    testWidgets('내 부탁에는 거둬들이기만 있다 — 확인 뒤 지우고 카드가 사라진다', (tester) async {
      final server = _Server(crew: _crew(), favors: [_favor(mine: true)]);
      await pumpHome(tester, server);

      expect(find.text('내 부탁'), findsOneWidget);
      expect(find.byKey(const Key('crew-favor-take-12')), findsNothing,
          reason: '내 부탁을 내가 맡을 수는 없다 — 서버도 400 이다');
      expect(find.byKey(const Key('crew-favor-cancel-12')), findsOneWidget);

      await tester.tap(find.byKey(const Key('crew-favor-cancel-12')));
      await tester.pumpAndSettle();
      expect(find.text('부탁을 거둬들일까요'), findsOneWidget);
      await confirm(tester);

      final write = server.writes.single;
      expect(write.method, 'DELETE');
      expect(write.url.path, '/api/crews/4/favors/12');
      expect(find.byKey(const Key('crew-favor-12')), findsNothing);
      expect(find.byKey(const Key('crew-favors-empty')), findsOneWidget);
    });

    testWidgets('거둬들이기를 그만두면 아무것도 안 나간다', (tester) async {
      final server = _Server(crew: _crew(), favors: [_favor(mine: true)]);
      await pumpHome(tester, server);

      await tester.tap(find.byKey(const Key('crew-favor-cancel-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('그만두기'));
      await tester.pumpAndSettle();

      expect(server.writes, isEmpty);
      expect(find.byKey(const Key('crew-favor-12')), findsOneWidget);
    });

    testWidgets('맡은 것은 무르기 — 부탁이 다시 열린다', (tester) async {
      final server = _Server(
        crew: _crew(),
        favors: [
          _favor(
              status: 'taken',
              takenByMe: true,
              takenBy: const {'userId': 1, 'nickname': '나'},
              scheduleId: 99),
        ],
        onWrite: (_) => _json(_favor()),
      );
      await pumpHome(tester, server);

      await tester.tap(find.byKey(const Key('crew-favor-release-12')));
      await tester.pumpAndSettle();
      expect(find.text('맡은 것을 무를까요'), findsOneWidget);
      await confirm(tester);

      final write = server.writes.single;
      expect(write.method, 'DELETE');
      expect(write.url.path, '/api/crews/4/favors/12/take');
      expect(find.byKey(const Key('crew-favor-take-12')), findsOneWidget,
          reason: '무르면 부탁이 다시 열린다 — 다른 사람이 맡을 수 있다');
      expect(find.text('물렀어요 · 부탁이 다시 열렸어요'), findsOneWidget);
    });
  });

  group('부탁 올리기', () {
    testWidgets('시간대를 안 고르면 못 올리고, 고르면 적은 그대로 나간다 — 목록을 다시 안 받는다',
        (tester) async {
      final server = _Server(
        crew: _crew(),
        onWrite: (request) {
          final body = jsonDecode(request.body) as Map;
          return _json(
              _favor(
                  id: 40,
                  onDate: body['onDate'] as String,
                  slot: body['slot'] as String,
                  note: body['note'],
                  mine: true),
              status: 201);
        },
      );
      await pumpHome(tester, server);
      expect(find.byKey(const Key('crew-favors-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('crew-favor-add')));
      await tester.pumpAndSettle();

      expect(find.text('시간대를 골라 주세요'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('crew-favor-submit'))).onPressed,
          isNull,
          reason: '시간대에 기본값이 없다 — 미리 골라 두면 안 바꾼 채 올리는 사람이 생긴다');
      expect(find.byKey(const Key('crew-favor-dog-7')), findsOneWidget);

      await tester.tap(find.byKey(const Key('crew-favor-slot-evening')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('crew-favor-note')), '  잠깐만요  ');
      final today = DateTime.now();
      await tester.tap(find.byKey(const Key('crew-favor-submit')));
      await tester.pumpAndSettle();

      final write = server.writes.single;
      expect(write.method, 'POST');
      expect(write.url.path, '/api/crews/4/favors');
      expect(jsonDecode(write.body), {
        'onDate': Schedule.formatDate(today),
        'slot': 'evening',
        'dogId': 7,
        'note': '잠깐만요',
      }, reason: '한 마리면 그 아이가 미리 골라져 있다 — 금액 칸은 없다');

      expect(find.byKey(const Key('crew-favor-40')), findsOneWidget);
      expect(find.text('내 부탁'), findsOneWidget);
      expect(find.text('부탁을 올렸어요'), findsOneWidget);
      expect(server.favorLoads.length, 1, reason: '올린 것을 끼워 넣으면 같은 목록이다');
    });

    testWidgets('"아이 없이" 를 고르면 dogId 를 안 싣고, 아이가 한 마리도 없으면 아이 칸이 없다',
        (tester) async {
      final server = _Server(
        crew: _crew(),
        onWrite: (_) => _json(_favor(id: 41, dog: null, mine: true), status: 201),
      );
      await pumpHome(tester, server);

      await tester.tap(find.byKey(const Key('crew-favor-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crew-favor-dog-none')));
      await tester.tap(find.byKey(const Key('crew-favor-slot-morning')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crew-favor-submit')));
      await tester.pumpAndSettle();

      final body = jsonDecode(server.writes.single.body) as Map;
      expect(body.containsKey('dogId'), isFalse);
      expect(body.containsKey('note'), isFalse, reason: '빈 한 줄은 안 싣는다');

      // 아이가 없는 사람.
      kMyPets.value = const [];
      final none = _Server(crew: _crew());
      await pumpHome(tester, none);
      await tester.tap(find.byKey(const Key('crew-favor-add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crew-favor-dog-none')), findsNothing,
          reason: '고를 아이가 없으면 칸 자체가 없다 — 아이를 아직 등록 안 한 사람도 부탁할 수 있다');
      expect(find.text('누구를'), findsNothing);
    });

    testWidgets('서버가 거절하면 시트가 이유를 말하고 닫히지 않는다', (tester) async {
      final server = _Server(
        crew: _crew(),
        onWrite: (_) => _error(404, 'NOT_FOUND', '반려동물을 찾을 수 없습니다.'),
      );
      await pumpHome(tester, server);

      await tester.tap(find.byKey(const Key('crew-favor-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crew-favor-slot-afternoon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crew-favor-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crew-favor-error')), findsOneWidget);
      expect(find.text('반려동물을 찾을 수 없습니다.'), findsOneWidget);
      expect(find.byKey(const Key('crew-favor-submit')), findsOneWidget,
          reason: '왜 안 됐는지 모른 채로 시트가 사라지면 같은 것을 다시 적는다');
    });
  });

  group('방장 넘기기 · 크루 지우기', () {
    testWidgets('혼자면 지우기, 둘 이상이면 넘기기다 — 둘 다 그리지 않는다', (tester) async {
      await pumpHome(tester, _Server(crew: _crew(owner: true, members: const [_me])));
      expect(find.text('크루 지우기'), findsOneWidget);
      expect(find.text('방장 넘기기'), findsNothing, reason: '넘길 사람이 없다');
      expect(find.text('크루 나가기'), findsNothing, reason: '방장은 못 나간다 — 서버도 400 이다');

      await pumpHome(tester, _Server(crew: _crew(owner: true)));
      expect(find.text('방장 넘기기'), findsOneWidget);
      expect(find.text('크루 지우기'), findsNothing,
          reason: '사람이 있으면 못 지운다 — 남의 대화를 지우는 버튼은 없다');
      expect(find.byKey(const Key('crew-owner-note')), findsOneWidget,
          reason: '버튼만 두면 왜 나가기가 없는지 아무도 모른다');
    });

    testWidgets('넘기면 화면이 멤버 모드가 된다 — 나가기가 생기고 고치기가 사라진다', (tester) async {
      final server = _Server(
        crew: _crew(owner: true),
        onWrite: (_) => _json(_crew(owner: false, members: const [
          {'userId': 2, 'nickname': '이웃', 'role': 'OWNER'},
          {'userId': 1, 'nickname': '나', 'role': 'MEMBER'},
        ])),
      );
      await pumpHome(tester, server);
      expect(find.byKey(const Key('crew-edit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('crew-action-방장 넘기기')));
      await tester.pumpAndSettle();
      expect(find.text('누구에게 넘길까요'), findsOneWidget);
      expect(find.byKey(const Key('crew-transfer-1')), findsNothing, reason: '나에게는 못 넘긴다');
      await tester.tap(find.byKey(const Key('crew-transfer-2')));
      await tester.pumpAndSettle();
      expect(find.text('이웃 님에게 넘길까요'), findsOneWidget);
      await confirm(tester);

      final write = server.writes.single;
      expect(write.method, 'PUT');
      expect(write.url.path, '/api/crews/4/owner/2');
      expect(find.text('이웃 님이 방장이 됐어요'), findsOneWidget);
      expect(find.text('크루 나가기'), findsOneWidget, reason: '넘긴 뒤의 나는 평범한 멤버라 나갈 수 있다');
      expect(find.byKey(const Key('crew-edit')), findsNothing);
      expect(find.text('방장 넘기기'), findsNothing);
    });

    testWidgets('지우면 목록으로 돌아가며 "달라졌다" 를 들고 나간다', (tester) async {
      final server = _Server(crew: _crew(owner: true, members: const [_me]));
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      bool? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                  builder: (_) => CrewHomeScreen(crewId: 4, repository: server.repo)));
            },
            child: const Text('열기'),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('crew-action-크루 지우기')));
      await tester.pumpAndSettle();
      expect(find.text('크루를 지울까요'), findsOneWidget);
      await confirm(tester);

      final write = server.writes.single;
      expect(write.method, 'DELETE');
      expect(write.url.path, '/api/crews/4');
      expect(popped, isTrue, reason: '목록이 그것을 보고 서버에 다시 묻는다');
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('혼자인 줄 알았는데 그 사이 누가 들어왔으면(409) 넘기라고 말하고 다시 불러온다',
        (tester) async {
      final server = _Server(
        crew: _crew(owner: true, members: const [_me]),
        onWrite: (_) => _error(409, 'CONFLICT', '혼자 남았을 때만 지울 수 있습니다.'),
      );
      await pumpHome(tester, server);
      server.crew = _crew(owner: true);

      await tester.tap(find.byKey(const Key('crew-action-크루 지우기')));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('다른 멤버가 남아 있어요. 방장을 넘기고 나가는 길이 있어요.'), findsOneWidget);
      expect(find.text('방장 넘기기'), findsOneWidget, reason: '다시 받으면 버튼이 넘기기로 바뀐다');
      expect(find.text('크루 지우기'), findsNothing);
      expect(find.text('열기'), findsNothing);
    });
  });
}
