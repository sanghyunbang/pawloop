// 머티리얼 위젯이 한국어로 그려지는가 — 이슈 #443.
//
// 날짜 고르기가 "Select date · Cancel · OK" 로 뜨던 것이 이 이슈다. 앱 루트에 위임자와 로케일이
// 없어서였다. 여기서는 **같은 값으로 작은 MaterialApp 을 띄워** 실제로 한국어인지 재고, 루트가
// 그 값을 쓰는지는 소스로 잰다 — 루트를 통째로 띄우면 라우터·플러그인이 따라온다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/core/localization.dart';

Widget _host(Widget home) => MaterialApp(
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: home,
    );

void main() {
  test('로케일은 ko 하나로 고정이고, 위임자는 머티리얼·위젯·쿠퍼티노 셋이다', () {
    expect(appLocale, const Locale('ko'));
    expect(appSupportedLocales, [const Locale('ko')],
        reason: '둘 이상이면 기기 언어를 따르게 되고, 앱 글은 한국어인데 달력만 영어인 상태로 돌아간다');
    expect(appLocalizationsDelegates, containsAll([
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ]));
  });

  testWidgets('날짜 고르기가 한국어로 뜬다 — 취소 · 확인, "Select date" 는 없다', (tester) async {
    await tester.pumpWidget(_host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showDatePicker(
          context: context,
          initialDate: DateTime(2026, 9, 13),
          firstDate: DateTime(2026, 9, 13),
          lastDate: DateTime(2027, 9, 13),
        ),
        child: const Text('열기'),
      ),
    )));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('취소'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('OK'), findsNothing);
    expect(find.text('Select date'), findsNothing,
        reason: '위임자가 없으면 머티리얼 기본값(영어)으로 그린다 — 그것이 #443 이다');
  });

  testWidgets('시각 고르기도 한국어다', (tester) async {
    await tester.pumpWidget(_host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showTimePicker(
            context: context, initialTime: const TimeOfDay(hour: 10, minute: 0)),
        child: const Text('열기'),
      ),
    )));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('취소'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
    expect(find.text('Select time'), findsNothing);
  });

  test('앱 루트가 그 값 셋을 쓴다 — 루트에 안 달면 위 검사는 초록인데 앱은 영어다', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('locale: appLocale'));
    expect(main, contains('supportedLocales: appSupportedLocales'));
    expect(main, contains('localizationsDelegates: appLocalizationsDelegates'));
  });
}
