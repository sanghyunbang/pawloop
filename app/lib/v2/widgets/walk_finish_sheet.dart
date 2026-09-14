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
import '../walk/walk_share.dart';
import '../walk/walk_share_card.dart';
import 'walk_summary_row.dart';

/// 화면 트리 밖에서 PNG 를 만드는 함수 — 테스트가 가짜를 꽂는 자리.
typedef RouteRenderer = Future<Uint8List> Function(RouteArt art);

class WalkFinishSheet extends StatefulWidget {
  final String timeLabel;
  final String distanceLabel;

  /// 산책 중 찍은 사진의 기기 안 경로(#450). 시트에 띠로 보이고, 공유 카드의 배경(첫 장)이 된다.
  /// 저장은 이 시트가 아니라 저장 화면 → `WalkSync` 가 한다.
  final List<String> photoPaths;

  /// 경로에서 바이트를 읽는 함수 — 사진이 있으면 반드시 준다(`WalkPhotoStore.read`). 파일은 이 시트가
  /// 읽지 않는다: 이 파일엔 `dart:io` 가 못 들어온다(`route_photo_no_network_test` 가 #310 을 잠근다).
  final Future<Uint8List?> Function(String path)? readPhoto;
  final String paceLabel;

  /// 그릴 경로와 사진에 적을 글자. 점이 둘 미만이면 미리보기·저장 버튼이 안 뜬다.
  final RouteArt art;

  /// 사진 파일 이름에 들어가는 시각(출발 시각).
  final DateTime walkedAt;

  final RoutePhotoSaver saver;
  final RouteRenderer renderer;

  /// 공유 카드에 들어가는 우리 아이 (#344). 아이가 없으면 카드도 없다 —
  /// "누구와 걸었나" 가 이 카드의 첫 줄이라 이름 없이 낼 것이 아니다.
  final String? dogName;

  /// 아이 아바타의 테두리색. 카드의 강조색이 된다.
  final Color dogColor;

  /// 사용자가 붙인 장소 (#338). 없으면 카드에 자리 자체가 없다.
  final String? placeName;

  /// 공유 시트를 여는 함수 — 테스트가 가짜를 꽂는 자리.
  final Future<void> Function(WalkShareCard card) shareCard;

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
    this.dogName,
    this.dogColor = T.warmMid,
    this.placeName,
    this.shareCard = WalkShare.share,
    this.photoPaths = const [],
    this.readPhoto,
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
  /// 띠의 그림 — 경로마다 한 번만 읽는다(다시 그릴 때마다 파일을 또 읽지 않게).
  final Map<String, Future<Uint8List?>> _thumbs = {};

  Future<Uint8List?> _thumb(String path) =>
      _thumbs.putIfAbsent(path, () => widget.readPhoto?.call(path) ?? Future<Uint8List?>.value(null));

  @override
  void initState() {
    super.initState();
    assert(widget.photoPaths.isEmpty || widget.readPhoto != null, '사진이 있으면 읽는 함수도 있어야 한다');
  }

  /// 카드를 그리는 동안 두 번 누르는 것을 막는다.
  bool _sharing = false;

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
          WalkSummaryRow(
            [
              (widget.timeLabel, '시간'),
              (widget.distanceLabel, '거리'),
              (widget.paceLabel, '페이스'),
            ],
            valueSize: 20,
          ),
          // 산책 중 찍은 사진 (#450) — 없으면 줄이 아예 없다.
          if (widget.photoPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            _photoStrip(),
          ],
          // 산책 중에 누른 것들 (#340). 안 눌렀으면 줄이 아예 없다 — 0회를 세어 보여 주면
          // 안 한 일이 못 한 일처럼 읽힌다.
          if (!WalkMomentTally.of(widget.art.moments).isEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: T.surface,
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
            _shareRow(),
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
  /// 찍은 사진 띠 — 한 줄, 왼쪽부터 찍은 순서. 4:5 로 자른다(커뮤니티 카드와 같은 규칙).
  Widget _photoStrip() => SizedBox(
        key: const Key('finish-photos'),
        height: 92,
        child: Row(children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.photoPaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 74,
                  height: 92,
                  child: FutureBuilder<Uint8List?>(
                    future: _thumb(widget.photoPaths[i]),
                    builder: (_, snap) {
                      final bytes = snap.data;
                      if (bytes == null || bytes.isEmpty) return _thumbFallback();
                      return Image.memory(bytes,
                          fit: BoxFit.cover,
                          cacheWidth: 222,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => _thumbFallback());
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text('사진 ${widget.photoPaths.length}장\n기록에 같이 남아요',
                style: const TextStyle(fontSize: 11.5, color: T.textMuted, height: 1.35)),
          ),
        ]),
      );

  /// 아직 안 읽었거나 못 읽는 사진의 자리 — 띠가 흔들리지 않게 같은 크기.
  Widget _thumbFallback() =>
      Container(color: T.surface, child: const Icon(Icons.photo_outlined, color: T.textMuted));

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

  /// 공유하기 · 사진 저장 두 줄 — 이슈 #344.
  ///
  /// 공유가 먼저다. 갤러리 저장은 공유 시트 안에도 있지만, 한 번에 갤러리로 가고 싶은
  /// 사람의 길을 없애지는 않는다(#310 이 만든 길이다).
  /// 아이가 있으면 두 칸, 없으면 예전 그대로 한 칸.
  ///
  /// **빈 `Expanded` 를 남기지 않는다.** 자리만 차지해도 사진 버튼이 오른쪽 반쪽으로
  /// 밀려 나 예전과 다른 화면이 된다 — 아직 아이를 안 넣은 사람에게는 바뀔 이유가 없다.
  /// (넘치지는 않는다. 넘칠 것이라 짐작하고 적었다가 되돌려 보고 초록이라 고쳤다.)
  Widget _shareRow() {
    final dog = widget.dogName;
    if (dog == null || dog.isEmpty) return _photoButton();
    return Row(children: [
      Expanded(child: _shareButton(dog)),
      Expanded(child: _photoButton()),
    ]);
  }

  /// 카드 한 장을 만들어 OS 공유 시트로 (#344).
  ///
  /// **아이 이름이 없으면 아예 안 그린다**([_shareRow] 가 거른다). 카드의 첫 줄이 아이
  /// 이름이라 이름 없이 낼 것이 아니다.
  Widget _shareButton(String dog) {
    return TextButton.icon(
      onPressed: _sharing ? null : () => _share(dog),
      icon: Icon(Icons.ios_share_rounded,
          size: 18, color: _sharing ? T.textMuted : T.warmText),
      label: Text(
        _sharing ? '만드는 중…' : '공유하기',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: _sharing ? T.textMuted : T.warmText,
        ),
      ),
    );
  }

  Future<void> _share(String dogName) async {
    setState(() => _sharing = true);
    try {
      // 첫 사진이 카드의 배경이 된다(#450) — Nike Run Club 처럼 사진 위에 수치를 얹는다.
      // 띠가 이미 읽은 바이트를 다시 쓴다 — 파일을 두 번 열지 않는다.
      final photo = widget.photoPaths.isEmpty ? null : await _thumb(widget.photoPaths.first);
      if (!mounted) return;
      await widget.shareCard(WalkShareCard(
        dogName: dogName,
        accent: widget.dogColor,
        dateLabel: widget.art.dateLabel,
        distanceLabel: widget.distanceLabel,
        timeLabel: widget.timeLabel,
        paceLabel: widget.paceLabel,
        placeName: widget.placeName,
        lngLat: widget.art.lngLat,
        photo: photo,
      ));
    } on WalkShareException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _photoButton() => TextButton.icon(
        onPressed: _saving || _saved ? null : _savePhoto,
        icon: Icon(
          _saved ? Icons.check_circle_rounded : Icons.photo_library_outlined,
          size: 18,
          color: _saved ? const Color(0xFF4CAF88) : T.warmText,
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
            color: _saved ? const Color(0xFF4CAF88) : T.warmText,
          ),
        ),
      );
}
