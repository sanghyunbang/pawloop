// 산책 끝내기 시트를 **저장 없이 닫았을 때** 산책이 계속 되는가 — 이슈 #706.
//
// ## 실기기에서 무슨 일이 있었나
//
// 2026-09-18, 8분을 걷고 저장했는데 기록이 **26초 · 59m** 였다. 사장님이 "끝내기를
// 눌렀다가 또 다시 하고 그랬다" 고 확인해 주셨다. `_finish()` 가 시계(`_timer`)와 위치
// 구독(`_posSub`)을 끄고 **되살리지 않아서**, 시트를 밖을 탭해 닫고 다시 걸으면 화면은
// "산책 기록 중" 을 띄운 채 시간도 거리도 안 올라갔다. 사용자에게는 멀쩡해 보인다 —
// 숫자가 얼어붙은 것은 8분을 다 걷고 저장 화면에 가서야 보인다.
//
// ## 왜 이 화면에 테스트가 없었나
//
// 위치가 `LocationService` 의 static 호출이라 위젯 테스트가 진짜 GPS 를 부르려 들었다.
// #706 을 고치면서 `locate`·`positions` 주입 자리를 냈다(`picker`·`photoStore` 와 같은 자리).
// 지도는 따로 막을 필요가 없다 — 테스트 빌드에는 `NAVER_MAP_CLIENT_ID` 가 없어
// `Env.hasNaverMap` 이 false 이고 `MapUnavailable` 이 대신 선다. `_captureMap()` 도
// `_ctrl == null` 이라 즉시 null 이다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/screens/walk_tracking_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_stats_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 9, 18, 10),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// 걸어가는 중인 화면 하나와, 그 화면을 흔들 손잡이들.
class _Walk {
  _Walk(this.tester, this.feed, this.listens);

  final WidgetTester tester;

  /// 걸어가는 좌표를 흘려 넣는 곳. **broadcast 여야 한다** — `_listenPositions()` 가
  /// 되살아날 때 끊었다 다시 듣는데, 단일 구독 스트림은 두 번째 `listen` 에서 던진다.
  final StreamController<Position> feed;

  /// `positions` 공장이 불린 횟수 = **위치 구독을 연 횟수**. 되살렸는지 아닌지가 여기 보인다.
  final List<String> listens;

  WalkStatsPanel get panel => tester.widget<WalkStatsPanel>(find.byType(WalkStatsPanel));

  /// 화면이 지금 그리고 있는 거리(km)와 시간 글자.
  double get km => panel.km;
  String get timeLabel => panel.timeLabel;

  /// 한 걸음 — 좌표 하나를 흘리고 [seconds] 초를 보낸다.
  ///
  /// 시계는 `Timer.periodic(1초)` 라 가짜 시간을 밀면 흐른다.
  Future<void> walk(Position p, {int seconds = 3}) async {
    feed.add(p);
    await tester.pump();
    await tester.pump(Duration(seconds: seconds));
  }
}

Future<_Walk> _pumpWalk(WidgetTester tester, {double height = 900}) async {
  final feed = StreamController<Position>.broadcast();
  addTearDown(feed.close);
  final listens = <String>[];
  final nav = GlobalKey<NavigatorState>();

  // 기본 800x600 은 가로로 누운 화면이라 끝내기 시트의 아래 버튼이 화면 밖으로 밀린다.
  // 실제로 이 화면을 쓰는 모양(세로 폰)으로 맞춘다.
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 아래에 화면이 한 장 있어야 한다 — '저장 안 함' 이 트래킹 화면을 pop 하기 때문이다.
  await tester.pumpWidget(MaterialApp(
    navigatorKey: nav,
    home: const Scaffold(body: Center(child: Text('홈'))),
  ));
  unawaited(nav.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => WalkTrackingScreen(
      locate: () async => LocationFix.found(_pos(37.5000, 127.0000)),
      positions: ({required String notificationTitle}) {
        listens.add(notificationTitle);
        return feed.stream;
      },
    ),
  )));
  // 라우트 전환 + `_start()` 안의 await 둘(위치 판정 · 알림 권한).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(WalkStatsPanel), findsOneWidget, reason: '트래킹 화면이 떠야 한다');
  return _Walk(tester, feed, listens);
}

/// 끝내기 시트를 띄운다. 패널은 기본이 펼침이라 '종료' 가 첫 프레임부터 보인다.
Future<void> _tapFinish(WidgetTester tester) async {
  await tester.tap(find.text('종료'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('산책 완료!'), findsOneWidget, reason: '끝내기 시트가 떠야 한다');
}

void main() {
  late Future<bool> Function() realNotify;

  setUp(() {
    // `_snapshot()` 이 5초마다 `WalkInProgressStore` 에 쓴다.
    SharedPreferences.setMockInitialValues({});
    // 안드로이드 13+ 알림 권한 — 진짜를 부르면 플러그인이 없어서 던진다.
    realNotify = LocationService.requestNotificationPermission;
    LocationService.requestNotificationPermission = () async => true;
  });

  tearDown(() => LocationService.requestNotificationPermission = realNotify);

  testWidgets('종료 시트를 밖을 탭해 닫으면 거리와 시간이 다시 는다 (#706)', (tester) async {
    final w = await _pumpWalk(tester);

    // 조금 걷는다.
    await w.walk(_pos(37.5010, 127.0000));
    expect(w.km, greaterThan(0), reason: '시트를 열기 전에 이미 걷고 있어야 한다');

    await _tapFinish(tester);

    // **밖을 탭해 닫는다** — 저장도 버리기도 아니다. 사용자는 아직 걷는 중이다.
    await tester.tapAt(const Offset(200, 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('산책 완료!'), findsNothing, reason: '시트가 닫혀야 한다');
    expect(find.byType(WalkStatsPanel), findsOneWidget, reason: '화면은 그대로 있어야 한다');

    final kmAtClose = w.km;
    final timeAtClose = w.timeLabel;

    // 시트를 닫은 뒤 다시 걷는다. 고치기 전에는 여기서 둘 다 얼어붙어 있었다.
    await w.walk(_pos(37.5020, 127.0000), seconds: 5);

    expect(w.km, greaterThan(kmAtClose),
        reason: '시트를 닫고 다시 걸었는데 거리가 안 늘었다 — 위치 구독이 안 되살아났다(#706)');
    expect(w.timeLabel, isNot(timeAtClose),
        reason: '시트를 닫고 5초가 지났는데 시간이 안 늘었다 — 시계가 안 되살아났다(#706)');
    // 숫자가 화면까지 닿는지도 한 번 본다 — 패널이 펼침이면 값이 그대로 글자가 된다.
    expect(find.text(w.timeLabel), findsOneWidget);
    expect(find.text(w.km.toStringAsFixed(2)), findsOneWidget);
  });

  testWidgets('저장 안 함으로 떠나면 되살리지 않는다', (tester) async {
    // 이 검사가 없으면 "언제나 되살린다" 로 바꿔도 위 검사가 초록이다. 떠나는 길에
    // 시계와 구독을 다시 여는 것은 그 자체로 버그다 — 화면은 사라지는데 포그라운드
    // 위치 서비스가 한 번 더 열린다.
    final w = await _pumpWalk(tester);
    await w.walk(_pos(37.5010, 127.0000));
    expect(w.listens, hasLength(1), reason: '시작할 때 한 번만 연다');

    await _tapFinish(tester);

    // 시트가 길면 아래 버튼이 스크롤 밖에 있다 — 사용자가 하는 대로 먼저 끌어 올린다.
    await tester.ensureVisible(find.text('저장 안 함'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장 안 함'));
    // 한 프레임이면 `await showModalBottomSheet` 뒤가 돈다. 화면은 아직 나가는
    // 중이라 `mounted` 가 true 다 — 되살리는 코드가 있으면 여기서 불린다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(w.listens, hasLength(1),
        reason: '버리고 떠나는 길인데 위치 구독을 한 번 더 열었다');

    await tester.pumpAndSettle();
    expect(find.byType(WalkStatsPanel), findsNothing, reason: '화면을 떠나야 한다');
    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('기록 저장하기로 떠나도 되살리지 않는다 — 가장 흔한 길이다', (tester) async {
    // **이 검사는 검증 담당이 찾은 구멍을 메운다.** 위의 '저장 안 함' 검사는 `onDiscard`
    // 만 덮는다. `onSave` 의 `_leavingAfterFinish = true` 한 줄을 지워 보면 나머지 검사
    // 셋이 전부 초록이었다 — 실제로 저장하고 떠나는, **사람들이 거의 항상 지나는 길**에
    // 포그라운드 위치 구독을 한 번 더 여는 회귀가 생겨도 아무도 안 잡는다는 뜻이다.
    final w = await _pumpWalk(tester);
    await w.walk(_pos(37.5010, 127.0000));
    expect(w.listens, hasLength(1), reason: '시작할 때 한 번만 연다');

    await _tapFinish(tester);

    await tester.ensureVisible(find.text('기록 저장하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 저장하기'));
    // 한 프레임이면 `await showModalBottomSheet` 뒤가 돈다. 저장 화면으로 가는 중이라
    // 이 화면은 아직 `mounted` 다 — 되살리는 코드가 있으면 여기서 불린다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(w.listens, hasLength(1),
        reason: '저장하러 떠나는 길인데 위치 구독을 한 번 더 열었다');

    // 저장 화면(`CreateScreen`)이 이 테스트의 관심사가 아니다. 그 화면이 뜨면서 던지는
    // 것(네트워크·저장소)은 여기서 다루지 않는다 — 우리가 재는 것은 **떠나는 길에
    // 구독을 다시 열지 않는가** 하나다.
    tester.takeException();
  });

  testWidgets('짧은 화면에서도 "기록 저장하기" 가 스크롤 없이 보인다 (#704)', (tester) async {
    // **2026-09-18 에 사장님이 실제로 막힌 자리다.** 2분을 걷고 돌아왔는데
    // "저장 버튼도 없고 아무것도 없다" 고 하셨다. 시트는 화면의 9/16(약 56%)에서 잘렸고,
    // 잘린 자리에 들어간 것이 하필 `기록 저장하기` 였다. 걷고 나서 그 기록을 남기는
    // **단 하나의 버튼**이다.
    //
    // **380 은 재서 고른 값이다.** 시트는 사진·기록·경로 그림이 붙을수록 길어지는데, 짧은
    // 화면은 그 긴 내용을 한 판에 재현하는 가장 싼 방법이다. 처음에 600 으로 잡았더니
    // 내용이 짧아 스크롤이 아예 안 생겨서, **버튼을 다시 스크롤 안에 넣는 되돌림을 못
    // 잡았다** — `isScrollControlled` 까지 같이 빼야 빨개졌다. 460 도 마찬가지였다.
    // 380 에서는 그 하나만 되돌려도 잡힌다(저장 버튼 아래끝이 408pt 가 된다).
    final w = await _pumpWalk(tester, height: 380);
    await w.walk(_pos(37.5010, 127.0000));

    await tester.tap(find.text('종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final save = find.byKey(const Key('finish-save'));
    expect(save, findsOneWidget, reason: '끝내기 시트에 저장 버튼이 있어야 한다');

    final box = tester.getRect(save);
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(box.bottom, lessThanOrEqualTo(screen), reason: '''
저장 버튼 아래끝이 ${box.bottom.toStringAsFixed(0)}pt 인데 화면은 ${screen.toStringAsFixed(0)}pt 다.
스크롤해야 닿는 자리에 있으면, 걷고 돌아온 사람은 앱이 고장난 줄 안다(#704).''');
    expect(box.top, greaterThanOrEqualTo(0));

    // 눌러서 실제로 닿는지까지 본다 — 보이기만 하고 다른 것이 위를 덮고 있으면 소용없다.
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
  });

  testWidgets('종료를 안 누르고 걸으면 거리·시간이 는다', (tester) async {
    // 바닥 — 계측 자체가 도는지. 이것이 빨개지면 위 둘은 아무것도 말해 주지 않는다.
    final w = await _pumpWalk(tester);
    final km0 = w.km;
    final t0 = w.timeLabel;

    await w.walk(_pos(37.5010, 127.0000), seconds: 4);

    expect(w.km, greaterThan(km0));
    expect(w.timeLabel, isNot(t0));
    expect(w.listens, hasLength(1), reason: '구독은 시작할 때 한 번이다');
  });

  testWidgets('따라 걸을 코스가 멀면 "코스 시작점까지 N km" 를 띄우고, 코스 위에 서면 숨긴다 (2026-09-21)', (tester) async {
    // 멀어도 우리 추적 화면에서 시작한다(#724 를 뒤집음) — 그러면 어디로 가야 하는지는 이 칩이 말한다.
    final feed = StreamController<Position>.broadcast();
    addTearDown(feed.close);
    final nav = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Center(child: Text('홈'))),
    ));
    // 코스 첫 점은 북쪽으로 약 2.8km — 집에서 카드를 눌러 시작한 사람의 자리다.
    const line = [
      [127.0000, 37.5252],
      [127.0030, 37.5270],
      [127.0000, 37.5252],
    ];
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => WalkTrackingScreen(
        courseLine: line,
        locate: () async => LocationFix.found(_pos(37.5000, 127.0000)),
        positions: ({required String notificationTitle}) => feed.stream,
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('course-start-hint')), findsOneWidget,
        reason: '멀어도 여기서 시작하니 어디로 가야 하는지 첫 화면이 말해야 한다');
    expect(find.textContaining('코스 시작점까지 2.8km'), findsOneWidget);

    // 코스 첫 점 50m 앞까지 걸어가면 칩이 사라진다 — 코스 위다.
    feed.add(_pos(37.5248, 127.0000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('course-start-hint')), findsNothing);
  });
}
