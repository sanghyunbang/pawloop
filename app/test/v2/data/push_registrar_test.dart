// 언제 기기 토큰을 서버에 보내나 (#83) — 규칙 셋을 firebase 없이 잰다.
//
// 1. 로그인한 사람의 것만 · 2. 나중에 로그인돼도 · 3. FCM 이 토큰을 바꾸면 다시. 그리고 같은
// (토큰, 사람) 은 한 번만이다.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/push_registrar.dart';

class _FakeTokens implements PushTokenSource {
  _FakeTokens(this.token);

  String? token;
  final _refreshes = StreamController<String>.broadcast();

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  void refresh(String next) {
    token = next;
    _refreshes.add(next);
  }
}

class _Harness {
  _Harness({
    String? token = 'T1',
    AuthStatus status = AuthStatus.unknown,
    this.userId,
    this.accept = true,
  })  : tokens = _FakeTokens(token),
        status = ValueNotifier<AuthStatus>(status);

  final _FakeTokens tokens;
  final ValueNotifier<AuthStatus> status;
  int? userId;
  bool accept;
  final sent = <String>[];

  late final registrar = PushRegistrar(
    tokens: tokens,
    register: (token) async {
      sent.add(token);
      return accept;
    },
    status: status,
    userId: () => userId,
  );

  Future<void> start() async {
    await registrar.start();
    await settle();
  }

  /// 스트림·리스너가 돈 뒤까지 기다린다 — 시계는 안 쓴다.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> login(int id) async {
    userId = id;
    status.value = AuthStatus.authenticated;
    await settle();
  }
}

void main() {
  test('게스트면 보내지 않는다 — 서버에 주인이 없는 토큰이다', () async {
    final h = _Harness(status: AuthStatus.unauthenticated);
    await h.start();
    expect(h.sent, isEmpty);

    h.status.value = AuthStatus.authenticating;
    await h.settle();
    expect(h.sent, isEmpty, reason: '소셜 왕복 중도 토큰이 없다(#673)');
  });

  test('온보딩 중도 안 보낸다 — 끝나는 순간을 듣는다', () async {
    final h = _Harness(status: AuthStatus.onboarding, userId: 3);
    await h.start();
    expect(h.sent, isEmpty);

    h.status.value = AuthStatus.authenticated;
    await h.settle();
    expect(h.sent, ['T1']);
  });

  test('앱을 켤 때 이미 로그인돼 있으면 한 번 보낸다 — 상태가 흔들려도 한 번이다', () async {
    final h = _Harness(status: AuthStatus.authenticated, userId: 3);
    await h.start();
    expect(h.sent, ['T1']);
    expect(h.registrar.sent, (token: 'T1', userId: 3));

    h.status.value = AuthStatus.onboarding;
    h.status.value = AuthStatus.authenticated;
    await h.settle();
    expect(h.sent, ['T1'], reason: '같은 토큰·같은 사람이면 요청은 하나다');
  });

  test('나중에 로그인되면 그때 보낸다 — AuthState.init 이 서버에 묻는 동안은 unknown 이다', () async {
    final h = _Harness();
    await h.start();
    expect(h.sent, isEmpty);

    await h.login(3);
    expect(h.sent, ['T1']);
  });

  test('FCM 이 토큰을 바꾸면 다시 보낸다 — 옛 토큰으로는 발송이 죽는다', () async {
    final h = _Harness(status: AuthStatus.authenticated, userId: 3);
    await h.start();

    h.tokens.refresh('T2');
    await h.settle();

    expect(h.sent, ['T1', 'T2']);
  });

  test('게스트일 때 바뀐 토큰은 로그인 뒤에 간다', () async {
    final h = _Harness(status: AuthStatus.unauthenticated);
    await h.start();
    h.tokens.refresh('T2');
    await h.settle();
    expect(h.sent, isEmpty);

    await h.login(3);
    expect(h.sent, ['T2'], reason: '마지막 토큰으로 간다 — 옛 T1 이 아니다');
  });

  test('다른 계정으로 다시 로그인하면 또 보낸다 — 서버가 주인을 바꾼다', () async {
    final h = _Harness(status: AuthStatus.authenticated, userId: 3);
    await h.start();
    expect(h.sent, ['T1']);

    h.status.value = AuthStatus.unauthenticated;
    h.userId = null;
    await h.settle();
    await h.login(4);

    expect(h.sent, ['T1', 'T1'], reason: '같은 토큰이라도 사람이 다르면 다시 보낸다');
  });

  test('같은 계정으로 다시 로그인해도 또 보낸다 — 로그아웃은 전 기기라 서버가 토큰을 폐기했다 (2026-09-21)', () async {
    final h = _Harness(status: AuthStatus.authenticated, userId: 2);
    await h.start();
    expect(h.sent, ['T1']);

    // 다른 기기(윈도우)에서 같은 계정을 로그아웃 → 서버가 이 사람의 토큰을 전부 폐기 → 이 기기도 결국 로그아웃.
    h.status.value = AuthStatus.unauthenticated;
    await h.settle();
    await h.login(2);

    expect(h.sent, ['T1', 'T1'],
        reason: '"이미 보냈다" 를 잊지 않으면 다시 로그인하고도 조용히 알림을 못 받는 기기가 된다 — 실기기가 그랬다');
  });

  test('실패했으면 다음 계기에 다시 간다', () async {
    final h = _Harness(status: AuthStatus.authenticated, userId: 3, accept: false);
    await h.start();
    expect(h.sent, ['T1']);
    expect(h.registrar.sent, isNull);

    h.accept = true;
    h.status.value = AuthStatus.onboarding;
    h.status.value = AuthStatus.authenticated;
    await h.settle();

    expect(h.sent, ['T1', 'T1']);
    expect(h.registrar.sent, (token: 'T1', userId: 3));
  });

  test('토큰이 아직 없으면 안 보내고, 오면 보낸다', () async {
    final h = _Harness(token: null, status: AuthStatus.authenticated, userId: 3);
    await h.start();
    expect(h.sent, isEmpty);

    h.tokens.refresh('T9');
    await h.settle();
    expect(h.sent, ['T9']);
  });

  test('보내는 중에 신호가 겹쳐도 한 번에 하나 — 끝난 뒤 다시 본다', () async {
    final gate = Completer<bool>();
    final sent = <String>[];
    final tokens = _FakeTokens('T1');
    final status = ValueNotifier<AuthStatus>(AuthStatus.authenticated);
    var calls = 0;
    final registrar = PushRegistrar(
      tokens: tokens,
      register: (token) {
        sent.add(token);
        calls++;
        return calls == 1 ? gate.future : Future.value(true);
      },
      status: status,
      userId: () => 3,
    );
    final started = registrar.start();
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['T1'], reason: '첫 요청이 나가 있다(아직 안 끝남)');

    tokens.refresh('T2');
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['T1'], reason: '겹친 신호는 줄을 선다');

    gate.complete(true);
    await started;
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['T1', 'T2'], reason: '끝난 뒤 바뀐 토큰을 본다');
  });

  test('dispose 뒤에는 듣지 않는다', () async {
    final h = _Harness();
    await h.start();
    h.registrar.dispose();

    await h.login(3);
    h.tokens.refresh('T2');
    await h.settle();

    expect(h.sent, isEmpty);
  });

  test('기본은 AuthState 를 듣는다 — 진짜 로그인 상태에 붙는다', () async {
    AuthState.resetForTest();
    addTearDown(AuthState.resetForTest);
    final sent = <String>[];
    final registrar = PushRegistrar(
      tokens: _FakeTokens('T1'),
      register: (token) async {
        sent.add(token);
        return true;
      },
    );
    addTearDown(registrar.dispose);

    await registrar.start();
    await Future<void>.delayed(Duration.zero);
    expect(sent, isEmpty, reason: '아직 unknown 이다');

    AuthState.signInForTest(const AuthUser(id: 5));
    await Future<void>.delayed(Duration.zero);

    expect(sent, ['T1']);
    expect(registrar.sent, (token: 'T1', userId: 5));
  });
}
