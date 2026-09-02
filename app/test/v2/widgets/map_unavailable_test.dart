// 지도 키가 없을 때 무엇이 보이는가 — 이슈 #182.
//
// `NAVER_MAP_CLIENT_ID` 없이 빌드하면 `main.dart` 가 SDK 초기화를 건너뛴다. 그런데
// 화면들은 그것과 무관하게 `NaverMap(` 을 그려서 assertion 이 사용자에게 그대로 보였다.
//
// `env.dart` 는 이 경우를 이미 알고 "지도 탭이 안내문만 표시한다" 고 적어 두었다.
// **그 안내문이 없었다.** 의도만 있고 만들어지지 않은 자리였다.
//
// ## 왜 소스를 세는가
//
// `Env.hasNaverMap` 은 `String.fromEnvironment` 라 **컴파일 타임 상수**다. 테스트에서
// 바꿀 수 없다 — 값을 바꾸려면 `--dart-define` 을 주고 다시 컴파일해야 한다.
// 그래서 위젯을 펌프해 두 갈래를 다 보는 방식이 안 된다.
//
// 대신 **가드가 있는지**를 소스에서 센다. 이건 "NaverMap 을 그리기 전에 반드시 키를
// 본다" 는 규칙이고, 그 규칙이 지켜지는지는 소스로 확인할 수 있다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/v2/widgets/map_unavailable.dart';

void main() {
  group('지도를 그리기 전에 키를 본다', () {
    test('NaverMap 을 쓰는 모든 화면이 Env.hasNaverMap 을 먼저 본다', () {
      // `NaverMap(` 을 그대로 세면 세 가지가 함께 잡힌다 — `FlutterNaverMap().init(`
      // (초기화, 위젯이 아니다), 이 규칙을 설명하는 주석, 그리고 이 테스트 자신.
      // 위젯 생성만 골라야 규칙이 말이 된다.
      bool buildsTheWidget(File f) => f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .any((l) {
            final at = l.indexOf('NaverMap(');
            if (at < 0) return false;
            // 앞에 글자가 붙어 있으면 다른 이름이다 (FlutterNaverMap 등).
            if (at > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(l[at - 1])) return false;
            return true;
          });

      final users = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(buildsTheWidget)
          .toList();

      expect(users, isNotEmpty, reason: '찾는 대상이 0개면 이 테스트는 아무것도 안 잰다');

      final unguarded = users
          .where((f) => !f.readAsStringSync().contains('Env.hasNaverMap'))
          .map((f) => f.path)
          .toList();

      expect(unguarded, isEmpty,
          reason: '가드가 없으면 키 빠진 빌드에서 빨간 assertion 이 사용자에게 보인다');
    });

    test('hasNaverMap 은 키가 비었는지만 본다', () {
      expect(Env.hasNaverMap, Env.naverMapClientId.isNotEmpty);
    });
  });

  group('안내문', () {
    testWidgets('무엇을 잃었는지와 무엇이 원인인지 둘 다 말한다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: MapUnavailable(what: '주변 장소를 보여드리는 화면이에요.'),
      ));

      // 실패를 숨기지 않는다.
      expect(find.text('지도를 불러올 수 없어요'), findsOneWidget);
      // 사용자가 무엇을 잃었는지.
      expect(find.text('주변 장소를 보여드리는 화면이에요.'), findsOneWidget);
      // 개발자에게 남기는 단서. 이 줄이 없으면 원인을 못 찾는다.
      expect(find.text('빌드에 지도 키가 들어가지 않았어요'), findsOneWidget);
    });
  });
}
