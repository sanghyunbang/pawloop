// lib/v2/data/walk_goal_store.dart
//
// 주간 산책 목표를 기기에 적는다 — 이슈 #341.
//
// ## 왜 서버가 아닌가
//
// 목표는 그 사람이 자기 아이에게 세운 약속이지 계약에 있는 값이 아니다. 서버에 두면
// 표 하나·엔드포인트 둘·마이그레이션 하나가 생기는데, 그것으로 사는 것은 "기기를 바꿔도
// 목표가 남는다" 하나뿐이다. 그 하나는 다시 세우면 되는 것이고, 제안값이 있어서 다시
// 세우는 데 두 탭이 든다.
//
// 서버에 둘 이유가 생기는 시점은 **가족이 같은 목표를 본다** 를 할 때다. 그때는
// `family_group` 아래로 간다.
//
// ## 아이마다 따로 둔다
//
// 소형견과 대형견의 권장량이 두 배 다르다. 한 사람이 둘을 키우는데 목표가 하나면 그 값은
// 둘 다에게 틀린다. 그래서 키에 **서버의 반려동물 id** 를 붙인다. 아직 서버에 없는 아이는
// id 가 없으므로 공통 자리에 적고, 등록되면 그 아이 자리로 옮겨 간다 —
// 옮기는 코드를 쓰지 않는다. 등록 전에 목표를 세우는 사람이 드물고, 그 경우 제안값이
// 다시 뜬다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/walk_goal.dart';

/// 목표가 바뀐 횟수. 목표 시트가 저장하면 올리고, 홈이 그것을 보고 다시 읽는다.
///
/// `kServerCareRev`(오늘의 케어)와 같은 방식이다 — 화면 사이에 저장소를 직접 넘기지 않고
/// "바뀌었다" 만 알린다.
final ValueNotifier<int> kWalkGoalRev = ValueNotifier<int>(0);

class WalkGoalStore {
  const WalkGoalStore();

  static const _prefix = 'v2.walk_goal';

  static String _keyFor(int? petId) => petId == null ? _prefix : '$_prefix.$petId';

  /// 저장된 목표. 세운 적이 없으면 `null` — 그때 화면이 제안값을 쓴다.
  Future<WalkGoal?> read({int? petId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(petId));
    if (raw == null) return null;
    try {
      return WalkGoal.tryParse(jsonDecode(raw));
    } on FormatException {
      // 깨진 값 하나 때문에 홈이 죽지 않는다. 제안값으로 돌아간다.
      return null;
    }
  }

  Future<void> save(WalkGoal goal, {int? petId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(petId), jsonEncode(goal.toJson()));
    kWalkGoalRev.value++;
  }

  /// 제안값으로 되돌린다 — 지우는 것이 곧 "앱이 제안하는 대로" 다.
  Future<void> clear({int? petId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(petId));
    kWalkGoalRev.value++;
  }
}
