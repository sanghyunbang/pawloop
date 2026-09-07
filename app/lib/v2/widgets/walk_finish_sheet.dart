// lib/v2/widgets/walk_finish_sheet.dart
//
// 산책 완료 바텀시트 — 트래킹 화면(`walk_tracking_screen.dart`)의 `_finish()` 가 띄운다.
// 이슈 #310 에서 화면 밖으로 꺼냈다: 시트에 **경로 미리보기**와 **"경로 사진 저장"** 이 붙었고,
// 그 둘은 지도·GPS 없이 테스트로 잴 수 있어야 한다(트래킹 화면 자체는 geolocator 와 네이버
// 지도를 물고 있어 위젯 테스트로 못 띄운다).
//
// ## 경로 사진은 갤러리에만 간다
//
// 그림은 `RouteCanvasPainter` 가 타일 없이 그리고(#235 C1 — 네이버 지도 위에 그리면 카메라
// 궤적이 곧 경로라 좌표가 네이버에 간다), PNG 는 `RoutePhotoSaver` 가 기기 갤러리에 넣는다.
// 업로드 경로를 타지 않는다 — `route_photo_no_network_test.dart` 가 소스로 잠근다.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../domain/walk_moment.dart';
import '../walk/route_image.dart';
import '../walk/route_photo_saver.dart';

/// 화면 트리 밖에서 PNG 를 만드는 함수 — 테스트가 가짜를 꽂는 자리.
typedef RouteRenderer = Future<Uint8List> Function(RouteArt art);

class WalkFinishSheet extends StatefulWidget {
  final String timeLabel;
  final String distanceLabel;
  final String paceLabel;

  /// 그릴 경로와 사진에 적을 글자. 점이 둘 미만이면 미리보기·저장 버튼이 안 뜬다.
  final RouteArt art;

  /// 사진 파일 이름에 들어가는 시각(출발 시각).
  final DateTime walkedAt;

  final RoutePhotoSaver saver;
  final RouteRenderer renderer;

  /// "기록 저장하기" · "저장 안 함". 시트를 닫는 것까지 부르는 쪽이 한다.
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  final Gradient warm;

  const WalkFinishSheet({
    super.key,
    required this.timeLabel,
    required this.distanceLabel,
    required this.paceLabel,
    required this.art,
    required this.walkedAt,
    required this.saver,
    required this.onSave,
    required this.onDiscard,
    required this.warm,
    this.renderer = RouteImage.renderPng,
  });

  /// 사진 아래에 적는 날짜 — "2026.09.06 14:20 출발".
  static String dateLabel(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)} 출발';
  }

  @override
  State<WalkFinishSheet> createState() => _WalkFinishSheetState();
}

class _WalkFinishSheetState extends State<WalkFinishSheet> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _savePhoto() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      final png = await widget.renderer(widget.art);
      await widget.saver.save(png, walkedAt: widget.walkedAt);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      _toast('갤러리에 저장했어요 · 앨범 Pawloop');
    } on RoutePhotoException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(const RoutePhotoException(RoutePhotoFailure.other).message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + MediaQuery.of(context).padding.bottom),
      // 줄이 하나 늘 때마다 넘치던 자리다 — 한 손 기록 요약(#340)을 더하자 26px 넘쳤다.
      // 시트 높이는 화면·글자 크기에 따라 달라지므로 넘치면 스크롤로 받는다.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 시스템 이모지 대신 자산 — 디자인 시스템은 Fluent 3D 이모지다(#327).
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              '산책 완료!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary),
            ),
            const SizedBox(width: 6),
            Image.asset('assets/emoji/paw.png', width: 22, height: 22, gaplessPlayback: true),
          ]),
          const SizedBox(height: 16),
          _SummaryRow([
            (widget.timeLabel, '시간'),
            (widget.distanceLabel, '거리'),
            (widget.paceLabel, '페이스'),
          ]),
          // 산책 중에 누른 것들 (#340). 안 눌렀으면 줄이 아예 없다 — 0회를 세어 보여 주면
          // 안 한 일이 못 한 일처럼 읽힌다.
          if (!WalkMomentTally.of(widget.art.moments).isEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F1FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                WalkMomentTally.of(widget.art.moments).summary,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (widget.art.drawable) ...[
            _preview(),
            const SizedBox(height: 10),
            _photoButton(),
            const SizedBox(height: 12),
          ] else ...[
            const Text(
              '경로가 짧아 그림은 못 만들었어요',
              style: TextStyle(fontSize: 12, color: T.textMuted),
            ),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: widget.onSave,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: widget.warm,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text(
                '기록 저장하기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onDiscard,
            child: const Text('저장 안 함', style: TextStyle(color: T.textMuted)),
          ),
        ],
        ),
      ),
    );
  }

  /// 타일 없이 그린 경로. 저장되는 사진과 **같은 painter** 다 — 보이는 것과 저장되는 것이 같다.
  Widget _preview() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: RouteCanvasPainter(widget.art, withCaption: false),
            child: const SizedBox.expand(),
          ),
        ),
      );

  Widget _photoButton() => TextButton.icon(
        onPressed: _saving || _saved ? null : _savePhoto,
        icon: Icon(
          _saved ? Icons.check_circle_rounded : Icons.photo_library_outlined,
          size: 18,
          color: _saved ? const Color(0xFF4CAF88) : const Color(0xFFE07A4E),
        ),
        label: Text(
          _saved
              ? '갤러리에 저장했어요'
              : _saving
                  ? '저장 중…'
                  : '경로 사진 저장',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _saved ? const Color(0xFF4CAF88) : const Color(0xFFE07A4E),
          ),
        ),
      );
}

/// 요약 세 칸 — 시간·거리·페이스.
///
/// ## 왜 재서 줄이나
///
/// 예전엔 `Row(spaceAround)` 에 칸을 그냥 얹었다. Row 는 flex 가 아닌 자식에게 **폭을
/// 무한대로** 주므로 값이 제 길이만큼 자라고, 그 합이 Row 폭을 넘으면 노란 줄무늬가 뜬다.
/// 폭 360dp(갤럭시 S8·A 다수)에서 가로로 24px, 320dp 에서 64px 넘쳤다(2026-09-07 실측).
/// 요약 줄(#340)이 있든 없든 같은 값이었다 — 세로가 아니라 가로가 좁아서 나던 것이다.
///
/// 값은 길이가 고정이 아니다. 시간은 두 시간을 넘기면 `120:45`, 거리는 `12.24km`,
/// 페이스는 아직 못 잰 동안 `-'--"` 다. 그래서 패딩이나 칸 간격을 좁히는 것으로는 못 막는다 —
/// 한 기기에서만 맞고 값이 길어지면 다시 터진다. 칸을 정확히 1/3 로 나눠 넘침 자체를 없애고
/// (`Expanded` 는 자식에게 꽉 찬 폭을 준다 — 넘치는 대신 글자가 제 안에서 처리된다),
/// 그 폭에 안 들어갈 때만 글자를 줄인다.
///
/// ## 세 칸이 **같은 크기**로 줄어든다
///
/// 칸마다 `FittedBox` 를 하나씩 두면 짧은 값은 20pt, 긴 값은 17.8pt 가 되어 한 줄에 크기가
/// 섞인다. 나란히 놓인 숫자는 같은 크기여야 한눈에 견줄 수 있으므로, 가장 긴 값 하나로
/// 배율을 정해 셋에 같이 먹인다.
class _SummaryRow extends StatelessWidget {
  /// (값, 라벨) 쌍.
  final List<(String, String)> cells;
  const _SummaryRow(this.cells);

  /// 넓은 화면에서 쓰던 크기 — 여기서부터 줄어들 뿐, 넘어서 커지지는 않는다.
  static const double baseSize = 20;

  static TextStyle valueStyle(double size) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: T.textPrimary);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final size = _sizeThatFits(context, box.maxWidth / cells.length);
          return Row(
            children: [
              for (final (value, label) in cells)
                Expanded(child: _SumCell(value, label, valueSize: size)),
            ],
          );
        },
      );

  /// 한 칸 폭 안에 세 값이 **모두** 들어가는 글자 크기. 다 들어가면 [baseSize] 그대로다.
  ///
  /// 테마 폰트(Pretendard)와 기기 글자 크기 배율까지 실제로 그릴 때와 같게 재야 한다 —
  /// 기본 스타일을 빼고 재면 폭을 잘못 잡아 다시 넘친다.
  double _sizeThatFits(BuildContext context, double cellWidth) {
    // 가로가 무한한 곳(가로 스크롤 등)에 놓이면 잴 것이 없다 — 원래 크기로 둔다.
    if (!cellWidth.isFinite || cellWidth <= 0) return baseSize;
    final base = DefaultTextStyle.of(context).style.merge(valueStyle(baseSize));
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final (value, _) in cells) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: base),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
    }
    // 딱 맞게 줄이면 반올림 한 픽셀에 끝 글자가 잘린다. 1px 을 남긴다.
    final room = cellWidth - 1;
    if (widest <= room || widest == 0) return baseSize;
    return baseSize * room / widest;
  }
}

class _SumCell extends StatelessWidget {
  final String value;
  final String label;

  /// 세 칸이 함께 쓰는 크기 — [_SummaryRow] 가 정한다.
  final double valueSize;
  const _SumCell(this.value, this.label, {required this.valueSize});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: _SummaryRow.valueStyle(valueSize),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0x9E463C64)),
          ),
        ],
      );
}
