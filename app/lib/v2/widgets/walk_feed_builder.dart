// lib/v2/widgets/walk_feed_builder.dart
//
// 산책 자료를 불러와 그리는 껍데기 — 이슈 #145.
//
// 화면 넷(홈·통계·기록·프로필)이 같은 자료를 그린다. 각자 `initState` 에서 부르고
// `setState` 로 담게 두면 **"돌아왔을 때 다시 불러오기" 를 한 곳에서 빠뜨리는 날**이
// 오고, 그 화면만 영원히 낡은 값을 보여 준다.
//
// 그래서 불러오기와 갱신 신호 듣기를 여기 한 곳에 둔다.
library;

import 'package:flutter/material.dart';

import '../data/walk_feed.dart';

/// 산책 자료를 불러와 [builder] 에 넘긴다. 자료가 바뀌면 다시 불러온다.
///
/// **처음 한 번은 [WalkFeedData.empty] 로 그린다.** 로딩 스피너를 두지 않는 이유는
/// 이 자료가 화면의 일부(요약 카드·막대)라서, 그 자리만 도는 스피너가 화면을 더
/// 어지럽히기 때문이다. 값이 오면 조용히 바뀐다.
class WalkFeedBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, WalkFeedData data) builder;

  /// 특정 반려동물만. 생략하면 내 전체를 섞는다.
  final int? dogId;

  const WalkFeedBuilder({super.key, required this.builder, this.dogId});

  @override
  State<WalkFeedBuilder> createState() => _WalkFeedBuilderState();
}

class _WalkFeedBuilderState extends State<WalkFeedBuilder> {
  WalkFeedData _data = WalkFeedData.empty;

  /// 겹쳐 들어온 응답이 순서를 거슬러 덮어쓰는 것을 막는다. 늦게 시작한 요청이 먼저
  /// 끝나면 오래된 값이 화면에 남는다.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    walkFeedRevision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    walkFeedRevision.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final mine = ++_generation;
    final data = await WalkFeed().load(dogId: widget.dogId);
    if (!mounted || mine != _generation) return;
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _data);
}
