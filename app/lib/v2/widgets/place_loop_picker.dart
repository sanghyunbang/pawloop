// 장소 시트의 "추천 코스" — 이슈 #725.
//
// 1 · 2 · 3km 중 하나를 고르면 서버에 그 장소의 왕복 코스를 묻고, **실제 길이와 시간**을 적고,
// **그 선을 지도 위에 바로 그린다.** "2km" 를 부탁했는데 2.1km 가 오면 2.1km 라고 적는다 —
// 카드가 거짓말하면 안 된다.
//
// 그림이 여기 있는 이유(2026-09-21): 받은 선을 그리는 곳이 추적 화면 하나였고, 그 화면은 장소
// 가까이에 있을 때만 열렸다. 집에서 카드를 눌러 보니 우리 지도에 그려진 코스를 한 번도
// 못 봤다. 처음엔 격자 캔버스(`RouteCanvasPainter`)에 선만 그렸는데 "뒤에 아무것도 없어서
// 어딘지 알 수 없다" 는 지적을 받았다 — 그 캔버스는 지도 키 없이 나가는 빌드(#310)용이다. 지금은
// 키가 있으면 **네이버 지도 위에 선**이고, 키가 없을 때만 캔버스다.
//
// 받은 선은 [onLoop] 로 부르는 쪽에 건넨다. 시트의 "이 코스 걷기" 가 그 선을 `startWalk(courseLine:)`
// 으로 넘기고, 추적 화면이 연한 선으로 깐다(#339 의 그 자리). 못 받으면 한 줄만 적고 나머지 동작은
// 그대로다 — 선은 덧이지 본문이 아니다.
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../core/config/env.dart';
import '../data/place_loop_repository.dart';
import '../theme/app_tokens.dart';
import '../walk/route_image.dart';
import 'form_kit.dart';

class PlaceLoopPicker extends StatefulWidget {
  final String contentId;

  /// 테스트가 갈아 끼운다.
  final PlaceLoopRepository? repository;

  /// 받은 코스(없으면 `null`). 길이를 바꿔 다시 묻는 동안에도 `null` 을 한 번 준다 — 옛 선을 들고
  /// 나가면 안 된다.
  final ValueChanged<PlaceLoop?>? onLoop;

  final int initialLengthM;

  const PlaceLoopPicker({
    super.key,
    required this.contentId,
    this.repository,
    this.onLoop,
    this.initialLengthM = 2000,
  });

  /// 고를 수 있는 길이. 개와 걷는 한 바퀴는 이 셋이면 된다 — 더 길면 코스가 아니라 나들이다.
  static const List<int> lengths = [1000, 2000, 3000];

  @override
  State<PlaceLoopPicker> createState() => _PlaceLoopPickerState();
}

class _PlaceLoopPickerState extends State<PlaceLoopPicker> {
  late final PlaceLoopRepository _repo = widget.repository ?? PlaceLoopRepository();
  late int _lengthM = widget.initialLengthM;
  PlaceLoop? _loop;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lengthM = _lengthM;
    setState(() {
      _loading = true;
      _loop = null;
    });
    widget.onLoop?.call(null);
    final loop = await _repo.fetch(widget.contentId, lengthM: lengthM);
    // 기다리는 사이 다른 길이를 골랐으면 이 답은 버린다 — 늦게 온 2km 가 1km 를 덮으면 안 된다.
    if (!mounted || lengthM != _lengthM) return;
    setState(() {
      _loop = loop;
      _loading = false;
    });
    widget.onLoop?.call(loop);
  }

  void _pick(int lengthM) {
    if (lengthM == _lengthM) return;
    setState(() => _lengthM = lengthM);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final loop = _loop;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 가 아니라 Wrap — 큰 글자(1.6배)·좁은 화면에서 칩 셋이 오른쪽으로 81px 넘쳤다
        // (`explore_place_photo_test` 가 잡음). 자리가 모자라면 칩이 다음 줄로 내려간다.
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.route_rounded, size: 16, color: T.textSecondary),
              SizedBox(width: 7),
              Text('추천 코스',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textSecondary)),
            ]),
          ),
          for (final lengthM in PlaceLoopPicker.lengths)
            PillChip(
              key: Key('loop-len-$lengthM'),
              label: '${lengthM ~/ 1000}km',
              selected: _lengthM == lengthM,
              onTap: () => _pick(lengthM),
            ),
        ]),
        const SizedBox(height: 6),
        if (_loading)
          const Text('코스를 찾는 중…',
              key: Key('loop-loading'), style: TextStyle(fontSize: 12.5, color: T.textMuted))
        else if (loop == null)
          const Text('지금은 추천 코스를 못 받아요',
              key: Key('loop-unavailable'), style: TextStyle(fontSize: 12.5, color: T.textMuted))
        else ...[
          Text(
            '실제 ${loop.distanceLabel} · ${loop.timeLabel} — "이 코스 걷기" 를 누르면 지도에 선으로 깔려요',
            key: const Key('loop-summary'),
            style: const TextStyle(fontSize: 12.5, color: T.textSecondary),
          ),
          const SizedBox(height: 8),
          // 받은 선을 바로 보여 준다 — 걷기 전에, 여기서. 키가 있으면 진짜 지도 위에.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: Env.hasNaverMap ? 200 : 120,
              child: Env.hasNaverMap ? _LoopMapPreview(loop: loop) : _LoopCanvasPreview(loop: loop),
            ),
          ),
        ],
      ]),
    );
  }
}

/// 네이버 지도 위의 코스 선 — 손가락은 안 받는다(시트를 끌 때 지도가 가로채면 안 된다). 길이를 바꾸면
/// 키가 달라져 지도가 새로 선다 — 컨트롤러를 붙들고 선만 갈아 끼우는 것보다 단순하고, 200px 짜리다.
class _LoopMapPreview extends StatelessWidget {
  const _LoopMapPreview({required this.loop});

  final PlaceLoop loop;

  @override
  Widget build(BuildContext context) {
    final coords = [for (final p in loop.lngLat) NLatLng(p[1], p[0])];
    return IgnorePointer(
      child: NaverMap(
        key: ValueKey('loop-map-${loop.contentId}-${loop.targetM}'),
        options: NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(target: coords.first, zoom: 14),
          scrollGesturesEnable: false,
          zoomGesturesEnable: false,
          tiltGesturesEnable: false,
          rotationGesturesEnable: false,
          stopGesturesEnable: false,
          scaleBarEnable: false,
          logoClickEnable: false,
          locale: const Locale('ko'),
        ),
        onMapReady: (c) async {
          await c.addOverlayAll({
            NPolylineOverlay(id: 'loop', coords: coords, color: T.warmEnd, width: 6),
            NMarker(id: 'loop-start', position: coords.first, iconTintColor: T.warmEnd),
          });
          await c.updateCamera(
            NCameraUpdate.fitBounds(NLatLngBounds.from(coords), padding: const EdgeInsets.all(28))
              ..setAnimation(animation: NCameraAnimation.none),
          );
        },
      ),
    );
  }
}

/// 지도 키 없는 빌드(#310)의 대체 — 격자 위 선. 지도 탭 코스 시트와 같은 캔버스라 새 그리기 코드가 없다.
class _LoopCanvasPreview extends StatelessWidget {
  const _LoopCanvasPreview({required this.loop});

  final PlaceLoop loop;

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const Key('loop-preview'),
        painter: RouteCanvasPainter(
          RouteArt(lngLat: loop.lngLat, distanceLabel: '', timeLabel: '', dateLabel: ''),
          withCaption: false,
        ),
        size: Size.infinite,
      );
}
