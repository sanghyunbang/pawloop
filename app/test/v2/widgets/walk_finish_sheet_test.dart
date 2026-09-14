// 산책 완료 시트 — 이슈 #310. 경로 사진이 갤러리로만 가는가, 실패가 화면을 안 죽이는가.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/walk_moment.dart';
import 'package:heat_trip_flutter/v2/walk/route_image.dart';
import 'package:heat_trip_flutter/v2/walk/route_photo_saver.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_finish_sheet.dart';

const _path = [
  [127.0374, 37.5445],
  [127.0402, 37.5455],
  [127.0420, 37.5430],
];

final _fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

({
  Widget sheet,
  List<String> savedNames,
  List<Uint8List> savedBytes,
  List<String> events,
  List<WalkShareCard> sharedCards,
}) fixture({
  List<List<double>> path = _path,
  RoutePhotoException? saveFails,
  List<WalkMoment> moments = const [],
  // 아이 이름이 없으면 공유 버튼이 아예 안 그려진다 (#344) — 예전 테스트들이
  // 이름 없이 부르므로 기본값도 없음이다.
  String? dogName,
  String? placeName,
  WalkShareException? shareFails,
  // 요약 세 값은 길이가 고정이 아니다 — 두 시간을 넘기면 `120:45`, 10km 를 넘기면 `12.24km`,
  // 아직 못 잰 페이스는 `-'--"` 다. 좁은 화면 테스트가 긴 쪽을 넣어 본다.
  String timeLabel = '18:40',
  String distanceLabel = '1.24km',
  String paceLabel = "15'03\"",
  // 지도 스냅숏(#483) — 있으면 디코더도 가짜로 꽂는다. 진짜 디코더는 route_image_test 가 잰다.
  MapGround? map,
  MapDecoder? decodeMap,
}) {
  final names = <String>[];
  final bytes = <Uint8List>[];
  final events = <String>[];
  final cards = <WalkShareCard>[];
  final sheet = WalkFinishSheet(
    timeLabel: timeLabel,
    distanceLabel: distanceLabel,
    paceLabel: paceLabel,
    art: RouteArt(
      lngLat: path,
      distanceLabel: distanceLabel,
      timeLabel: timeLabel,
      dateLabel: WalkFinishSheet.dateLabel(DateTime(2026, 9, 6, 14, 20)),
      moments: moments,
      map: map,
    ),
    decodeMap: decodeMap ?? decodeImageFromList,
    walkedAt: DateTime(2026, 9, 6, 14, 20),
    // 렌더러는 가짜 — 실제 PNG 는 route_image_test 가 잰다. 여기서는 "만든 바이트가 그대로
    // 저장기로 가는가" 만 본다.
    renderer: (_) async => _fakePng,
    saver: RoutePhotoSaver.fake((b, name) async {
      if (saveFails != null) throw saveFails;
      bytes.add(b);
      names.add(name);
    }),
    onSave: () => events.add('save'),
    onDiscard: () => events.add('discard'),
    dogName: dogName,
    placeName: placeName,
    // 진짜 공유 시트는 OS 가 연다 — 여기서는 "무엇을 넘겼는가" 만 본다.
    shareCard: (card) async {
      cards.add(card);
      final f = shareFails;
      if (f != null) throw f;
    },
    warm: const LinearGradient(colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
  );
  return (sheet: sheet, savedNames: names, savedBytes: bytes, events: events, sharedCards: cards);
}

Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: sheet))));
  await tester.pumpAndSettle();
}

/// 논리 폭 [widthDp] 의 화면에 띄운다 — 물리 픽셀이 아니라 **dp** 로 적는다.
/// 기기 표는 dp 로 말한다(갤럭시 S8·A 다수가 360dp, 픽셀 계열이 393dp).
Future<void> pumpSheetAt(
  WidgetTester tester,
  Widget sheet, {
  required double widthDp,
  double heightDp = 780,
  double textScale = 1.0,
}) async {
  const ratio = 3.0;
  tester.view.physicalSize = Size(widthDp * ratio, heightDp * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    // 화면 크기는 view 에서 온 것을 그대로 두고 글자 배율만 바꾼다 — MediaQueryData 를
    // 통째로 새로 만들면 size 가 0 이 되어 다른 것을 재게 된다.
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: sheet)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 요약 칸에 쓰인 글자 크기(스타일에 적힌 값).
double valueSizeOf(WidgetTester tester, String value) =>
    tester.widget<Text>(find.text(value).first).style!.fontSize!;

/// 화면에 **그려진** 높이. 위·아래 모서리를 전역 좌표로 바꿔 재므로 조상이 걸어 둔
/// 확대·축소(FittedBox 등)까지 함께 잡힌다 — 크기가 스타일에 안 남는 축소를 잡으려면 이쪽이다.
String Function(String) drawnHeightOf(WidgetTester tester) => (String value) {
      final f = find.text(value).first;
      return (tester.getBottomLeft(f).dy - tester.getTopLeft(f).dy).toStringAsFixed(2);
    };

void main() {
  testWidgets('요약 셋과 경로 미리보기, "경로 사진 저장" 이 보인다', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    expect(find.text('산책 완료!'), findsOneWidget);
    expect(find.text('18:40'), findsOneWidget);
    expect(find.text('1.24km'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets, reason: '타일 없이 그린 경로 미리보기');
    expect(find.text('경로 사진 저장'), findsOneWidget);
  });

  testWidgets('"경로 사진 저장" → 렌더한 PNG 가 저장기로 가고 이름은 pawloop_walk_출발시각', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    await tester.tap(find.text('경로 사진 저장'));
    await tester.pumpAndSettle();

    expect(f.savedBytes, [_fakePng]);
    expect(f.savedNames, ['pawloop_walk_20260906_1420']);
    expect(find.text('갤러리에 저장했어요 · 앨범 Pawloop'), findsOneWidget);
    expect(find.text('갤러리에 저장했어요'), findsOneWidget, reason: '버튼이 저장됨으로 바뀐다');

    // 두 번 눌러도 두 장이 되지 않는다
    await tester.tap(find.text('갤러리에 저장했어요'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(f.savedBytes, hasLength(1));
  });

  testWidgets('점이 둘 미만이면 미리보기도 저장 버튼도 없고 이유를 한 줄 적는다', (tester) async {
    final f = fixture(path: const [[127.0374, 37.5445]]);
    await pumpSheet(tester, f.sheet);

    expect(find.text('경로 사진 저장'), findsNothing);
    expect(find.text('경로가 짧아 그림은 못 만들었어요'), findsOneWidget);
    expect(find.text('기록 저장하기'), findsOneWidget, reason: '기록 저장은 경로와 무관하게 된다');
  });

  testWidgets('사진 권한이 없으면 문구를 보여 주고 시트는 살아 있다 — 기록 저장은 여전히 된다', (tester) async {
    final f = fixture(saveFails: const RoutePhotoException(RoutePhotoFailure.permissionDenied));
    await pumpSheet(tester, f.sheet);

    await tester.tap(find.text('경로 사진 저장'));
    await tester.pumpAndSettle();

    expect(find.text('사진 저장 권한이 없어요 · 설정에서 허용해 주세요'), findsOneWidget);
    expect(f.savedBytes, isEmpty);
    expect(find.text('경로 사진 저장'), findsOneWidget, reason: '다시 누를 수 있어야 한다');

    await tester.tap(find.text('기록 저장하기'));
    expect(f.events, ['save']);
  });

  testWidgets('"저장 안 함" 은 onDiscard 를 부른다', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    await tester.tap(find.text('저장 안 함'));
    expect(f.events, ['discard']);
  });

  // ── 산책 중 한 손 기록 (#340) ────────────────────────────

  testWidgets('눌러 둔 것이 있으면 "배변 2회 · 물 1회" 한 줄이 붙는다', (tester) async {
    final f = fixture(moments: const [
      WalkMoment(kind: WalkMomentKind.poop, tSec: 60, pathIndex: 0),
      WalkMoment(kind: WalkMomentKind.poop, tSec: 300, pathIndex: 1),
      WalkMoment(kind: WalkMomentKind.water, tSec: 400, pathIndex: 2),
    ]);
    await pumpSheet(tester, f.sheet);

    expect(find.text('배변 2회 · 물 1회'), findsOneWidget);
  });

  testWidgets('하나도 안 눌렀으면 줄 자체가 없다 — 0회를 적으면 못 한 일처럼 읽힌다', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    expect(find.textContaining('회'), findsNothing);
  });

  testWidgets('낮은 화면에서도 세로로 안 넘친다 — 줄이 하나 늘 때마다 넘치던 자리다', (tester) async {
    // 실측: 요약 줄을 더하자 에뮬레이터에서 **세로로** 26px 넘쳤다(2026-09-07).
    // 393x509dp 는 그 에뮬레이터의 논리 크기다. 세로를 재는 자리라 폭은 넓은 쪽으로 둔다 —
    // 좁은 폭의 **가로** 넘침은 아래 360dp 묶음이 따로 잰다.
    final f = fixture(moments: const [
      WalkMoment(kind: WalkMomentKind.poop, tSec: 60, pathIndex: 0),
      WalkMoment(kind: WalkMomentKind.water, tSec: 400, pathIndex: 2),
    ]);
    await pumpSheetAt(tester, f.sheet, widthDp: 393, heightDp: 509);

    expect(tester.takeException(), isNull,
        reason: '넘치면 프레임워크가 예외를 남긴다 — 노란 줄무늬는 그 예외의 그림이다');
  });

  // ── 좁은 폭에서 가로로 안 넘친다 ──────────────────────────
  //
  // 요약 세 칸이 `Row(spaceAround)` 에 그냥 얹혀 있었다. Row 는 flex 가 아닌 자식에게 폭을
  // 무한대로 주므로 값이 제 길이만큼 자라고, 합이 Row 폭을 넘으면 노란 줄무늬가 뜬다.
  // 폭 360dp 에서 24px, 320dp 에서 64px 넘쳤다(2026-09-07 실측). 요약 줄(#340)이 있든
  // 없든 같은 값이었다 — 세로가 아니라 **가로**가 좁아서 나던 것이다.
  //
  // 360dp 는 갤럭시 S8·A 시리즈 상당수의 논리 폭이다.

  testWidgets('폭 360dp — 요약 줄(#340)과 경로 미리보기가 함께 있어도 가로로 안 넘친다', (tester) async {
    final f = fixture(moments: const [
      WalkMoment(kind: WalkMomentKind.poop, tSec: 60, pathIndex: 0),
      WalkMoment(kind: WalkMomentKind.water, tSec: 400, pathIndex: 2),
    ]);
    await pumpSheetAt(tester, f.sheet, widthDp: 360);

    expect(tester.takeException(), isNull);
    expect(find.text('배변 1회 · 물 1회'), findsOneWidget, reason: '요약 줄이 있는 채로 잰 것이다');
    expect(find.text('경로 사진 저장'), findsOneWidget, reason: '미리보기도 있는 채로 잰 것이다');
  });

  testWidgets('폭 360dp — 요약 줄이 없어도 가로로 안 넘친다', (tester) async {
    // 고친 것이 요약 줄이 아니라 요약 **세 칸**임을 못 박는다.
    await pumpSheetAt(tester, fixture().sheet, widthDp: 360);

    expect(tester.takeException(), isNull);
  });

  testWidgets('두 시간을 넘긴 긴 값(120:45 · 12.24km)도 360dp 에서 안 넘친다', (tester) async {
    // 패딩·칸 간격을 좁히는 것으로는 여기서 다시 터진다 — 값이 길어지면 어떤 고정 폭도 진다.
    final f = fixture(
      timeLabel: '120:45',
      distanceLabel: '12.24km',
      paceLabel: "120'03\"",
      moments: const [WalkMoment(kind: WalkMomentKind.poop, tSec: 60, pathIndex: 0)],
    );
    await pumpSheetAt(tester, f.sheet, widthDp: 360);

    expect(tester.takeException(), isNull);
    expect(find.text('12.24km'), findsOneWidget, reason: '줄이더라도 값을 자르지는 않는다');
  });

  testWidgets('기기 글자 크기를 1.5배로 키워도 360dp 에서 안 넘친다', (tester) async {
    // 실기기에서 줄무늬가 나는 길 중 하나다 — 기본 배율의 Pretendard 는 360dp 에 들어가지만
    // "글자 크기 가장 크게" 로 두면 같은 값이 320px 을 넘는다(2026-09-07 폰트 실측).
    final f = fixture(moments: const [
      WalkMoment(kind: WalkMomentKind.water, tSec: 400, pathIndex: 2),
    ]);
    await pumpSheetAt(tester, f.sheet, widthDp: 360, textScale: 1.5);

    expect(tester.takeException(), isNull);
  });

  testWidgets('세 값은 **같은** 크기로 줄어든다 — 나란한 숫자에 크기가 섞이면 못 견준다', (tester) async {
    // 칸마다 FittedBox 를 하나씩 두면 짧은 "18:40" 만 20pt 로 남고 긴 값은 17.8pt 가 되어
    // 줄이 들쭉날쭉해진다. 가장 긴 값 하나로 배율을 정해 셋에 같이 먹인다.
    await pumpSheetAt(tester, fixture().sheet, widthDp: 360);

    // **화면에 그려진** 높이로 잰다 — style.fontSize 만 보면 FittedBox 로 줄인 것을 놓친다.
    // FittedBox 는 글자 크기가 아니라 그리기를 확대·축소하므로 스타일에는 자국이 안 남는다.
    final drawn = ['18:40', '1.24km', "15'03\""].map(drawnHeightOf(tester)).toSet();
    expect(drawn, hasLength(1), reason: '셋이 한 크기로 그려져야 한다 — 실제: $drawn');
    expect(valueSizeOf(tester, '1.24km'), lessThan(20),
        reason: '360dp 에서는 실제로 줄어든 것이어야 한다 — 잘리거나 넘친 것이 아니라');
  });

  testWidgets('값이 짧으면 줄이지 않는다 — 들어가는데 작게 그리면 그냥 작아진 것이다', (tester) async {
    final f = fixture(timeLabel: '8:40', distanceLabel: '1.2km', paceLabel: "5'03\"");
    await pumpSheetAt(tester, f.sheet, widthDp: 360);

    expect(valueSizeOf(tester, '1.2km'), 20);
  });

  // ── 공유하기 (#344) ─────────────────────────────────────────
  group('공유하기', () {
    testWidgets('아이가 있으면 사진 저장 옆에 공유하기가 있다', (tester) async {
      final f = fixture(dogName: '보리');
      await pumpSheet(tester, f.sheet);

      expect(find.text('공유하기'), findsOneWidget);
      expect(find.text('경로 사진 저장'), findsOneWidget,
          reason: '갤러리로 바로 가던 길(#310)을 없애지 않는다');
    });

    testWidgets('아이가 없으면 공유 버튼이 아예 없다 — 첫 줄이 빈 카드를 만들지 않는다',
        (tester) async {
      await pumpSheet(tester, fixture().sheet);

      expect(find.text('공유하기'), findsNothing);
      expect(find.text('경로 사진 저장'), findsOneWidget);
    });

    testWidgets('누르면 이 산책의 값과 좌표가 그대로 카드로 간다', (tester) async {
      final f = fixture(dogName: '보리', placeName: '서울숲');
      await pumpSheet(tester, f.sheet);

      await tester.tap(find.text('공유하기'));
      await tester.pumpAndSettle();

      expect(f.sharedCards, hasLength(1));
      final card = f.sharedCards.single;
      expect(card.dogName, '보리');
      expect(card.distanceLabel, '1.24km');
      expect(card.timeLabel, '18:40');
      expect(card.placeName, '서울숲');
      expect(card.lngLat, _path,
          reason: '자르기 전 좌표를 그대로 넘긴다 — 자르는 곳은 카드 한 군데다(#339)');
    });

    testWidgets('공유가 실패하면 문구를 띄우고 시트는 살아 있다', (tester) async {
      final f = fixture(dogName: '보리', shareFails: const WalkShareException('공유 앱 없음'));
      await pumpSheet(tester, f.sheet);

      await tester.tap(find.text('공유하기'));
      await tester.pumpAndSettle();

      expect(find.text('공유 시트를 열지 못했어요'), findsOneWidget);
      expect(find.text('공유하기'), findsOneWidget, reason: '버튼이 다시 눌리는 상태로 돌아와야 한다');
    });

    testWidgets('아이가 없으면 사진 버튼이 예전 그대로 가운데 있다', (tester) async {
      // 공유 버튼 자리를 빈 `Expanded` 로 남겨 두면 사진 버튼이 오른쪽 반쪽의
      // 가운데(폭의 75%)로 밀려 난다. 넘치지는 않아서 넘침 검사로는 안 잡힌다.
      await pumpSheetAt(tester, fixture().sheet, widthDp: 360);

      final button = tester.getCenter(find.widgetWithText(TextButton, '경로 사진 저장'));
      final sheet = tester.getCenter(find.byType(WalkFinishSheet));

      expect((button.dx - sheet.dx).abs(), lessThan(1.0),
          reason: '버튼이 ${button.dx}, 시트 가운데가 ${sheet.dx} — 빈 칸이 남아 있다');
    });

    testWidgets('폭 360dp — 버튼이 둘이 되어도 가로로 안 넘친다', (tester) async {
      await pumpSheetAt(tester, fixture(dogName: '보리').sheet, widthDp: 360);

      expect(tester.takeException(), isNull);
    });
  });

  // ── 지도 바닥 (#483) ─────────────────────────────────────────
  group('지도 바닥 (#483)', () {
    ui.Image solid() {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 80), Paint()..color = const Color(0xFF00C853));
      return rec.endRecording().toImageSync(40, 80);
    }

    MapGround ground() => MapGround(
          bytes: _fakePng,
          viewSize: const Size(100, 200),
          screenPoints: [for (var i = 0; i < _path.length; i++) Offset(10.0 + i * 3, 20.0 + i * 5)],
        );

    RouteCanvasPainter previewPainter(WidgetTester tester) => tester
        .widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is RouteCanvasPainter))
        .painter as RouteCanvasPainter;

    testWidgets('스냅숏이 있으면 한 번 디코딩해 미리보기가 지도 위에 그리고, 공유 카드에는 같은 스냅숏이 간다',
        (tester) async {
      var decoded = 0;
      final g = ground();
      final f = fixture(dogName: '보리', map: g, decodeMap: (bytes) async {
        decoded++;
        expect(bytes, same(g.bytes));
        return solid();
      });
      await pumpSheet(tester, f.sheet);

      expect(previewPainter(tester).map, isNotNull, reason: '미리보기의 바닥이 지도다');
      expect(decoded, 1, reason: '바이트는 한 번만 디코딩한다');

      await tester.tap(find.text('공유하기'));
      await tester.pumpAndSettle();
      expect(f.sharedCards.single.map, same(g), reason: '카드도 같은 스냅숏 위에 그린다');
    });

    testWidgets('스냅숏이 없으면 캔버스다 — painter 의 map 이 null 이고 디코더를 부르지 않는다', (tester) async {
      var decoded = 0;
      final f = fixture(decodeMap: (bytes) async {
        decoded++;
        return solid();
      });
      await pumpSheet(tester, f.sheet);

      expect(previewPainter(tester).map, isNull);
      expect(decoded, 0);
    });

    testWidgets('바이트를 못 읽으면 캔버스로 그리고 시트는 살아 있다', (tester) async {
      final f = fixture(map: ground(), decodeMap: (bytes) async => throw StateError('깨진 바이트'));
      await pumpSheet(tester, f.sheet);

      expect(previewPainter(tester).map, isNull);
      expect(find.text('경로 사진 저장'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
