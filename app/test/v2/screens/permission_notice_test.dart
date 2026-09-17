// 접근권한 안내 — 이슈 #682.
//
// ## 여기서 재는 것
//
//  1. 필수와 선택이 **나뉘어 보인다** — 정보통신망법 제22조의2 제1항이 나누라고 한다.
//  2. 선택 절에 **"동의하지 않아도 앱을 쓸 수 있어요"** 가 있다 — 같은 조항이 그 사실을
//     알리라고 한다. 이 문장이 사라지면 화면이 있어도 요건을 못 채운다.
//  3. 설정 > 앱 에서 들어가진다.
//  4. 첫 실행(소개 끝)에 한 번 지나간다 — 건너뛰기로 끝내도 지나간다.
//  5. **목록이 매니페스트·plist 와 어긋나지 않는다.** 권한을 새로 선언하고 고지를 잊으면
//     여기가 빨간불이다. 고지 화면은 한 번 쓰고 잊히기 쉬워서 사람 기억에 맡기지 않는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/intro_screen.dart';
import 'package:heat_trip_flutter/v2/screens/settings_screen.dart';
import 'package:heat_trip_flutter/v2/screens/settings/permission_notice_screen.dart';

/// 설정 화면과 같은 이유로 화면을 길게 잡는다 — 절이 늘어나는 자리라 폰 한 화면에
/// 맞추면 아래 항목이 "없다" 로 보인다.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.resetForTest();
  });
  tearDown(AuthState.resetForTest);

  group('접근권한 안내 화면', () {
    testWidgets('필수와 선택이 나뉘어 보인다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      expect(find.text('필수 접근권한'), findsOneWidget);
      expect(find.text('선택 접근권한'), findsOneWidget,
          reason: '정보통신망법 제22조의2 제1항이 필수와 선택을 구분해 알리라고 한다');
      // 꼬리표도 항목마다 붙는다 — 절 제목만으로는 스크롤 중에 어느 절인지 잃는다.
      expect(find.text('필수'), findsNWidgets(PermissionNoticeScreen.essentials.length));
      expect(find.text('선택'), findsNWidgets(PermissionNoticeScreen.optionals.length));
    });

    testWidgets('선택 절에 "동의하지 않아도 앱을 쓸 수 있어요" 가 있다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      expect(find.text(PermissionNoticeScreen.optionalNotice), findsOneWidget,
          reason: '이 문장이 요건 자체다 — 없으면 화면이 있어도 고지가 아니다');
    });

    testWidgets('항목마다 왜 필요한지가 적혀 있다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      for (final p in kAppPermissions) {
        expect(find.text(p.title), findsOneWidget, reason: p.title);
        expect(find.text(p.why), findsOneWidget, reason: '${p.title} 의 이유');
      }
    });

    testWidgets('설정에서 열 때는 확인 버튼이 없다 — 뒤로 가면 된다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      expect(find.byKey(const Key('permission-notice-ack')), findsNothing);
    });

    testWidgets('첫 실행으로 열면 확인 버튼이 있다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen(firstRun: true));

      expect(find.byKey(const Key('permission-notice-ack')), findsOneWidget);
      expect(find.text('확인했어요'), findsOneWidget);
    });
  });

  group('목록이 선언과 어긋나지 않는다', () {
    test('Info.plist 의 NS...UsageDescription 이 전부 고지돼 있다', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final declared = RegExp(r'<key>(NS\w*UsageDescription)</key>')
          .allMatches(plist)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, isNotEmpty, reason: 'plist 를 못 읽었으면 이 검사는 아무것도 안 잰다');

      final noticed = {for (final p in kAppPermissions) ...p.ios};
      expect(declared.difference(noticed), isEmpty,
          reason: 'plist 에 있는데 고지에 없다 — 사용자는 뜬금없는 대화상자를 만난다');
      expect(noticed.difference(declared), isEmpty,
          reason: '고지에 있는데 plist 에 없다 — 안 쓰는 권한을 고지하고 있다');
    });

    test('AndroidManifest 의 uses-permission 이 전부 고지돼 있다', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final declared = RegExp(r'<uses-permission[^>]*android:name="([\w.]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, isNotEmpty,
          reason: '매니페스트를 못 읽었으면 이 검사는 아무것도 안 잰다');

      final noticed = {for (final p in kAppPermissions) ...p.android};
      expect(declared.difference(noticed), isEmpty,
          reason: '매니페스트에 있는데 고지에 없다 — 이 검사가 있는 이유가 이것이다');
      expect(noticed.difference(declared), isEmpty,
          reason: '고지에 있는데 매니페스트에 없다 — 안 쓰는 권한을 고지하고 있다');
    });

    test('위치는 선택이다 — 거부해도 앱이 돌아가는 것을 코드에서 확인했다', () {
      final location = kAppPermissions.firstWhere((p) => p.title == '위치');

      expect(location.essential, isFalse,
          reason: '라우터가 위치 권한을 보지 않고, 홈 카드와 추적 화면이 거부를 받아 낸다 — '
              '거부한 사람도 커뮤니티·채팅·일정을 쓴다');
      expect(location.ifDenied, isNotNull,
          reason: '대신 무엇을 못 쓰게 되는지는 말해야 한다');
      expect(location.ifDenied, contains('산책'));
    });

    test('선택 항목은 전부 거부했을 때를 말한다', () {
      for (final p in PermissionNoticeScreen.optionals) {
        expect(p.ifDenied, isNotNull, reason: '${p.title} 에 거부했을 때 설명이 없다');
        expect(p.ifDenied, contains('거부해도 앱을 쓸 수 있어요'), reason: p.title);
      }
    });
  });

  group('들어가는 길', () {
    testWidgets('설정 > 앱 에 접근권한 안내 줄이 있고, 누르면 열린다', (tester) async {
      AuthState.status.value = AuthStatus.unauthenticated;
      await _pump(tester, const SettingsScreen());

      expect(find.text(PermissionNoticeScreen.menuLabel), findsOneWidget);

      await tester.tap(find.text(PermissionNoticeScreen.menuLabel));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionNoticeScreen), findsOneWidget);
      expect(find.text('선택 접근권한'), findsOneWidget);
    });

    testWidgets('첫 실행 — 소개를 끝내면 안내를 지나서야 onDone 이 불린다', (tester) async {
      var calls = 0;
      await _pump(tester, IntroScreen(onDone: () => calls++));

      for (var i = 0; i < kIntroPages.length - 1; i++) {
        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionNoticeScreen), findsOneWidget);
      expect(calls, 0, reason: '안내를 보기 전에 로그인 화면으로 넘어가면 고지가 아니다');

      await tester.tap(find.byKey(const Key('permission-notice-ack')));
      await tester.pumpAndSettle();

      expect(calls, 1);
    });

    testWidgets('건너뛰기로 끝내도 안내를 지난다 — 그쪽이 오히려 다수다', (tester) async {
      var calls = 0;
      await _pump(tester, IntroScreen(onDone: () => calls++));

      await tester.tap(find.text('건너뛰기'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionNoticeScreen), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('설정에서 소개를 다시 볼 때는 안 뜬다 — 설정에 자기 줄이 있다', (tester) async {
      var calls = 0;
      await _pump(tester, IntroScreen(onDone: () => calls++, replay: true));

      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionNoticeScreen), findsNothing);
      expect(calls, 1);
    });
  });
}
