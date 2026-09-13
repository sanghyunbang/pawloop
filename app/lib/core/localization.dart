// 머티리얼 위젯의 한국어 — 이슈 #443.
//
// ## 왜 한 곳에 두나
//
// `MaterialApp.router` 에 세 값을 직접 적어도 되지만, 그러면 검사가 앱 루트를 통째로 띄워야
// 그것을 잴 수 있다(라우터·플러그인이 따라온다). 값을 여기 두면 검사가 **같은 값으로 작은
// MaterialApp 을 띄워** 날짜 고르기가 실제로 한국어인지 재고, 루트가 이 값을 쓰는지는
// 따로 잰다.
//
// ## 왜 ko 로 고정하나
//
// 앱의 글자는 전부 한국어다. 기기 언어를 따르게 두면 영어 기기에서 앱 글은 한국어인데
// 달력·툴팁만 영어가 된다 — 지금까지가 그 상태였다(위임자가 없어 머티리얼 기본값인 영어).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 앱이 그리는 로케일. 기기 언어와 무관하다.
const Locale appLocale = Locale('ko');

/// 지원 로케일 — 하나뿐이다. 둘 이상이면 [appLocale] 고정과 뜻이 어긋난다.
const List<Locale> appSupportedLocales = [appLocale];

/// 머티리얼 · 위젯 · 쿠퍼티노 셋 다 단다. 하나라도 빠지면 그 계층의 문구가 영어로 남거나,
/// 쿠퍼티노 위젯(iOS 식 스크롤 날짜 고르기 등)이 로케일을 못 찾아 던진다.
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
