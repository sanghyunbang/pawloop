// 일정 탭 — 게스트와 세션 만료 (#680).
//
// 로그인 없이 일정 탭을 열면 "일정을 불러오지 못했어요 · 다시 시도" 가 떴고, 눌러도 영원히
// 같았다. 원인이 연결이 아니라 로그인이었는데 `_send` 가 401 을 `network` 로 뭉갰고, 화면은
// 토큰이 있는지 보지도 않고 서버부터 불렀다. 홈·채팅과 같은 답으로 고쳤다 — 토큰이 없으면
// **부르지 않고** 로그인 안내를 그린다.
//
// 그래서 여기서는 문구와 **요청 개수**를 같이 잰다. 화면만 보면 "안 불렀다" 와 "불렀는데
// 401 을 잘 그렸다" 가 구분되지 않고, 뒤엣것은 소셜 왕복을 끊는다(#673).
//
// `schedule_screen_test` 와 같이 저장소를 목으로 갈아끼우지 않고 **진짜 저장소에 MockClient
// 를 꽂는다** — 상태 코드가 실패의 종류로 옮겨지는 그 자리까지 한 번에 지나야 한다.
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
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
import 'package:heat_trip_flutter/v2/screens/schedule_screen.dart';

const _base = 'https://api.example.test';

/// 테스트가 보는 "오늘". 달이 바뀌어도 같은 것을 재기 위해 고정한다.
final _today = DateTime(2026, 10, 15);

/// 서버 하나. [status] 로 답하고 나간 요청을 센다. 200 이면 가족 없음(404) · 일정 없음(`[]`) 이다.
class _Server {
  /// 가족·일정 요청에 답할 상태 코드. 테스트 도중 바꿀 수 있다 — "로그인하면 그때 읽는다".
  int status;

  /// 기기에 토큰이 있는가. 게스트는 없고, 세션이 끝난 사람은 있다(서버가 401 을 준다).
  bool tokens;

  final List<http.Request> sent = [];

  _Server({required this.status, required this.tokens});

  late final AuthedClient client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      if (status != 200) {
        return _json({'error': {'code': 'PROBE'}}, status: status);
      }
      if (request.url.path == '/api/groups/me') {
        return _json({'error': {'code': 'NOT_FOUND'}}, status: 404);
      }
      return _json(const []);
    }),
    baseUrl: _base,
    store: _Tokens(this),
  );

  ScheduleRepository get repo => ScheduleRepository(baseUrl: _base, client: client);
  FamilyRepository get family => FamilyRepository(baseUrl: _base, client: client);

  /// 일정 목록을 받으러 간 요청만. 갱신(`/auth/token/refresh`)은 401 의 부산물이라 뺀다.
  Iterable<http.Request> get scheduleCalls =>
      sent.where((r) => r.url.path == '/api/schedules');
}

class _Tokens implements AuthTokenStore {
  final _Server server;

  _Tokens(this.server);

  @override
  Future<String?> readAccessToken() async => server.tokens ? 'access-token' : null;

  @override
  Future<String?> readRefreshToken() async => server.tokens ? 'refresh-token' : null;

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

Future<void> _pump(WidgetTester tester, _Server server) async {
  // 달력 + 목록이 한 번에 만들어지도록 키 큰 뷰포트를 준다(`schedule_screen_test` 와 같다).
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: ScheduleScreen(
      repository: server.repo,
      familyRepository: server.family,
      today: _today,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(AuthState.resetForTest);
  tearDown(AuthState.resetForTest);

  group('게스트 — 로그인한 적 없는 사람', () {
    testWidgets('서버를 부르지 않고 로그인 안내를 그린다 — "다시 시도" 는 없다', (tester) async {
      AuthState.status.value = AuthStatus.unauthenticated;
      final server = _Server(status: 401, tokens: false);
      await _pump(tester, server);

      expect(server.sent, isEmpty,
          reason: '게스트에게 401 을 받으러 가지 않는다 — 요청 자체가 0 이어야 한다');
      expect(find.text('로그인이 필요해요'), findsOneWidget);
      expect(find.text('로그인하면 우리 가족 일정을 함께 봐요'), findsOneWidget);
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('일정을 불러오지 못했어요'), findsNothing,
          reason: '원인은 연결이 아니라 로그인이다');
      expect(find.text('다시 시도'), findsNothing,
          reason: '눌러도 영원히 같은 결과인 버튼은 그리지 않는다');
    });

    testWidgets('"로그인" 을 누르면 로그인 화면으로 간다', (tester) async {
      AuthState.status.value = AuthStatus.unauthenticated;
      final server = _Server(status: 401, tokens: false);
      await _pump(tester, server);

      await tester.tap(find.text('로그인'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(server.sent, isEmpty);
    });

    testWidgets('머리말의 + 도 로그인 화면이다 — 시트를 열지 않는다', (tester) async {
      AuthState.status.value = AuthStatus.unauthenticated;
      final server = _Server(status: 401, tokens: false);
      await _pump(tester, server);

      await tester.tap(find.byTooltip('일정 추가'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ScheduleSheet), findsNothing,
          reason: '시트에서 저장을 누르면 401 이다 — 열어 주는 것이 친절이 아니다');
      expect(server.sent, isEmpty);
    });

    testWidgets('소셜 왕복 중에도 부르지 않는다 — 그때 나간 401 이 로그인 왕복을 끊었다(#673)',
        (tester) async {
      AuthState.status.value = AuthStatus.unauthenticated;
      final server = _Server(status: 401, tokens: false);
      await _pump(tester, server);

      // 소셜 버튼을 누른 순간. 이 화면은 상태 알림을 듣고 다시 읽는다.
      AuthState.beginAuthenticating();
      await tester.pumpAndSettle();

      expect(server.sent, isEmpty, reason: '왕복 중에는 보낼 토큰이 없다');
      expect(find.text('로그인이 필요해요'), findsOneWidget);
    });

    testWidgets('로그인하면 그때 읽는다 — 안내는 사라지고 요청이 나간다', (tester) async {
      AuthState.status.value = AuthStatus.unauthenticated;
      final server = _Server(status: 401, tokens: false);
      await _pump(tester, server);
      expect(server.sent, isEmpty);

      server
        ..status = 200
        ..tokens = true;
      AuthState.signInForTest(const AuthUser(id: 1, nickname: '보리엄마'));
      await tester.pumpAndSettle();

      expect(server.scheduleCalls, hasLength(1),
          reason: '상태 알림을 듣고 있어야 게스트로 열어 둔 탭이 로그인 뒤에 읽는다');
      expect(find.text('로그인이 필요해요'), findsNothing);
      expect(find.text('아직 적어 둔 일정이 없어요'), findsOneWidget);
    });
  });

  group('로그인은 했는데 서버가 401 을 준다 — 세션이 끝났다', () {
    testWidgets('연결 실패가 아니라 로그인 안내다', (tester) async {
      AuthState.signInForTest(const AuthUser(id: 1, nickname: '보리엄마'));
      final server = _Server(status: 401, tokens: true);
      await _pump(tester, server);

      expect(server.scheduleCalls, isNotEmpty, reason: '토큰이 있으니 묻기는 한다');
      expect(find.text('로그인이 필요해요'), findsOneWidget);
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('일정을 불러오지 못했어요'), findsNothing,
          reason: '401 을 연결 실패로 읽으면 "다시 시도" 가 영원히 같은 화면을 만든다');
      expect(find.text('다시 시도'), findsNothing);
    });
  });

  testWidgets('500 은 지금처럼 "다시 시도" 다 — 서버 문제는 다시 보내면 된다', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: '보리엄마'));
    final server = _Server(status: 500, tokens: true);
    await _pump(tester, server);

    expect(find.text('일정을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('로그인이 필요해요'), findsNothing);

    final before = server.scheduleCalls.length;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(server.scheduleCalls.length, before + 1, reason: '다시 시도는 정말로 다시 보낸다');
  });
}
