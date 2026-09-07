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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SumCell(widget.timeLabel, '시간'),
              _SumCell(widget.distanceLabel, '거리'),
              _SumCell(widget.paceLabel, '페이스'),
            ],
          ),
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

class _SumCell extends StatelessWidget {
  final String value;
  final String label;
  const _SumCell(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: T.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
        ],
      );
}
