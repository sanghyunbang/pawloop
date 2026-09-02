// app/tool/live_family_check.dart
//
// **살아 있는 백엔드에 대고 도는 확인** — 이슈 #196 완료 조건 1~3.
// CI 에서 안 돈다(`flutter test` 는 `test/` 만 훑는다). 손으로 부를 때만 돈다:
//
//   1) backend: ./gradlew bootRun --args='--spring.profiles.active=dev'
//   2) app:     flutter test tool/live_family_check.dart
//
// `test/` 의 위젯 테스트는 `MockClient` 로 서버를 흉내 낸다 — 요청의 **모양**은 지키지만
// 서버가 받아들이는지는 모른다. 여기서는 **진짜 `FamilyScreen`** 을 띄우고 탭·입력을 위젯
// 트리로 하고, HTTP 는 `AuthedClient` 가 실제 소켓으로 내보낸다.
//
// 함정 둘은 `live_community_check.dart` 머리말에 적어 뒀다 — `HttpOverrides` 는 테스트 본문
// 안에서 풀어야 하고, 진짜 통신은 전부 `tester.runAsync(...)` 안이어야 한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/screens/family_screen.dart';

const _base = 'http://localhost:8080';

class _LiveTokenStore implements AuthTokenStore {
  String? access;
  String? refresh;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    access = accessToken;
    refresh = refreshToken ?? refresh;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

Future<_LiveTokenStore> _signUp(String tag, int stamp) async {
  final email = 'live-196-$tag-$stamp@example.test';
  final signup = await http.post(
    Uri.parse('$_base/auth/signup'),
    headers: const {'Content-Type': 'application/json; charset=utf-8'},
    body: utf8.encode(jsonEncode({
      'email': email,
      'password': 'Passw0rd!live',
      'nickname': tag,
      'name': tag,
      'gender': 'male',
      'ageGroup': 'over14',
      'agreeTos': true,
      'agreePrivacy': true,
      'agreeMarketing': false,
      'tosVersion': 'v1.0',
      'privacyVersion': 'v1.0',
    })),
  );
  expect(signup.statusCode, 201, reason: '백엔드가 안 떠 있으면 여기서 멈춘다');

  final login = await http.post(
    Uri.parse('$_base/auth/login'),
    headers: const {'Content-Type': 'application/json; charset=utf-8'},
    body: utf8.encode(jsonEncode({'email': email, 'password': 'Passw0rd!live'})),
  );
  expect(login.statusCode, 200);
  final tokens = jsonDecode(utf8.decode(login.bodyBytes)) as Map<String, Object?>;
  return _LiveTokenStore()
    ..access = tokens['accessToken'] as String?
    ..refresh = tokens['refreshToken'] as String?;
}

FamilyRepository _repoFor(_LiveTokenStore store) => FamilyRepository(
      baseUrl: _base,
      client: AuthedClient(inner: http.Client(), store: store, baseUrl: _base),
    );

void main() {
  testWidgets('진짜 화면 → 진짜 서버 → 가족 그룹과 초대 코드', (tester) async {
    HttpOverrides.global = null;

    final stamp = DateTime.now().microsecondsSinceEpoch;
    late _LiveTokenStore owner;
    late _LiveTokenStore mate;

    await tester.runAsync(() async {
      owner = await _signUp('아빠$stamp', stamp);
      mate = await _signUp('엄마$stamp', stamp + 1);
    });

    final repo = _repoFor(owner);

    // 1) 그룹이 없는 계정으로 화면을 연다.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FamilyScreen(repository: repo)),
    ));
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (find.text('가족 그룹 만들기').evaluate().isNotEmpty) break;
      }
    });

    expect(find.text('아직 가족 그룹이 없어요'), findsOneWidget);
    expect(find.text('가족 그룹 만들기'), findsOneWidget,
        reason: '완료 조건 1 — 여기가 비어 있던 자리다');
    expect(find.text('초대 코드로 참여하기'), findsOneWidget);

    // 2) 사람이 하는 순서로 만든다.
    await tester.tap(find.text('가족 그룹 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '라이브 가족 $stamp');

    await tester.runAsync(() async {
      await tester.tap(find.text('만들기'));
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (find.text('가족 초대').evaluate().isNotEmpty) break;
      }
    });

    // 3) 만들자마자 초대 시트가 뜬다 — 완료 조건 2.
    expect(find.text('가족 초대'), findsOneWidget,
        reason: '만들고 나면 초대 코드가 보여야 한다');

    String? code;
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final t = w.data;
      if (t != null && RegExp(r'^[A-Z0-9-]{4,}$').hasMatch(t)) {
        code = t;
        break;
      }
    }
    expect(code, isNotNull, reason: '초대 코드가 화면에 없다');

    // 4) 다른 계정이 그 코드로 참여한다 — 완료 조건 3.
    await tester.runAsync(() async {
      final join = await http.post(
        Uri.parse('$_base/api/chat/invites/$code/join'),
        headers: {'Authorization': 'Bearer ${mate.access}'},
      );
      expect(join.statusCode, anyOf(200, 201),
          reason: '초대 코드로 참여가 안 되면 혼자 쓰는 그룹이다');

      // 참여한 사람도 같은 그룹을 본다.
      final mateGroup = await _repoFor(mate).myGroup();
      final ownerGroup = await repo.myGroup();
      expect(mateGroup.id, ownerGroup.id);
      expect(mateGroup.members.length, 2,
          reason: '서로의 케어 기록이 보이려면 같은 그룹의 멤버여야 한다');

      // ignore: avoid_print
      print('LIVE_CHECK group.id=${ownerGroup.id} room=${ownerGroup.roomId} '
          'code=$code members=${mateGroup.members.length}');
    });
  }, timeout: const Timeout(Duration(seconds: 120)));
}
