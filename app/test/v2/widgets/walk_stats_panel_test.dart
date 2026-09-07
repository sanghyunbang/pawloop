// 트래킹 스탯 패널 — 종료가 첫 프레임부터 보이는가 (#327).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/widgets/walk_stats_panel.dart';

Widget _wrap({
  required bool expanded,
  bool paused = false,
  VoidCallback? onToggle,
  VoidCallback? onPause,
  VoidCallback? onFinish,
  // 스탯 세 값은 길이가 고정이 아니다 — 두 시간을 넘기면 `120:45`, 10km 를 넘기면
  // `12.24`, 아직 못 잰 페이스는 `-'--"` 다. 좁은 화면 테스트가 긴 쪽을 넣어 본다.
  double km = 0.32,
  String timeLabel = '00:42',
  String paceLabel = "2'10\"",
  double textScale = 1.0,
}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          // 화면 크기는 view 에서 온 것을 그대로 두고 글자 배율만 바꾼다 — MediaQueryData 를
          // 통째로 새로 만들면 size 가 0 이 되어 다른 것을 재게 된다.
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: WalkStatsPanel(
                km: km,
                timeLabel: timeLabel,
                paceLabel: paceLabel,
                paused: paused,
                expanded: expanded,
                onToggle: onToggle ?? () {},
                onPauseToggle: onPause ?? () {},
                onFinish: onFinish ?? () {},
              ),
            ),
          ),
        ),
      ),
    );

/// 논리 폭 [widthDp] 의 화면으로 바꾼다 — 물리 픽셀이 아니라 **dp** 로 적는다.
/// 기기 표는 dp 로 말한다(갤럭시 S8·A 다수가 360dp, 픽셀 계열이 393dp).
///
/// 이걸 안 걸면 창이 **800x600** 이다. 어떤 폰보다 넓어서, 폭 때문에 나는 넘침은
/// 여기 있는 어떤 테스트에도 안 걸린다 — 이 패널의 가로 넘침이 그렇게 오래 남아 있었다.
void useWidth(WidgetTester tester, double widthDp, {double heightDp = 780}) {
  const ratio = 3.0;
  tester.view.physicalSize = Size(widthDp * ratio, heightDp * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
}

/// 화면에 **그려진** 높이. 위·아래 모서리를 전역 좌표로 바꿔 재므로 조상이 걸어 둔
/// 확대·축소(FittedBox 등)까지 함께 잡힌다 — 크기가 스타일에 안 남는 축소를 잡으려면 이쪽이다.
String Function(String) drawnHeightOf(WidgetTester tester) => (String value) {
      final f = find.text(value).first;
      return (tester.getBottomLeft(f).dy - tester.getTopLeft(f).dy).toStringAsFixed(2);
    };

double valueSizeOf(WidgetTester tester, String value) =>
    tester.widget<Text>(find.text(value).first).style!.fontSize!;

void main() {
  test('트래킹 화면의 기본은 펼침이다 — 종료를 한 번 더 눌러 꺼내지 않는다', () {
    expect(WalkStatsPanel.expandedByDefault, isTrue);
  });

  testWidgets('펼침: 거리·시간·페이스와 일시정지·종료가 보인다', (tester) async {
    await tester.pumpWidget(_wrap(expanded: true));

    expect(find.text('종료'), findsOneWidget);
    expect(find.text('일시정지'), findsOneWidget);
    expect(find.text('0.32'), findsOneWidget);
    expect(find.text('00:42'), findsOneWidget);
    expect(find.text("2'10\""), findsOneWidget);
    expect(find.text('산책 기록 중'), findsOneWidget);
  });

  testWidgets('접힘: 알약 하나, 종료는 없다 — 탭하면 onToggle', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(_wrap(expanded: false, onToggle: () => toggled++));

    expect(find.text('0.32km · 00:42'), findsOneWidget);
    expect(find.text('종료'), findsNothing);

    await tester.tap(find.text('0.32km · 00:42'));
    expect(toggled, 1);
  });

  testWidgets('종료와 일시정지가 콜백을 부른다', (tester) async {
    var finished = 0;
    var paused = 0;
    await tester.pumpWidget(_wrap(expanded: true, onFinish: () => finished++, onPause: () => paused++));

    await tester.tap(find.text('종료'));
    await tester.tap(find.text('일시정지'));
    expect(finished, 1);
    expect(paused, 1);
  });

  testWidgets('일시정지 중엔 "재개" 와 "일시정지됨"', (tester) async {
    await tester.pumpWidget(_wrap(expanded: true, paused: true));

    expect(find.text('재개'), findsOneWidget);
    expect(find.text('일시정지됨'), findsOneWidget);
    expect(find.text('종료'), findsOneWidget, reason: '멈춰 있어도 끝낼 수 있어야 한다');
  });

  // ── 좁은 폭에서 가로로 안 넘친다 (#386) ──────────────────────
  //
  // 거리·시간·페이스 세 칸이 `Row(spaceAround)` 에 그냥 얹혀 있었다. Row 는 flex 가 아닌
  // 자식에게 폭을 무한대로 주므로 값이 제 길이만큼 자라고, 합이 Row 폭을 넘으면 노란
  // 줄무늬가 뜬다. 360dp 68px, **393dp 에서도 35px** 넘쳤다(2026-09-07 실측).
  //
  // 완료 시트(20pt)보다 이르다 — 글자가 24pt 인데 margin 14+14 · padding 18+18 을 써서
  // 360dp 기기의 안쪽 폭이 296px 밖에 안 된다. 산책 내내 떠 있는 패널이다.

  testWidgets('폭 360dp — 펼침 패널이 가로로 안 넘친다', (tester) async {
    useWidth(tester, 360);
    await tester.pumpWidget(_wrap(expanded: true));

    expect(tester.takeException(), isNull,
        reason: '넘치면 프레임워크가 예외를 남긴다 — 노란 줄무늬는 그 예외의 그림이다');
    expect(find.text('종료'), findsOneWidget, reason: '좁아도 주 동작은 그대로 보인다');
  });

  testWidgets('폭 393dp(에뮬레이터) 에서도 안 넘친다 — 여기서도 35px 넘치던 자리다', (tester) async {
    useWidth(tester, 393);
    await tester.pumpWidget(_wrap(expanded: true));

    expect(tester.takeException(), isNull);
  });

  testWidgets('두 시간을 넘긴 긴 값(120:45 · 12.24)도 360dp 에서 안 넘친다', (tester) async {
    // 패딩·칸 간격을 좁히는 것으로는 여기서 다시 터진다 — 값이 길어지면 어떤 고정 폭도 진다.
    useWidth(tester, 360);
    await tester.pumpWidget(
        _wrap(expanded: true, km: 12.24, timeLabel: '120:45', paceLabel: "120'03\""));

    expect(tester.takeException(), isNull);
    expect(find.text('12.24'), findsOneWidget, reason: '줄이더라도 값을 자르지는 않는다');
  });

  testWidgets('기기 글자 크기를 1.5배로 키워도 360dp 에서 안 넘친다', (tester) async {
    useWidth(tester, 360);
    await tester.pumpWidget(_wrap(expanded: true, textScale: 1.5));

    expect(tester.takeException(), isNull);
  });

  testWidgets('접힘 알약도 360dp 에서, 글자를 키워도 안 넘친다', (tester) async {
    useWidth(tester, 360);
    await tester.pumpWidget(
        _wrap(expanded: false, km: 12.24, timeLabel: '120:45', textScale: 1.5));

    expect(tester.takeException(), isNull);
  });

  testWidgets('세 값은 **같은** 크기로 줄어든다 — 나란한 숫자에 크기가 섞이면 못 견준다', (tester) async {
    // 칸마다 FittedBox 를 하나씩 두면 짧은 값만 24pt 로 남아 줄이 들쭉날쭉해진다.
    // **화면에 그려진** 높이로 잰다 — style.fontSize 만 보면 FittedBox 로 줄인 것을 놓친다.
    useWidth(tester, 360);
    await tester.pumpWidget(
        _wrap(expanded: true, km: 12.24, timeLabel: '120:45', paceLabel: "120'03\""));

    final drawn = ['12.24', '120:45', "120'03\""].map(drawnHeightOf(tester)).toSet();
    expect(drawn, hasLength(1), reason: '셋이 한 크기로 그려져야 한다 — 실제: $drawn');
    expect(valueSizeOf(tester, '120:45'), lessThan(24),
        reason: '360dp 에서는 실제로 줄어든 것이어야 한다 — 잘리거나 넘친 것이 아니라');
  });

  testWidgets('들어가는 폭에서는 24pt 그대로다 — 들어가는데 작게 그리면 그냥 작아진 것이다', (tester) async {
    // 480dp 로 잰다. 위젯 테스트의 폰트는 글자 하나가 정사각형이라 실제 Pretendard 보다
    // 훨씬 넓어서, 24pt 인 이 패널은 **테스트 안에서만** 360dp 에서도 살짝 줄어든다.
    // 실기기 기본 글자 크기로는 안 줄어든다 — 폴더블·태블릿 폭에서 "안 줄인다" 를 잰다.
    useWidth(tester, 480);
    await tester.pumpWidget(_wrap(expanded: true));

    expect(valueSizeOf(tester, '00:42'), 24);
  });
}
