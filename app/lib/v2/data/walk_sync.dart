// lib/v2/data/walk_sync.dart
//
// 초안을 서버로 밀어 올리는 **정책** — 이슈 #145.
//
// ## 왜 화면이 아니라 여기인가
//
// "언제 재시도하고 언제 포기하는가" 는 화면마다 다르면 안 된다. 저장 화면이 400 을
// 재시도로 다루고 홈은 아니라면, 같은 초안이 어느 화면을 지났느냐에 따라 살거나
// 죽는다. 판정이 한 곳에 있어야 한다.
//
// ## 순서
//
//  1. 초안을 **먼저 큐에 넣는다.** 전송을 시도하기 전이다 — 여기서 앱이 죽어도 남는다.
//  2. 반려동물 id 를 정한다. 없으면 큐에 남기고 물러난다(등록 뒤에 다시 나간다).
//  3. 보낸다. 성공하면 큐에서 뺀다.
//  4. 재시도 가능한 실패면 큐에 남기고, 영구 거절이면 거절 큐로 옮긴다.
library;

import 'walk_feed.dart';
import 'walk_outbox.dart';
import 'walk_repository.dart';

/// 한 번의 밀어올리기 결과.
enum WalkSyncOutcome {
  /// 서버에 저장됐다.
  saved,

  /// 아직 못 보냈다. **큐에 남아 있고 나중에 다시 나간다.**
  queued,

  /// 서버가 영구히 거절했다. 거절 큐로 옮겼다.
  rejected,
}

class WalkSyncResult {
  final WalkSyncOutcome outcome;

  /// 저장됐으면 서버가 준 산책.
  final ServerWalk? walk;

  /// 못 보냈으면 그 이유. 화면이 그대로 보여 준다.
  final String? reason;

  /// **반려동물이 없어서** 못 보냈나.
  ///
  /// 이걸 문구로 판별하게 두면(reason 문자열 비교) 문구를 고치는 날 조용히 깨진다.
  /// 화면은 이 값으로 등록 시트를 띄울지 정한다 (#159).
  final bool needsPet;

  const WalkSyncResult(this.outcome,
      {this.walk, this.reason, this.needsPet = false});
}

/// 초안 큐를 서버로 밀어 올린다.
class WalkSync {
  final WalkRepository _repo;
  final WalkOutbox _outbox;

  WalkSync(this._repo, this._outbox);

  static Future<WalkSync> open({WalkRepository? repository}) async =>
      WalkSync(repository ?? WalkRepository(), await WalkOutbox.open());

  List<WalkDraft> get pending => _outbox.pending;

  List<WalkDraft> get rejected => _outbox.rejected;

  /// 초안 하나를 저장한다. **큐에 먼저 넣고 시작한다.**
  ///
  /// [dogId] 를 주지 않으면 서버의 첫 반려동물을 쓴다. 한 마리도 없으면 보내지 않고
  /// 큐에 남긴다 — 계약이 `dogId` 를 필수로 요구하므로 지어낼 수 없다.
  Future<WalkSyncResult> push(WalkDraft draft, {int? dogId}) async {
    // 1. 무엇보다 먼저 남긴다. 이 줄 다음에 무슨 일이 나도 기록은 살아 있다.
    await _outbox.put(draft);

    final int resolved;
    try {
      resolved = dogId ?? draft.dogId ?? await _firstPetId();
    } on WalkFailure catch (e) {
      return WalkSyncResult(WalkSyncOutcome.queued, reason: e.message);
    } on StateError {
      // 서버에 한 마리도 없다. 화면이 등록 시트를 띄울 수 있게 표시해 준다.
      return const WalkSyncResult(
        WalkSyncOutcome.queued,
        reason: '반려동물을 등록하면 이 산책을 올릴게요',
        needsPet: true,
      );
    }

    final withDog = draft.copyWith(dogId: resolved);
    await _outbox.put(withDog);

    try {
      final walk = await _repo.saveWalk(
        dogId: resolved,
        dogIds: withDog.dogIds,
        clientWalkId: withDog.clientWalkId,
        startedAt: withDog.startedAt,
        endedAt: withDog.endedAt,
        distanceM: withDog.distanceM,
        durationS: withDog.durationS,
        path: withDog.path.isEmpty ? null : withDog.path,
        pathT: withDog.pathT.isEmpty ? null : withDog.pathT,
        memo: withDog.memo,
        weather: withDog.weather,
        place: withDog.place,
      );
      await _outbox.remove(withDog.clientWalkId);
      // 화면들이 이 신호를 듣고 다시 불러온다. 없으면 저장하고 홈으로 돌아와도
      // "오늘 0회" 가 그대로다.
      notifyWalksChanged();
      return WalkSyncResult(WalkSyncOutcome.saved, walk: walk);
    } on WalkFailure catch (e) {
      if (e.retryable) {
        await _outbox.put(withDog.copyWith(lastError: e.message));
        return WalkSyncResult(WalkSyncOutcome.queued, reason: e.message);
      }
      // 다시 보내도 같다. 대기 큐에 두면 그 자리가 막히고 정상 기록이 밀려난다.
      await _outbox.reject(withDog, e.message);
      return WalkSyncResult(WalkSyncOutcome.rejected, reason: e.message);
    }
  }

  /// 밀린 것을 전부 내보낸다. 화면이 열릴 때 부른다.
  ///
  /// **처음 막히는 곳에서 멈춘다.** 연결이 없으면 나머지도 같은 이유로 실패할 것이고,
  /// 그 실패들이 각각 12초 타임아웃을 쓰면 화면이 오래 멈춘다.
  ///
  /// @return 이번에 서버로 올라간 수
  Future<int> flush() async {
    final queue = _outbox.pending;
    if (queue.isEmpty) return 0;

    int sent = 0;
    for (final draft in queue) {
      final result = await push(draft);
      if (result.outcome == WalkSyncOutcome.saved) {
        sent++;
      } else if (result.outcome == WalkSyncOutcome.queued) {
        break;
      }
      // 거절된 것은 큐에서 빠졌으므로 계속 진행한다.
    }
    return sent;
  }

  Future<void> discardRejected(String clientWalkId) =>
      _outbox.discardRejected(clientWalkId);

  /// 서버의 첫 반려동물. 한 마리도 없으면 [StateError].
  Future<int> _firstPetId() async {
    final pets = await _repo.pets();
    if (pets.isEmpty) {
      throw StateError('no pet');
    }
    return pets.first.id;
  }
}
