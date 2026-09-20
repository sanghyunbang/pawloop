// 장소 시트의 "추천 코스" — 이슈 #725.
//
// 1 · 2 · 3km 중 하나를 고르면 서버에 그 장소의 왕복 코스를 묻고, **실제 길이와 시간**을 적는다.
// "2km" 를 부탁했는데 2.1km 가 오면 2.1km 라고 적는다 — 카드가 거짓말하면 안 된다.
//
// 받은 선은 [onLoop] 로 부르는 쪽에 건넨다. 시트의 "이 코스 걷기" 가 그 선을 `startWalk(courseLine:)`
// 으로 넘기고, 추적 화면이 연한 선으로 깐다(#339 의 그 자리). 못 받으면 한 줄만 적고 나머지 동작은
// 그대로다 — 선은 덧이지 본문이 아니다.
import 'package:flutter/material.dart';

import '../data/place_loop_repository.dart';
import '../theme/app_tokens.dart';
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
        Row(children: [
          const Icon(Icons.route_rounded, size: 16, color: T.textSecondary),
          const SizedBox(width: 7),
          const Text('추천 코스',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textSecondary)),
          const SizedBox(width: 10),
          for (final lengthM in PlaceLoopPicker.lengths)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: Key('loop-len-$lengthM'),
                label: '${lengthM ~/ 1000}km',
                selected: _lengthM == lengthM,
                onTap: () => _pick(lengthM),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        if (_loading)
          const Text('코스를 찾는 중…',
              key: Key('loop-loading'), style: TextStyle(fontSize: 12.5, color: T.textMuted))
        else if (loop == null)
          const Text('지금은 추천 코스를 못 받아요',
              key: Key('loop-unavailable'), style: TextStyle(fontSize: 12.5, color: T.textMuted))
        else
          Text(
            '실제 ${loop.distanceLabel} · ${loop.timeLabel} — "이 코스 걷기" 를 누르면 지도에 선으로 깔려요',
            key: const Key('loop-summary'),
            style: const TextStyle(fontSize: 12.5, color: T.textSecondary),
          ),
      ]),
    );
  }
}
