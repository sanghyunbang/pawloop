// app/tool/live_community_check.dart
//
// **살아 있는 백엔드에 대고 도는 확인.** CI 에서 안 돈다 — `flutter test` 는 `test/` 만
// 훑고 이 파일은 거기 없다. 손으로 부를 때만 돈다:
//
//   1) backend: ./gradlew bootRun --args='--spring.profiles.active=dev'
//   2) app:     flutter test tool/live_community_check.dart
//
// ## 왜 필요한가
//
// 이슈 #172 의 완료 조건 2가 **"앱에서 글을 하나 쓴 뒤 DB 의 `post` 표에 그 행이 있는
// 것을 눈으로 확인한다"** 이다. `test/` 의 위젯 테스트는 `MockClient` 를 꽂아 서버를
// 흉내 낸다 — 그건 앱이 만든 요청의 **모양**을 지키지만 서버가 그것을 받아들이는지는
// 모른다. curl 은 반대로 서버를 지키지만 앱 화면을 안 지난다.
//
// 여기서는 **진짜 위젯**(`PostWriteScreen`)을 띄우고, 탭·입력을 위젯 트리로 하고,
// HTTP 는 `AuthedClient` 가 실제 소켓으로 내보낸다. 남는 것은 렌더링뿐이고 그건
// 실기기 확인(#198)의 몫이다.
//
// ## 두 가지 함정 — 둘 다 실제로 밟았다
//
// 1. `flutter_test` 는 모든 HTTP 를 400 으로 막는다(`HttpOverrides.global`). **테스트
//    본문 안에서** 풀어야 한다 — 바인딩이 초기화되며 자기 오버라이드를 다시 깔아서
//    `main()` 첫 줄에서 풀면 덮인다.
// 2. `testWidgets` 는 **가짜 시간**에서 돈다. 진짜 소켓의 콜백은 그 존에서 안 깨어나서
//    `pump()` 를 아무리 돌려도 응답이 영원히 안 온다(10분 타임아웃을 실제로 봤다).
//    진짜 통신을 하는 구간은 전부 `tester.runAsync(...)` 안이어야 한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

const _base = 'http://localhost:8080';

/// 이번 실행에서 만든 계정의 토큰을 들고 있는 저장소.
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

void main() {
  testWidgets('진짜 화면 → 진짜 서버 → DB', (tester) async {
    HttpOverrides.global = null;

    final store = _LiveTokenStore();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final email = 'live-172-$stamp@example.test';

    // 1) 계정을 만들고 로그인한다.
    //    앱의 로그인 화면은 소셜이라 여기서는 계약의 이메일 경로를 쓴다.
    await tester.runAsync(() async {
      final signup = await http.post(
        Uri.parse('$_base/auth/signup'),
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
        body: utf8.encode(jsonEncode({
          'email': email,
          'password': 'Passw0rd!live',
          'nickname': '라이브확인',
          'name': 'Live',
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
      store.access = tokens['accessToken'] as String?;
      store.refresh = tokens['refreshToken'] as String?;
    });

    final repo = CommunityRepository(
      baseUrl: _base,
      client: AuthedClient(inner: http.Client(), store: store, baseUrl: _base),
    );

    // 2) 진짜 글쓰기 화면을 띄운다.
    CommunityPost? written;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            written = await Navigator.of(context).push<CommunityPost>(
              MaterialPageRoute(
                builder: (_) => PostWriteScreen(
                  repository: repo,
                  loc: '서울숲',
                  contentId: '126508',
                ),
              ),
            );
          },
          child: const Text('열기'),
        );
      }),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 3) 사람이 하는 것과 같은 순서로 만진다.
    expect(find.text('서울숲'), findsOneWidget);
    expect(find.text('장소 연결됨'), findsOneWidget);

    await tester.tap(find.text('산책로 후기'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '라이브 확인 $stamp');
    await tester.enterText(
        find.byType(TextField).last, '진짜 서버에 실제로 들어갔는지 보는 글입니다.');

    // 여기부터가 진짜 통신이다. 가짜 시간에서는 응답이 영원히 안 온다.
    await tester.runAsync(() async {
      await tester.tap(find.text('올리기'));
      for (var i = 0; i < 100 && written == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    // 4) 서버가 준 것을 본다.
    expect(written, isNotNull, reason: '화면이 새 글을 돌려주지 못했다');
    expect(written!.board, CommunityBoard.walkReview);
    expect(written!.contentId, '126508');
    expect(written!.loc, '서울숲');
    expect(written!.author.isWithdrawn, isFalse);
    expect(written!.author.nickname, '라이브확인');

    // 5) 게스트로 다시 읽어 목록에 있는지 본다 — 토큰 없는 클라이언트다.
    await tester.runAsync(() async {
      final guest = CommunityRepository(
        baseUrl: _base,
        client: AuthedClient(
            inner: http.Client(), store: _LiveTokenStore(), baseUrl: _base),
      );
      final page = await guest.feed(board: CommunityBoard.walkReview);
      final mine = page.items.where((p) => p.id == written!.id);

      expect(mine, hasLength(1), reason: '방금 쓴 글이 목록에 보여야 한다(완료 조건 6)');
      expect(mine.single.reactions.mine, isNull,
          reason: '게스트에게는 mine 이 null 이다');
      expect(mine.single.title, '라이브 확인 $stamp');
    });

    // 사람이 DB 에서 찾을 수 있게 id 를 남긴다.
    // ignore: avoid_print
    print('LIVE_CHECK post.id=${written!.id} title=${written!.title}');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
