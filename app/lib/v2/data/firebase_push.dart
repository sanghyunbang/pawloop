// lib/v2/data/firebase_push.dart
//
// Firebase 를 아는 **유일한** 파일 — 이슈 #83. 순수 테스트가 이것을 import 하지 않는다(플러그인은
// 테스트 바인딩에 채널이 없어 던진다). 규칙은 옆 파일들에 있다 — 언제 토큰을 보내나는
// `push_registrar.dart`, 무슨 data 가 오면 어디로 가나는 `push_route.dart`.
//
// ## Firebase 가 없어도 앱은 뜬다
//
// `google-services.json` 은 저장소 밖이다(.gitignore). 그 파일 없이 빌드한 앱에서
// `Firebase.initializeApp()` 은 던진다 — 여기서 잡고 푸시만 끈다. 서버가 키 없이 뜨는 것과 같은
// 태도다(`PushConfig` — "키 파일 하나 때문에 채팅·산책·가족이 전부 안 뜨는 것보다 알림만 안 가는
// 쪽이 낫다").
//
// ## 앞에 있을 때와 뒤에 있을 때
//
// 뒤에 있거나 꺼져 있을 때 온 푸시는 FCM 이 직접 띄운다(매니페스트가 가리키는 `push` 채널). 누르면
// `onMessageOpenedApp`(떠 있었음) 이나 `getInitialMessage`(꺼져 있었음) 로 오고, 둘 다
// `offerFromNotification` 으로 보낸다 — 기기 알림을 누른 것과 같은 길이다. 앞에 있을 때는 아무도
// 안 띄우므로 `LocalNotificationSink.showPush` 가 같은 제목·본문으로 한 장 띄운다(안드로이드).
// iOS 는 앞에 있을 때도 시스템이 띄우게 둔다(`setForegroundNotificationPresentationOptions`) —
// 우리가 또 띄우면 두 장이다.
//
// ## 알림 권한은 로그인한 뒤에
//
// 앱을 처음 여는 사람에게 권한부터 묻지 않는다(기기 알림과 같은 태도). 토큰을 **처음 서버에 보내는
// 순간** — 로그인한 사람이 생긴 순간 — 에 한 번 묻는다. 안드로이드 13+ 와 iOS 는 이 권한이 없으면
// 토큰이 있어도 화면에 아무것도 안 뜬다.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'local_notification_sink.dart';
import 'notification_route.dart';
import 'push_registrar.dart';
import 'push_route.dart';
import 'push_token_repository.dart';

class FirebasePush {
  FirebasePush._();

  static bool _started = false;
  static bool _askedPermission = false;
  static PushRegistrar? _registrar;

  /// 계약의 `platform`.
  static String get platformName =>
      Platform.isIOS ? PushTokenRepository.ios : PushTokenRepository.android;

  /// 앱 시작 때 한 번. 첫 프레임을 기다리게 하지 않는다 — `main` 이 `unawaited` 로 부른다.
  static Future<void> start({
    LocalNotificationSink? sink,
    PushTokenRepository? tokens,
  }) async {
    if (_started) return;
    _started = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Push] Firebase 없음 — 푸시 꺼짐 (${e.runtimeType})');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    final notifications = sink ?? LocalNotificationSink();
    final repository = tokens ?? PushTokenRepository();

    try {
      await notifications.ensurePushChannel();
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      debugPrint('[Push] 채널 준비 실패 (${e.runtimeType})');
    }

    _registrar = PushRegistrar(
      tokens: _FcmTokenSource(messaging),
      register: (token) async {
        await _askPermissionOnce(messaging);
        return repository.register(token, platform: platformName);
      },
    );
    unawaited(_registrar!.start());

    // 앞에 떠 있을 때 — 우리가 띄운다(안드로이드). iOS 는 시스템이 띄운다(위 주석).
    FirebaseMessaging.onMessage.listen((message) {
      if (Platform.isIOS) return;
      final notice = foregroundNoticeOf(
        data: message.data,
        title: message.notification?.title,
        body: message.notification?.body,
      );
      if (notice == null) return;
      unawaited(notifications.showPush(notice));
    });

    // 뒤에 있다가 눌려서 앞으로 왔다.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => offerFromNotification(pushPayloadOf(message.data)),
    );

    // 꺼져 있다가 푸시로 떴다 — 홈이 떠서 가져갈 때까지 상자가 들고 있는다.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        offerFromNotification(pushPayloadOf(initial.data));
      }
    } catch (e) {
      debugPrint('[Push] 시작 메시지를 못 읽었다 (${e.runtimeType})');
    }
  }

  static Future<void> _askPermissionOnce(FirebaseMessaging messaging) async {
    if (_askedPermission) return;
    _askedPermission = true;
    try {
      final settings = await messaging.requestPermission();
      debugPrint('[Push] 알림 권한 ${settings.authorizationStatus.name}');
    } catch (e) {
      debugPrint('[Push] 권한을 못 물었다 (${e.runtimeType})');
    }
  }
}

class _FcmTokenSource implements PushTokenSource {
  _FcmTokenSource(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<String?> currentToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      // 구글 서비스가 없는 기기(일부 에뮬레이터·중국 단말)는 여기서 던진다 — 푸시만 없다.
      debugPrint('[Push] 토큰을 못 받았다 (${e.runtimeType})');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;
}
