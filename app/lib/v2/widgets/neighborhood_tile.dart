// lib/v2/widgets/neighborhood_tile.dart
//
// 설정의 "내 동네" 한 줄 — 이슈 #342.
//
// 고른 동네가 있으면 **구까지만** 크게 보이고 동은 작게 따라온다. 남에게 보이는 단위가
// 구라는 것을 이 화면에서부터 같은 모양으로 말한다 — 글 카드에 동이 안 나오는 것을 나중에
// 알면 "내 동네가 잘못 저장됐나" 로 읽힌다.
import 'package:flutter/material.dart';

import '../data/neighborhood_store.dart';
import '../domain/neighborhood.dart';
import '../screens/neighborhood_picker_screen.dart';
import '../theme/app_tokens.dart';

class NeighborhoodTile extends StatefulWidget {
  const NeighborhoodTile({super.key, this.store, this.onPick});

  final NeighborhoodStore? store;

  /// 고르는 화면을 여는 자리. 테스트가 가짜 화면을 준다.
  final Future<Neighborhood?> Function(BuildContext context)? onPick;

  @override
  State<NeighborhoodTile> createState() => _NeighborhoodTileState();
}

class _NeighborhoodTileState extends State<NeighborhoodTile> {
  late final NeighborhoodStore _hood = widget.store ?? NeighborhoodStore();

  Neighborhood? _mine;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    kNeighborhoodRev.addListener(_load);
  }

  @override
  void dispose() {
    kNeighborhoodRev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final mine = await _hood.read();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _loaded = true;
    });
  }

  Future<void> _pick() async {
    final picked = await (widget.onPick ?? _open)(context);
    if (picked == null || !mounted) return;
    setState(() => _mine = picked);
  }

  Future<Neighborhood?> _open(BuildContext context) =>
      Navigator.of(context).push<Neighborhood>(
        MaterialPageRoute(builder: (_) => const NeighborhoodPickerScreen()),
      );

  Future<void> _clear() async {
    await _hood.clear();
    if (!mounted) return;
    setState(() => _mine = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final mine = _mine;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        const Icon(Icons.home_work_outlined, size: 20, color: T.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _pick,
            behavior: HitTestBehavior.opaque,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mine == null ? '동네를 고르면 지도와 글이 그 동네부터 보여요' : mine.districtLabel,
                  style: TextStyle(
                      fontSize: mine == null ? 13.5 : 14.5,
                      fontWeight: FontWeight.w700,
                      color: mine == null ? T.textSecondary : T.textPrimary)),
              const SizedBox(height: 2),
              Text(
                mine == null
                    ? '위치 권한 없이 목록에서 고를 수 있어요'
                    // 남에게 보이는 것은 구까지다. 그 말을 고른 사람에게 먼저 한다.
                    : '${mine.dong} · 남에게는 ${mine.districtLabel} 까지만 보여요',
                style: const TextStyle(fontSize: 12, color: T.textMuted),
              ),
            ]),
          ),
        ),
        if (mine != null)
          GestureDetector(
            onTap: _clear,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('지우기',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textMuted)),
            ),
          ),
        GestureDetector(
          onTap: _pick,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.chevron_right, size: 18, color: T.textFaint),
          ),
        ),
      ]),
    );
  }
}
