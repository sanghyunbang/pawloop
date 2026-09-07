// lib/v2/data/walk_care_link.dart
//
// 산책이 서버에 저장되면 오늘의 케어 "산책" 칸에도 남긴다 (#326).
//
// 걸어 봤을 때 산책을 방금 저장했는데 케어 카드의 산책 칸은 "아직" 이었다 — 두 기록이
// 이어져 있지 않았다. 산책 저장 화면이 케어 카드를 직접 알 이유는 없으니, 이 한 조각이
// 둘 사이에 선다: 가족이 있으면 `walk` 케어 로그를 하나 남기고 카드가 다시 읽게 한다.
//
// 가족이 없는 것은 오류가 아니다 — 아무것도 하지 않는다. 다른 실패도 산책 저장을 되돌리지
// 않는다(산책은 이미 서버에 있다). 조용히 false 를 돌려주고 끝난다.
import '../domain/walk_moment.dart';
import '../widgets/today_care_card.dart' show kServerCareRev;
import 'family_repository.dart';

class WalkCareLink {
  WalkCareLink({FamilyRepository? repository}) : _repo = repository ?? FamilyRepository();

  final FamilyRepository _repo;

  /// 케어 로그를 남겼으면 true. 가족이 없거나 못 남겼으면 false — 어느 쪽도 던지지 않는다.
  ///
  /// [moments] 는 산책 중에 한 탭으로 남긴 것들이다(#340). **한 탭에 한 줄**로 보낸다 —
  /// 서버에 묶어 보내는 경로가 없고, 케어 카드가 하루치를 세는 단위가 줄 하나다.
  /// 시각은 서버가 정하므로(계약이 `occurredAt` 을 안 받는다) 눌린 시각이 아니라
  /// **저장한 시각**으로 남는다. 그 차이가 문제가 되는 화면은 아직 없다.
  Future<bool> recordWalk({List<WalkMoment> moments = const []}) async {
    try {
      final group = await _repo.myGroup();
      await _repo.recordCare(group.id, ServerCareType.walk);
      for (final moment in moments) {
        final type = ServerCareType.tryParse(moment.kind.wire);
        if (type == null) continue;
        try {
          await _repo.recordCare(group.id, type);
        } on FamilyFailure {
          // 한 건이 막혀도(429·네트워크) 나머지는 보낸다 — 산책은 이미 저장됐다.
        }
      }
      kServerCareRev.value++;
      return true;
    } on FamilyFailure {
      // noGroup 이 대부분이다. 나머지(401·네트워크)도 여기서 삼킨다 — 산책 저장의 스낵바가
      // 케어 실패 때문에 바뀌면 사용자는 산책이 안 된 줄 안다.
      return false;
    } catch (_) {
      return false;
    }
  }
}
