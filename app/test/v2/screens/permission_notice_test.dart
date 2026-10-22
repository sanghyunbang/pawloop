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
//  6. 인터넷 계열이 고지 목록에 **없다**(2026-09-18). 시행령 제9조의2 제1항 각 호에
//     없는 것을 필수 항목으로 올려 두니 화면이 "이 앱에 꼭 필요한 건 인터넷뿐" 이라고
//     말하는 꼴이었다.
//  7. 위치가 **필수**다 — 시행령 제9조의2 제3항의 세 기준으로 갈랐다. "거부해도 앱이
//     열리니 선택" 은 법의 기준이 아니었다. 그러면서도 앱이 잠기지 않는다고 말한다.
//  8. 위치 항목이 **약관 동의와 별개**라고 말한다 — 같은 "필수" 가 두 화면에서 다른
//     뜻이라 모순으로 읽혔다. 짝이 되는 줄은 `consent_test.dart` 가 잰다.
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

      expect(find.text(PermissionNoticeScreen.essentialLabel), findsOneWidget);
      expect(find.text(PermissionNoticeScreen.optionalLabel), findsOneWidget,
          reason: '정보통신망법 제22조의2 제1항이 필수와 선택을 구분해 알리라고 한다');
      // 꼬리표도 항목마다 붙는다 — 절 제목만으로는 스크롤 중에 어느 절인지 잃는다.
      expect(find.text('필수적'), findsNWidgets(PermissionNoticeScreen.essentials.length));
      expect(find.text('선택적'), findsNWidgets(PermissionNoticeScreen.optionals.length));
    });

    testWidgets('필수는 위치 하나다 — 절이 비어 있지 않다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      expect(PermissionNoticeScreen.essentials.map((p) => p.title), ['위치'], reason: '''
시행령 제9조의2 제3항의 세 기준(공개된 서비스의 범위와 실제 제공 여부·이용자의 합리적
예상 가능성·기술적 관련성)이 전부 위치를 가리킨다. 나머지 넷은 그 서비스 없이도 성립한다.''');
      expect(find.text(PermissionNoticeScreen.essentialLabel), findsOneWidget);
      expect(find.text(PermissionNoticeScreen.essentialNotice), findsOneWidget,
          reason: '절 제목만 있고 머리말이 없으면 필수가 무슨 뜻인지 말하지 않은 것이다');
      expect(find.text(PermissionNoticeScreen.noEssentialNotice), findsNothing,
          reason: '필수가 있는데 "없어요" 가 뜨면 화면이 거짓말을 한다');
    });

    test('필수 머리말이 "앱을 쓸 수 없다" 고 말하지 않는다 — 그것은 거짓이다', () {
      expect(PermissionNoticeScreen.essentialNotice, isNot(contains('앱을 쓸 수 없')),
          reason: '''
위치를 거부해도 앱은 열린다 — 라우터가 위치를 보지 않고 커뮤니티·채팅·일정은 위치를
부르지 않는다. 법이 가르는 기준은 "앱이 열리는가" 가 아니라 "그 서비스를 제공할 수
있는가" 다(시행령 제9조의2 제3항). 머리말이 앱을 잠근다고 말하면 화면이 거짓말을 한다.''');
    });

    testWidgets('두 화면의 경계를 적는다 — 약관 동의와 별개다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      expect(find.text(PermissionNoticeScreen.boundaryNotice), findsOneWidget,
          reason: '같은 "필수" 가 여기서는 기기 권한, 동의 화면에서는 약관이다');
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
    // 고지하는 것과 **일부러 안 하는 것**을 합쳐야 선언과 같아진다. 안 하는 쪽을
    // [kNotNoticedPermissions] 로 적어 두는 이유가 이 검사다 — 그냥 지우면 "선언에는
    // 있는데 고지에 없다" 를 더는 못 잡고, 새 권한이 조용히 빠져도 초록이 된다.
    Set<String> accountedFor(Iterable<String> noticed) =>
        {...noticed, for (final p in kNotNoticedPermissions) p.name};

    test('Info.plist 의 NS...UsageDescription 이 전부 고지돼 있다', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final declared = RegExp(r'<key>(NS\w*UsageDescription)</key>')
          .allMatches(plist)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, isNotEmpty, reason: 'plist 를 못 읽었으면 이 검사는 아무것도 안 잰다');

      final noticed = {for (final p in kAppPermissions) ...p.ios};
      expect(declared.difference(accountedFor(noticed)), isEmpty,
          reason: 'plist 에 있는데 고지에도 "일부러 뺐다" 에도 없다 — '
              '사용자는 뜬금없는 대화상자를 만난다');
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
      expect(declared.difference(accountedFor(noticed)), isEmpty,
          reason: '매니페스트에 있는데 고지에도 "일부러 뺐다" 에도 없다 — '
              '이 검사가 있는 이유가 이것이다');
      expect(noticed.difference(declared), isEmpty,
          reason: '고지에 있는데 매니페스트에 없다 — 안 쓰는 권한을 고지하고 있다');
    });

    test('일부러 뺀 것은 이유가 있고, 실제로 선언돼 있고, 고지와 겹치지 않는다', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final declared = {
        ...RegExp(r'<uses-permission[^>]*android:name="([\w.]+)"')
            .allMatches(manifest)
            .map((m) => m.group(1)!),
        ...RegExp(r'<key>(NS\w*UsageDescription)</key>')
            .allMatches(plist)
            .map((m) => m.group(1)!),
      };
      final noticed = {
        for (final p in kAppPermissions) ...p.android,
        for (final p in kAppPermissions) ...p.ios,
      };

      for (final skipped in kNotNoticedPermissions) {
        expect(declared, contains(skipped.name),
            reason: '${skipped.name} 은 이제 선언에 없다 — 이 줄을 지워라. '
                '안 지우면 "선언 = 고지 + 뺀 것" 이 느슨해진다');
        expect(noticed, isNot(contains(skipped.name)),
            reason: '${skipped.name} 이 양쪽에 다 있다 — 어느 쪽이 참인지 알 수 없다');
        expect(skipped.why.length, greaterThan(20),
            reason: '${skipped.name} 을 왜 뺐는지가 없다 — 이유 없는 줄은 '
                '"귀찮은 권한을 숨기는 곳" 이 된다');
      }
    });

    test('인터넷 계열은 고지 목록에 없다 — 시행령 제9조의2 제1항 각 호 밖이다', () {
      const outOfScope = [
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.WAKE_LOCK',
        'android.permission.FOREGROUND_SERVICE',
      ];
      final noticed = {for (final p in kAppPermissions) ...p.android};

      for (final name in outOfScope) {
        expect(noticed, isNot(contains(name)), reason: '''
$name 은 단말에 저장된 정보도, 자동 저장된 정보도, 고유정보도, 입출력 기능도 아니다.
설치할 때 자동으로 붙어서 최초 접근 때 이용자가 고를 것도 없다 — 고를 수 없는 것을
고지 항목으로 세우면 화면이 "이 앱에 꼭 필요한 건 인터넷뿐" 이라고 말하게 된다.''');
        expect(kNotNoticedPermissions.map((p) => p.name), contains(name),
            reason: '$name 은 뺀 이유와 함께 남아 있어야 한다');
      }
      for (final p in kAppPermissions) {
        expect(p.title, isNot(contains('인터넷')), reason: p.title);
        expect(p.title, isNot(contains('네트워크')), reason: p.title);
      }
    });

    test('위치는 필수다 — 시행령 제9조의2 제3항의 세 기준이 전부 위치를 가리킨다', () {
      final location = kAppPermissions.firstWhere((p) => p.title == '위치');

      expect(location.essential, isTrue, reason: '''
한 번 틀렸다가 고친 자리다. "거부해도 앱이 열리니 선택" 은 법의 기준이 아니다 — 시행령
제9조의2 제3항은 ①공개된 서비스의 범위와 실제 제공 여부 ②이용자의 합리적 예상 가능성
③기술적 관련성을 보라고 한다. 우리가 내건 것이 산책 기록이고, 산책 앱이 위치를 쓰는 것은
당연히 예상되며, GPS 없이 경로를 그릴 방법이 없다. 펫피·피리부는 강아지·포랜드도 전부
"(필수) GPS 위치정보" 로 적는다(2026-09-18 플레이스토어 설명 확인).''');
      expect(location.ifDenied, isNotNull,
          reason: '필수라도 무엇을 못 쓰게 되는지는 말해야 한다');
      expect(location.ifDenied, contains('산책'));
      expect(location.ifDenied, contains('앱이 잠기지는'), reason: '''
필수로 적는다고 앱이 잠기는 것이 아니다. 법 제22조의2 제2항이 막는 것은 *비필수* 권한
미동의를 이유로 한 서비스 거부뿐이고, 우리 앱은 위치를 거부해도 열린다. 화면이 그 사실을
말하지 않으면 사용자가 가진 자유를 실제보다 작게 알리는 것이 된다.''');
    });

    testWidgets('위치 항목이 약관 동의와 별개라고 말한다', (tester) async {
      await _pump(tester, const PermissionNoticeScreen());

      final location = kAppPermissions.firstWhere((p) => p.title == '위치');
      expect(location.ifDenied, contains(kLocationIsNotTheTerms), reason: '''
두 화면 다 위치를 필수라 부르지만 뜻이 다르다 — 여기서는 기기의 GPS 를 켜는 허용이고,
동의 화면에서는 위치기반서비스 이용약관이라는 계약 문서다. 설명이 없으면 같은 "필수" 가
두 화면에서 다른 뜻이라 읽는 사람이 헷갈린다 — 실기기에서 그렇게 읽었다(#682).''');
      expect(find.textContaining(kLocationIsNotTheTerms), findsOneWidget,
          reason: '상수에만 있고 화면에 안 그려지면 아무 말도 안 한 것이다');
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
      expect(find.text(PermissionNoticeScreen.optionalLabel), findsOneWidget);
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
