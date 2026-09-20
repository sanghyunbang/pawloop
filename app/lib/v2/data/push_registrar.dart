// lib/v2/data/push_registrar.dart
//
// 언제 기기 토큰을 서버에 보내나 — 이슈 #83.
//
// ## 규칙 셋
//
//  1. **로그인한 사람의 것만** 보낸다. 게스트의 토큰은 서버에 주인이 없다 — 보내면 401 이고,
//     그 401 을 세션이 끝난 것으로 읽는 길이 있다(#11). 온보딩 중도 안 보낸다 — 아직 가족이
//     없어서 받을 알림이 없고, 끝나는 순간을 아래 2 가 듣는다.
//  2. 로그인이 **나중에** 되어도 보낸다. 앱을 켤 때 `AuthState.init` 이 서버에 물어보는 동안은
//     `unknown` 이라 그 순간에는 못 보내고, 확정되는 순간을 듣는다. 다른 계정으로 다시
//     로그인하면 또 보낸다 — 서버가 토큰의 주인을 바꾼다.
//  3. FCM 이 토큰을 **바꾸면** 다시 보낸다. 옛 토큰으로는 발송이 죽고 서버가 그것을 폐기하므로,
//     새 것을 안 보내면 이 기기는 조용히 알림을 못 받는 기기가 된다.
//
// 같은 (토큰, 사람) 은 **한 번만** — 상태 알림이 여러 번 와도(온보딩 → 인증, 프로필 수정) 요청은
// 하나다. 실패했으면 다음 계기에 다시 간다.
//
// ## 왜 firebase 를 모르나
//
// 토큰을 주는 쪽을 [PushTokenSource] 로 떼어 두면 이 규칙 셋을 플러그인 없이 잰다. 진짜는
// `firebase_push.dart` 가 FCM 으로 꽂는다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_state.dart';

/// 토큰을 주는 쪽. 진짜는 FCM, 테스트는 가짜.
abstract interface class PushTokenSource {
  /// 지금 토큰. 아직 없거나 못 받으면 null — 던지지 않는다.
  Future<String?> currentToken();

  /// FCM 이 토큰을 바꿀 때마다 새 값.
  Stream<String> get tokenRefreshes;
}

class PushRegistrar {
  PushRegistrar({
    required PushTokenSource tokens,
    required Future<bool> Function(String token) register,
    ValueListenable<AuthStatus>? status,
    int? Function()? userId,
  })  : _tokens = tokens,
        _register = register,
        _status = status ?? AuthState.status,
        _userId = userId ?? (() => AuthState.user?.id);

  final PushTokenSource _tokens;
  final Future<bool> Function(String token) _register;
  final ValueListenable<AuthStatus> _status;
  final int? Function() _userId;

  String? _token;
  ({String token, int userId})? _sent;
  StreamSubscription<String>? _refreshes;
  bool _busy = false;
  bool _again = false;

  /// 마지막으로 서버에 둔 (토큰, 사람). 없으면 null.
  @visibleForTesting
  ({String token, int userId})? get sent => _sent;

  /// 듣기 시작한다. 지금 토큰을 한 번 읽고, 그 뒤로는 로그인 상태와 토큰 갱신을 듣는다.
  Future<void> start() async {
    _status.addListener(_onSignal);
    _refreshes = _tokens.tokenRefreshes.listen((token) {
      _token = token;
      _onSignal();
    });
    final token = await _tokens.currentToken();
    if (token != null && token.isNotEmpty) {
      _token = token;
    }
    await _settle();
  }

  void dispose() {
    _status.removeListener(_onSignal);
    _refreshes?.cancel();
    _refreshes = null;
  }

  void _onSignal() => unawaited(_settle());

  /// 한 번에 하나만 보낸다. 보내는 중에 신호가 또 오면 끝난 뒤 다시 본다 — 그 사이 토큰이나 사람이
  /// 바뀌었을 수 있고, 안 바뀌었으면 아래 비교가 걸러 낸다.
  Future<void> _settle() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _registerIfNeeded();
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  Future<void> _registerIfNeeded() async {
    final token = _token;
    final userId = _userId();
    if (token == null || userId == null || _status.value != AuthStatus.authenticated) return;
    final sent = _sent;
    if (sent != null && sent.token == token && sent.userId == userId) return;
    if (await _register(token)) {
      _sent = (token: token, userId: userId);
    }
  }
}
