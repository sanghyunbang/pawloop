// 소셜 왕복 중에는 `/api/**` 가 한 건도 안 나간다 — 이슈 #673.
//
// ## 여기서 재는 것
//
// 로그아웃한 사람이 소셜 버튼을 누르면 `beginAuthenticating()` 이 상태를
// `authenticating` 으로 올리고, **그 알림이 홈 위젯들에게 간다.** 홈 위젯들은 상태가
// 바뀔 때마다 다시 읽으므로 그 순간 서버를 부른다 — 그런데 **그때는 아직 토큰이 없다.**
//
// 그 401 은 `AuthedClient` 에서 "보낼 refresh 토큰도 없다 → 세션 끝" 으로 번역되고,
// `markSessionExpired()` 가 로그인 왕복 한가운데서 세션을 끝낸다. 라우터가 `/home` 을
// `/auth/login` 페이지로 갈아 끼우면, `/home` 위에 `Navigator.push` 로 얹혀 있던
// **로그인 화면도 함께 제거된다**(Flutter `navigator.dart:1606`). 왕복이 끝나 돌아온
// `_login()` 은 `if (!mounted) return;` 에서 끝나고 `completeLogin` 이 한 번도 안 불린다.
// 사장님이 겪으신 "한 번 눌러서는 안 넘어간다" 가 이것이다.
//
// 그래서 여기서는 **요청 개수를 센다.** 문구가 아니라 숫자다 — 화면은 게스트일 때와
// 똑같이 그려지므로 그림만 보면 잡히지 않는다.
//
// 위젯 셋은 이슈가 지목한 자리 그대로다(`today_schedule_line` · `today_care_card` ·
// `neighbor_photo_strip`). 산책 피드는 위젯이 아니라 자료라 직접 부른다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/neighbor_photo_strip.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';
import 'package:heat_trip_flutter/v2/widgets/today_schedule_line.dart';

const _base = 'https://api.example.test';

/// 로그아웃 직후의 기기 — 액세스 토큰도 refresh 토큰도 없다.
///
/// 이 저장소가 중요하다. RT 가 없으면 `AuthedClient` 는 갱신을 시도조차 못 하고
/// 곧바로 "세션 끝" 으로 넘어간다(`authed_client.dart` 의 `_performRefresh`).
class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

/// 나간 요청을 세는 클라이언트. 답은 전부 401 이다 — 토큰이 없으니 서버도 그렇게 답한다.
class _Counter {
  final List<Uri> calls = <Uri>[];

  AuthedClient client({Future<void> Function()? onSessionExpired}) => AuthedClient(
        inner: MockClient((request) async {
          calls.add(request.url);
          return http.Response(
            jsonEncode({'error': {'code': 'UNAUTHORIZED'}}),
            401,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        baseUrl: _base,
        store: _NoTokens(),
        onSessionExpired: onSessionExpired,
      );
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  setUp(() {
    // **없으면 안 된다.** `markSessionExpired()` 는 상태를 내리기 **전에**
    // `clearSessionTraces()` 를 await 하고, 그것이 SharedPreferences 를 읽는다.
    // 목을 안 깔면 그 await 가 이 테스트 안에서 안 풀려서 상태가 그대로 남고,
    // 되돌리기 검증이 **고침 없이도 초록**이 된다. 실제로 그렇게 속았다.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.resetForTest();
    // 로그아웃 직후. 여기서 소셜 버튼을 누른다.
    AuthState.status.value = AuthStatus.unauthenticated;
  });
  tearDown(AuthState.resetForTest);

  group('왕복 중(authenticating)에는 토큰 없이 서버를 부르지 않는다', () {
    testWidgets('오늘 할 일 한 줄', (tester) async {
      final counter = _Counter();
      final repo = ScheduleRepository(baseUrl: _base, client: counter.client());

      await tester.pumpWidget(_host(TodayScheduleLine(
        repository: repo,
        today: DateTime(2026, 10, 15),
      )));
      await tester.pumpAndSettle();
      expect(counter.calls, isEmpty, reason: '누르기 전에도 안 부른다');

      // 소셜 버튼을 누른 순간. 이 한 줄이 상태 알림을 듣고 다시 읽는다.
      AuthState.beginAuthenticating();
      await tester.pumpAndSettle();

      expect(counter.calls, isEmpty, reason: '왕복 중에는 보낼 토큰이 없다');
    });

    testWidgets('오늘의 케어 카드', (tester) async {
      final counter = _Counter();
      final repo = FamilyRepository(baseUrl: _base, client: counter.client());

      await tester.pumpWidget(_host(TodayCareCard(repository: repo)));
      await tester.pumpAndSettle();
      expect(counter.calls, isEmpty);

      AuthState.beginAuthenticating();
      await tester.pumpAndSettle();

      expect(counter.calls, isEmpty, reason: '왕복 중에는 보낼 토큰이 없다');
    });

    testWidgets('이웃의 사진 한 줄', (tester) async {
      final counter = _Counter();
      final repo = CommunityRepository(baseUrl: _base, client: counter.client());

      await tester.pumpWidget(_host(NeighborPhotoStrip(repository: repo)));
      await tester.pumpAndSettle();
      expect(counter.calls, isEmpty);

      AuthState.beginAuthenticating();
      await tester.pumpAndSettle();

      expect(counter.calls, isEmpty, reason: '왕복 중에는 보낼 토큰이 없다');
    });

    test('산책 피드 — 위젯이 아니라 자료라 직접 부른다', () async {
      final counter = _Counter();
      final feed = WalkFeed(
        repository: WalkRepository(baseUrl: _base, client: counter.client()),
      );

      AuthState.beginAuthenticating();
      final data = await feed.load();

      expect(counter.calls, isEmpty, reason: '왕복 중에는 보낼 토큰이 없다');
      expect(data.offline, isFalse, reason: '부르지 않았으니 못 부른 것도 아니다');
    });
  });

  // 위의 것들이 가드 하나씩을 재는 것이라면, 이것은 **고리 전체**를 잰다.
  // `onSessionExpired` 를 main.dart 와 같은 모양으로 꽂아, 요청 → 401 → 세션 만료 →
  // 상태 강등까지 실제로 이어 붙인 뒤 상태가 `authenticating` 에 남아 있는지 본다.
  //
  // **setUp 의 `SharedPreferences.setMockInitialValues` 가 여기서 결정적이다.**
  // `markSessionExpired()` 는 상태를 내리기 전에 `clearSessionTraces()` 를 await 하고
  // 그것이 prefs 를 읽는다. 목이 없으면 그 await 가 이 테스트 안에서 안 풀려서, 고침을
  // 빼도 상태가 `authenticating` 그대로 남아 **초록이 나왔다.** 처음에 실제로 그렇게
  // 속았다 — 목을 깐 뒤에야 되돌리기가 빨강이 됐다.
  //
  // 재 본 결과: ㄱ 을 되돌리면 요청이 나가 첫 단언이 빨강, ㄱ·ㄴ 을 함께 되돌리면
  // 상태 단언까지 빨강이다. ㄴ 만 되돌리면 ㄱ 이 요청을 막아 여기까지 오지 않으므로
  // 초록이고, 그쪽은 `auth_state_test.dart` 의 단위 테스트가 따로 잠근다.
  testWidgets('왕복 중에 401 이 들어와도 로그인 화면을 뺏지 않는다', (tester) async {
    final counter = _Counter();
    final repo = FamilyRepository(
      baseUrl: _base,
      client: counter.client(onSessionExpired: AuthState.markSessionExpired),
    );

    await tester.pumpWidget(_host(TodayCareCard(repository: repo)));
    await tester.pumpAndSettle();

    AuthState.beginAuthenticating();
    await tester.pumpAndSettle();
    expect(counter.calls, isEmpty, reason: '고침이 다 살아 있으면 요청 자체가 안 나간다');

    expect(
      AuthState.status.value,
      AuthStatus.authenticating,
      reason: '여기서 unauthenticated 가 되면 라우터가 /home 을 갈아 끼우고 '
          '그 위에 얹힌 로그인 화면이 함께 사라진다',
    );
    expect(
      AuthState.sessionEnded,
      isFalse,
      reason: '왕복 중에 들어온 401 은 "끝났다" 가 아니라 "아직 시작을 안 했다" 이다',
    );
  });
}
