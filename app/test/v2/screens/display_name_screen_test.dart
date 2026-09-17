// 표시 이름 바꾸기 — 이슈 #665.
//
// 재는 것은 "이름이 바뀌었다고 믿게 만드는 자리" 셋이다.
//
//  1. 빈 이름은 **나가지 않는다.** 서버는 빈 닉네임을 "안 바꿈" 으로 읽고 200 을 주므로,
//     보내면 아무것도 안 바뀌었는데 화면이 "바꿨어요" 라고 말하고 닫힌다.
//  2. 저장이 실패하면 **화면이 안 닫힌다.** 닫히면 옛 이름으로 글을 쓰면서 새 이름이라고 믿는다.
//  3. 저장이 성공하면 `AuthState` 의 이름이 **그 자리에서** 바뀐다. 안 그러면 프로필도 홈도
//     옛 이름을 계속 그린다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/profile_store.dart';
import 'package:heat_trip_flutter/v2/screens/display_name_screen.dart';

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

typedef _Reply = http.Response Function(http.Request request);

http.Response _json(String body, int code) => http.Response(
      body,
      code,
      // 한글 문구가 그대로 돌아오게 — 이 헤더가 없으면 본문이 latin1 로 실린다.
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 서버가 보낸 닉네임을 그대로 돌려주는 `PUT /auth/me` 200. 실제 응답이 갱신된 `User` 다.
http.Response _echo(http.Request request) {
  final sent = jsonDecode(request.body) as Map<String, dynamic>;
  return _json(
    jsonEncode({
      'id': 7,
      'nickname': sent['nickname'],
      'email': 'me@example.test',
    }),
    200,
  );
}

ProfileStore _store(List<http.Request> sent, _Reply reply) => ProfileStore(
      client: AuthedClient(
        inner: MockClient((request) async {
          sent.add(request);
          return reply(request);
        }),
        baseUrl: 'https://api.example.test',
        store: _Tokens(),
      ),
      baseUrl: 'https://api.example.test',
    );

final _field = find.byKey(const Key('display-name-field'));
final _save = find.byKey(const Key('display-name-save'));

/// 화면을 **얹어서** 연다 — 닫혔는지 안 닫혔는지를 재려면 밑에 다른 화면이 있어야 한다.
Future<List<http.Request>> _pump(WidgetTester t, _Reply reply) async {
  final sent = <http.Request>[];
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DisplayNameScreen(store: _store(sent, reply)),
            )),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
  return sent;
}

void main() {
  setUp(() => AuthState.signInForTest(const AuthUser(id: 7, nickname: '카카오닉')));
  tearDown(AuthState.resetForTest);

  testWidgets('지금 이름이 미리 들어 있다', (t) async {
    await _pump(t, _echo);

    expect(find.text('카카오닉'), findsOneWidget,
        reason: '빈 칸으로 시작하면 무엇을 바꾸는 중인지 안 보인다');
  });

  testWidgets('빈 이름은 저장하지 않는다 — 이유를 말하고 화면도 안 닫힌다', (t) async {
    final sent = await _pump(t, _echo);

    await t.enterText(_field, '');
    await t.tap(_save);
    await t.pumpAndSettle();

    expect(sent, isEmpty,
        reason: '서버는 빈 닉네임을 "안 바꿈" 으로 읽고 200 을 준다 — 보내면 화면이 거짓말을 한다');
    expect(find.textContaining('비워 둘 수 없어요'), findsOneWidget);
    expect(find.byType(DisplayNameScreen), findsOneWidget);
    expect(AuthState.user!.nickname, '카카오닉');
  });

  testWidgets('공백만 친 것도 빈 이름이다', (t) async {
    final sent = await _pump(t, _echo);

    await t.enterText(_field, '   ');
    await t.tap(_save);
    await t.pumpAndSettle();

    expect(sent, isEmpty);
    expect(find.textContaining('비워 둘 수 없어요'), findsOneWidget);
  });

  testWidgets('저장이 실패하면 화면이 안 닫히고 서버가 말한 이유가 남는다', (t) async {
    final sent = await _pump(
      t,
      (_) => _json(
        '{"error":{"code":"BAD_REQUEST","message":"닉네임은 20자를 넘을 수 없습니다."}}',
        400,
      ),
    );

    await t.enterText(_field, '새이름');
    await t.tap(_save);
    await t.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(find.byType(DisplayNameScreen), findsOneWidget,
        reason: '바뀐 줄 알고 나가면 옛 이름으로 글을 쓰게 된다');
    expect(find.text('닉네임은 20자를 넘을 수 없습니다.'), findsOneWidget,
        reason: '상한은 서버가 정본이라 서버 문구를 그대로 보여 준다');
    expect(AuthState.user!.nickname, '카카오닉');
  });

  testWidgets('응답이 아예 없어도 화면이 안 닫힌다 — 연결을 말한다', (t) async {
    await _pump(t, (_) => throw const SocketishFailure());

    await t.enterText(_field, '새이름');
    await t.tap(_save);
    await t.pumpAndSettle();

    expect(find.byType(DisplayNameScreen), findsOneWidget);
    expect(find.textContaining('연결을 확인'), findsOneWidget);
    expect(AuthState.user!.nickname, '카카오닉');
  });

  testWidgets('실패한 뒤 다시 시도할 수 있다', (t) async {
    var fail = true;
    final sent = await _pump(t, (request) {
      if (fail) {
        fail = false;
        return _json('{}', 500);
      }
      return _echo(request);
    });

    await t.enterText(_field, '길동이아빠');
    await t.tap(_save);
    await t.pumpAndSettle();
    expect(find.byType(DisplayNameScreen), findsOneWidget);

    await t.tap(_save);
    await t.pumpAndSettle();

    expect(sent, hasLength(2));
    expect(AuthState.user!.nickname, '길동이아빠');
  });

  testWidgets('저장이 성공하면 AuthState 의 이름이 바뀌고 화면이 닫힌다', (t) async {
    final sent = await _pump(t, _echo);
    final before = AuthState.userRev.value;

    await t.enterText(_field, '길동이아빠');
    await t.tap(_save);
    await t.pumpAndSettle();

    expect(jsonDecode(sent.single.body), {'nickname': '길동이아빠'},
        reason: '표시 이름 하나만 보낸다 — 나머지 칸은 null 이 "안 바꿈" 이다');
    expect(AuthState.user!.nickname, '길동이아빠');
    expect(AuthState.user!.displayName, '길동이아빠');
    expect(AuthState.userRev.value, greaterThan(before),
        reason: '듣고 있는 화면이 다시 그려야 홈과 프로필이 즉시 새 이름을 보인다');
    expect(find.byType(DisplayNameScreen), findsNothing);
  });

  testWidgets('앞뒤 공백은 떼고 보낸다', (t) async {
    final sent = await _pump(t, _echo);

    await t.enterText(_field, '  길동이아빠  ');
    await t.tap(_save);
    await t.pumpAndSettle();

    expect(jsonDecode(sent.single.body), {'nickname': '길동이아빠'});
  });

  testWidgets('상한을 넘겨 칠 수 없다 — 앱이 먼저 막는다', (t) async {
    const max = ProfileStore.maxNicknameLength;
    final sent = await _pump(t, _echo);

    await t.enterText(_field, '가' * (max + 5));
    await t.pump();

    expect(find.text('$max/$max'), findsOneWidget);

    await t.tap(_save);
    await t.pumpAndSettle();

    expect((jsonDecode(sent.single.body) as Map)['nickname'], '가' * max);
  });

  testWidgets('이미 쓴 글의 이름은 안 바뀐다고 화면이 말한다', (t) async {
    await _pump(t, _echo);

    expect(find.textContaining('이미 쓴 글'), findsOneWidget,
        reason: 'post.handle 과 chat_message.sender_name 은 그때의 이름을 찍어 둔다');
  });
}

/// `MockClient` 안에서 던질 것 — 실제로는 `SocketException` 이 오는 자리다.
/// 그 타입을 쓰려면 `dart:io` 가 필요한데, 이 테스트가 보려는 것은 **예외의 종류가 아니라
/// 응답이 없을 때의 화면**이라 아무 예외로도 같은 길을 지난다.
class SocketishFailure implements Exception {
  const SocketishFailure();
}
