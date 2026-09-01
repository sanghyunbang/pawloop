// lib/v2/data/walk_feed.dart
//
// 화면 넷이 함께 쓰는 산책 읽기 계층 — 이슈 #145.
//
// ## 왜 한 곳인가
//
// 홈·통계·기록·프로필 네 화면이 같은 것을 그린다. 각자 서버를 부르게 두면
// **"전송 대기 중인 산책을 어디까지 보여 주는가" 가 화면마다 달라진다.** 홈은 보여 주고
// 기록 목록은 안 보여 주면, 사용자는 홈에서 본 산책을 목록에서 찾다가 사라졌다고 읽는다.
//
// ## 화면이 거짓말하지 않는다
//
// 서버 응답과 **전송 대기 초안을 함께** 준다. 대기 중인 것은 화면에서 "전송 대기" 로
// 그려진다 — 없는 것처럼 감추지도, 저장된 것처럼 보이지도 않는다.
library;

import 'package:flutter/foundation.dart';

import 'walk_outbox.dart';
import 'walk_repository.dart';
import 'walk_sync.dart';

/// 화면 하나가 그릴 한 벌.
class WalkFeedData {
  /// 서버에 저장된 산책들. 최신 기록순이다(걸은 순서가 아니다 — 서버가 그렇게 정렬한다).
  final List<ServerWalk> walks;

  /// 아직 서버에 없는 초안들. 화면은 이것을 **"전송 대기"** 로 그린다.
  final List<WalkDraft> pending;

  /// 서버가 **다시 보내도 소용없다고 거절한** 초안들(400 등).
  ///
  /// `WalkOutbox.reject` 가 이것을 지우지 않고 남기는 이유를 화면까지 이어야 한다 —
  /// 사용자가 실제로 걸은 기록이고, 왜 못 올라갔는지 보고 스스로 지울 기회를 줘야
  /// 한다. **조용히 버리면 그건 사라진 것과 같다.**
  ///
  /// 이 목록을 나르지 않던 동안 큐에는 남아 있는데 화면 어디에서도 읽지 않아,
  /// `create_screen` 의 1.8초 스낵바를 놓치면 산책이 통째로 사라진 줄 알았다 (#161).
  final List<WalkDraft> rejected;

  /// 서버가 낸 통계. **대기 중인 것은 여기 안 들어 있다** — 서버가 모르는 값이다.
  final ServerWalkStats stats;

  /// 서버를 못 불렀나. 참이면 화면은 통계를 0 으로 그리되 **"불러오지 못했다"** 를
  /// 말해야 한다. 0 을 그냥 보여 주면 "산책을 한 번도 안 했다" 로 읽힌다.
  final bool offline;

  /// 다음 장의 커서. **`null` 이면 끝이다.**
  ///
  /// 이게 없던 동안 목록이 첫 장(30건)에서 끊겼는데 요약 카드는 서버 집계
  /// (`allTimeCount`)를 그렸다 — 40회라고 적힌 화면에 30개만 있었다 (#161).
  final String? nextCursor;

  final bool hasMore;

  const WalkFeedData({
    required this.walks,
    required this.pending,
    required this.stats,
    required this.offline,
    this.rejected = const [],
    this.nextCursor,
    this.hasMore = false,
  });

  static const empty = WalkFeedData(
    walks: [],
    pending: [],
    stats: ServerWalkStats.empty,
    offline: true,
  );

  /// 다음 장을 이어 붙인 새 값.
  WalkFeedData appending(ServerWalkPage page) => WalkFeedData(
        walks: [...walks, ...page.items],
        pending: pending,
        rejected: rejected,
        stats: stats,
        offline: false,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );

  /// 화면에 그릴 것이 하나라도 있나. **거절된 것도 센다** — 그것마저 없는 것으로
  /// 치면 "아직 산책 기록이 없어요" 아래에 거절 카드가 놓이는 모순이 생긴다.
  bool get hasAnything =>
      walks.isNotEmpty || pending.isNotEmpty || rejected.isNotEmpty;

  /// 오늘 걸은 것. **대기 중인 것도 센다** — 사용자는 이미 걸었다.
  ///
  /// 통계 응답의 `weekKm` 으로 오늘 거리는 알 수 있지만 **건수와 시간은 알 수 없다.**
  /// 그래서 목록에서 오늘 것을 골라 접는다. 하루에 20번 넘게 걷는 사람은 없으므로
  /// 첫 장이면 충분하다.
  ({int count, double km, int minutes}) get today {
    final now = DateTime.now();
    bool isToday(DateTime t) =>
        t.year == now.year && t.month == now.month && t.day == now.day;

    var count = 0;
    var meters = 0;
    var seconds = 0;

    for (final walk in walks) {
      if (!isToday(walk.startedAt)) continue;
      count++;
      meters += walk.distanceM;
      seconds += walk.durationS;
    }
    for (final draft in pending) {
      if (!isToday(draft.startedAt)) continue;
      count++;
      meters += draft.distanceM;
      seconds += draft.durationS;
    }

    return (count: count, km: meters / 1000.0, minutes: seconds ~/ 60);
  }

  /// 이번 주 요일별 거리(월요일부터, 길이 7). **대기 중인 것을 얹는다.**
  ///
  /// 서버 통계만 그리면 방금 걸었는데 막대가 안 오르고, 사용자는 기록이 안 됐다고 읽는다.
  List<double> get weekKmWithPending {
    final week = List<double>.from(stats.weekKm);
    final monday = _mondayOf(DateTime.now());

    for (final draft in pending) {
      final day = DateTime(
        draft.startedAt.year,
        draft.startedAt.month,
        draft.startedAt.day,
      );
      final index = day.difference(monday).inDays;
      if (index >= 0 && index < 7) {
        week[index] += draft.km;
      }
    }
    return week;
  }

  /// 오늘이 주간 막대의 몇 번째인가. **월요일이 0 이다.**
  ///
  /// 예전에는 `kWalkTodayIdx = 6` 이라는 상수였고, 그래서 오늘 막대 강조가 **영원히
  /// 일요일**이었다.
  static int get todayIndex => DateTime.now().weekday - 1;

  static DateTime _mondayOf(DateTime t) {
    final day = DateTime(t.year, t.month, t.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}

/// 산책 자료가 바뀌었다는 신호.
///
/// 저장·전송·삭제가 일어나면 값이 하나 오른다. 화면들은 이것을 듣고 다시 불러온다.
///
/// **왜 필요한가.** 산책을 저장하고 홈으로 돌아왔는데 "오늘 0회" 가 그대로면 사용자는
/// 기록이 안 됐다고 읽는다. 화면마다 "돌아왔을 때 다시 불러오기" 를 손으로 붙이면 한
/// 곳을 빠뜨리는 날이 오고, 그 화면만 영원히 낡은 값을 보여 준다.
final ValueNotifier<int> walkFeedRevision = ValueNotifier<int>(0);

/// 자료가 바뀌었다고 알린다. 성공한 저장·전송·삭제가 부른다.
void notifyWalksChanged() => walkFeedRevision.value++;

/// 서버 + 전송 대기 큐를 합쳐 화면에 준다.
class WalkFeed {
  /// 목록 첫 장의 크기. 홈의 "오늘" 집계와 기록 목록이 같은 응답을 쓴다.
  static const int pageSize = 30;

  final WalkRepository _repo;

  WalkFeed({WalkRepository? repository}) : _repo = repository ?? WalkRepository();

  /// 화면이 열릴 때 한 번.
  ///
  /// **밀린 초안을 먼저 내보낸다.** 그래야 방금 연결이 돌아온 사람의 기록이 이 화면에서
  /// 바로 서버 것으로 바뀐다.
  Future<WalkFeedData> load({int? dogId}) async {
    // 큐를 비우는 것이 실패해도 읽기는 계속한다 — 연결이 없으면 아래도 실패하지만,
    // 여기서 던지면 대기 목록조차 못 보여 준다.
    List<WalkDraft> pending = const [];
    List<WalkDraft> rejected = const [];
    try {
      final sync = await WalkSync.open(repository: _repo);
      await sync.flush();
      pending = sync.pending;
      rejected = sync.rejected;
    } catch (_) {
      // 저장소를 못 열었다. 대기 목록 없이 서버 것만 보여 준다.
    }

    try {
      final results = await Future.wait([
        _repo.walks(dogId: dogId, limit: pageSize),
        _repo.stats(dogId: dogId),
      ]);
      final page = results[0] as ServerWalkPage;
      return WalkFeedData(
        walks: page.items,
        pending: pending,
        rejected: rejected,
        stats: results[1] as ServerWalkStats,
        offline: false,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } on WalkFailure {
      // 서버를 못 불렀다. **대기 중인 것은 그대로 보여 준다** — 그것마저 감추면
      // 방금 걸은 산책이 사라진 것처럼 보인다.
      return WalkFeedData(
        walks: const [],
        pending: pending,
        rejected: rejected,
        stats: ServerWalkStats.empty,
        offline: true,
      );
    }
  }

  /// 다음 장. **커서가 없으면 부르지 마라** — 서버는 커서 없는 요청을 첫 장으로 답한다.
  ///
  /// 실패하면 `null` 이다. 다음 장을 못 받았다고 **이미 그린 목록을 버리지 않는다.**
  Future<ServerWalkPage?> more(String cursor, {int? dogId}) async {
    try {
      return await _repo.walks(dogId: dogId, cursor: cursor, limit: pageSize);
    } on WalkFailure {
      return null;
    }
  }
}
