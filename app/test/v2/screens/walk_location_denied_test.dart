// 위치를 못 잡았을 때 이 앱이 무엇을 말하는가. 이슈 #160.
//
// 예전에는 아무 말도 하지 않았다. 위치가 없으면 트래킹 화면이 서울숲 근처 가짜
// 루프를 그리고 거리를 올렸고, 사용자는 자기가 걷지 않은 1.37km 를 보고 있었다.
// 완료 조건 3 이 "권한 거부와 사용자 중단이 다른 문구를 낸다" 인 이유는, 두 경우에
// 사용자가 할 일이 정반대이기 때문이다 — 하나는 OS 설정으로 가야 하고 하나는 앱
// 안에서 토글만 끄면 된다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/screens/walk_tracking_screen.dart';

Future<void> _pump(WidgetTester t, LocationDenial d,
    {Future<void> Function()? onRetry}) async {
  await t.pumpWidget(MaterialApp(
    home: WalkLocationDeniedScreen(
      denial: d,
      onRetry: onRetry ?? () async {},
    ),
  ));
}

/// 화면에 실제로 그려진 문자열 전부. 문구가 갈리는지 보려면 이걸 비교한다.
Set<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data)
    .whereType<String>()
    .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // '위치 수집 다시 켜기' 가 `setPaused` 로 **디스크에 남긴다**. 목이 없으면
  // MissingPluginException 이다 — 이 줄이 그 버튼이 실제로 저장한다는 증거이기도 하다.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  tearDown(() => LocationService.paused.value = false);

  group('이유마다 다른 것을 말한다', () {
    testWidgets('다섯 이유가 전부 다른 제목을 낸다', (t) async {
      final titles = <String>[];
      for (final d in LocationDenial.values) {
        await _pump(t, d);
        // 제목은 화면에서 가장 큰 글자다.
        final title = t
            .widgetList<Text>(find.byType(Text))
            .firstWhere((w) => w.style?.fontSize == 18);
        titles.add(title.data!);
      }
      expect(titles.length, LocationDenial.values.length);
      expect(titles.toSet().length, titles.length,
          reason: '이유가 다섯인데 문구가 겹치면 사용자는 무엇을 해야 할지 모른다: $titles');
    });

    testWidgets('권한 거부와 사용자 중단은 겹치는 문장이 하나도 없다', (t) async {
      await _pump(t, LocationDenial.denied);
      final denied = _texts(t);
      await _pump(t, LocationDenial.pausedByUser);
      final paused = _texts(t);

      // '직접 입력해서 기록하기' 는 양쪽 공통이라 빼고 비교한다.
      const shared = '직접 입력해서 기록하기';
      expect(denied.difference({shared}).intersection(paused.difference({shared})),
          isEmpty,
          reason: '두 경우에 사용자가 할 일이 정반대다 — OS 설정 vs 앱 안 토글');
    });

    testWidgets('사용자가 끈 경우는 앱 안에서 끝난다고 말한다', (t) async {
      await _pump(t, LocationDenial.pausedByUser);
      expect(find.text('위치 수집을 중단해 두셨어요'), findsOneWidget);
      expect(find.text('위치 수집 다시 켜기'), findsOneWidget);
      // OS 설정으로 보내지 않는다 — 앱 안에서 켤 수 있는데 설정으로 보내면 헤맨다.
      expect(find.text('앱 설정 열기'), findsNothing);
      expect(find.text('위치 설정 열기'), findsNothing);
    });

    testWidgets('영구 거부는 앱이 다시 못 묻는다는 사실을 말한다', (t) async {
      await _pump(t, LocationDenial.deniedForever);
      expect(find.text('앱 설정 열기'), findsOneWidget);
      // '다시 시도' 를 주면 눌러도 아무 일이 없다 — 앱은 다시 물을 수 없다.
      expect(find.text('다시 시도'), findsNothing);
    });

    testWidgets('신호가 약한 것뿐이면 고치라고 하지 않는다', (t) async {
      await _pump(t, LocationDenial.unavailable);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('앱 설정 열기'), findsNothing);
    });
  });

  group('가짜를 그리는 대신 손입력으로 보낸다', () {
    testWidgets('어떤 이유든 직접 입력 진입로가 있다', (t) async {
      for (final d in LocationDenial.values) {
        await _pump(t, d);
        expect(find.text('직접 입력해서 기록하기'), findsOneWidget,
            reason: '$d 에서 기록할 길이 막히면 사용자는 걷고도 아무것도 못 남긴다');
      }
    });
  });

  group('일시중지 해제', () {
    testWidgets('버튼을 누르면 토글이 꺼지고 다시 판정한다', (t) async {
      LocationService.paused.value = true;
      var retried = 0;
      await _pump(t, LocationDenial.pausedByUser,
          onRetry: () async => retried++);

      await t.tap(find.text('위치 수집 다시 켜기'));
      await t.pump();

      expect(LocationService.paused.value, isFalse);
      expect(retried, 1, reason: '토글만 끄고 재판정을 안 하면 화면이 그대로 멈춘다');
    });
  });

  group('LocationService.locate', () {
    test('일시중지 중이면 Geolocator 를 건드리지 않고 이유를 준다', () async {
      // 테스트 환경에는 플랫폼 채널이 없다. 여기서 Geolocator 로 내려가면
      // MissingPluginException 이 난다 — 안 난다는 것이 곧 단락 증거다.
      LocationService.paused.value = true;
      final fix = await LocationService.locate();
      expect(fix.ok, isFalse);
      expect(fix.denial, LocationDenial.pausedByUser);
      expect(fix.position, isNull);
      LocationService.paused.value = false;
    });

    test('current() 는 locate() 의 좌표만 꺼낸 껍데기다', () async {
      LocationService.paused.value = true;
      expect(await LocationService.current(), isNull);
      LocationService.paused.value = false;
    });
  });
}
