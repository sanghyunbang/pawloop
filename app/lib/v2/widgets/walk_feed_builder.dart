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

import '../data/auth_state.dart';
import 'package:flutter/material.dart';

import '../data/walk_feed.dart';

/// 산책 자료를 불러와 [builder] 에 넘긴다. 자료가 바뀌면 다시 불러온다.
///
/// **처음 한 번은 [WalkFeedData.empty] 로 그린다.** 로딩 스피너를 두지 않는 이유는
/// 이 자료가 화면의 일부(요약 카드·막대)라서, 그 자리만 도는 스피너가 화면을 더
/// 어지럽히기 때문이다. 값이 오면 조용히 바뀐다.
class WalkFeedBuilder extends StatefulWidget {
  /// [loadMore] 는 다음 장이 **있을 때만** 준다. `null` 이면 끝이다 —
  /// 화면은 그때 '더 보기' 를 그리지 않는다.
  final Widget Function(
    BuildContext context,
    WalkFeedData data,
    Future<void> Function()? loadMore,
  ) builder;

  /// 특정 반려동물만. 생략하면 내 전체를 섞는다.
  final int? dogId;

  /// 자료를 어디서 읽는가. **테스트만 넘긴다.**
  ///
  /// 이게 없던 동안 이 껍데기를 쓰는 화면 넷은 위젯 테스트가 불가능했다 — 안에서
  /// `WalkFeed()` 를 직접 만들어 진짜 네트워크를 탔기 때문이다. 그래서 "큐에는
  /// 있는데 화면이 안 읽는다" 같은 결함(#161)을 테스트로 잡을 수 없었다.
  final WalkFeed? feed;

  const WalkFeedBuilder({
    super.key,
    required this.builder,
    this.dogId,
    this.feed,
  });

  @override
  State<WalkFeedBuilder> createState() => _WalkFeedBuilderState();
}

class _WalkFeedBuilderState extends State<WalkFeedBuilder> {
  WalkFeedData _data = WalkFeedData.empty;

  late final WalkFeed _feed = widget.feed ?? WalkFeed();

  /// 겹쳐 들어온 응답이 순서를 거슬러 덮어쓰는 것을 막는다. 늦게 시작한 요청이 먼저
  /// 끝나면 오래된 값이 화면에 남는다.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    walkFeedRevision.addListener(_reload);
    // 게스트로 봤다가 로그인하면 값이 바뀐다 — 신호 없이 두면 홈이 "로그인하면" 을 계속 말한다.
    AuthState.status.addListener(_reload);
    _reload();
  }

  /// 고른 아이가 바뀌면 다시 읽는다 — 이슈 #563.
  ///
  /// 이게 없으면 홈에서 아이를 바꿔도 **요약과 주간 목표가 앞 아이의 숫자로 남는다.**
  /// 히어로는 뭉치인데 숫자는 보리 것인 화면이 된다.
  @override
  void didUpdateWidget(WalkFeedBuilder old) {
    super.didUpdateWidget(old);
    if (old.dogId != widget.dogId) _reload();
  }

  @override
  void dispose() {
    walkFeedRevision.removeListener(_reload);
    AuthState.status.removeListener(_reload);
    super.dispose();
  }

  /// 다음 장을 받는 중인가. 두 번 눌러도 한 번만 나간다.
  bool _loadingMore = false;

  Future<void> _reload() async {
    final mine = ++_generation;
    // 실패한 화면에서 다시 읽을 때는 **먼저 "모름" 으로 돌아간다**(#568). 안 그러면
    // "다시 시도" 를 눌러도 화면이 그대로라 눌렸는지 알 수 없고, 같은 실패가 반복되면
    // 아무 일도 안 일어난 것처럼 보인다.
    //
    // 이미 그린 **성공한** 자료는 안 버린다 — 갱신 신호마다 화면이 비면 산책을 저장할
    // 때마다 목록이 한 번씩 사라진다.
    if (_data.offline && !_data.loading) {
      setState(() => _data = WalkFeedData.empty);
    }
    final data = await _feed.load(dogId: widget.dogId);
    if (!mounted || mine != _generation) return;
    setState(() => _data = data);
  }

  /// 다음 장을 이어 붙인다.
  ///
  /// 실패하면 **아무것도 안 바꾼다** — 이미 그린 목록을 버리면 사용자는 기록이
  /// 사라졌다고 읽는다.
  Future<void> _loadMore() async {
    final cursor = _data.nextCursor;
    if (cursor == null || _loadingMore) return;
    final mine = _generation;
    setState(() => _loadingMore = true);

    final page = await _feed.more(cursor, dogId: widget.dogId);
    if (!mounted || mine != _generation) return;
    setState(() {
      _loadingMore = false;
      if (page != null) _data = _data.appending(page);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        _data,
        _data.hasMore && _data.nextCursor != null ? _loadMore : null,
      );
}
