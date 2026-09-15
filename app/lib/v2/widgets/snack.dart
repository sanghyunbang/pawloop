// lib/v2/widgets/snack.dart
//
// 말풍선(SnackBar)이 **언제 사라지는가** — 그 한 가지 규칙만 여기 있습니다.
//
// ## 왜 이 자리가 따로 있나 (#531)
//
// 플러터 3.32 부터 `SnackBar` 는 `action` 이 있으면 `persist` 가 **기본 참**이고,
// `persist` 면 `duration` 을 **통째로 무시한다**.
//
// ```dart
// // material/snack_bar.dart
// persist = persist ?? action != null;
//
// // material/scaffold.dart — 시간이 다 됐을 때
// if (snackBar.persist) {
//   return;                 // 안 닫는다
// }
// hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
// ```
//
// 우리 말풍선은 화면 맨 아래, **탭 바 위**에 뜬다. 안 사라지면 홈·지도·일정·커뮤니티·채팅
// 어느 것도 못 누른다. 산책을 저장한 사람이 6분 뒤에도 탭을 못 눌렀다(#531). 적어 둔
// `duration: 3.2초` 는 조용히 거짓말이 되어 있었다.
//
// ## 그런데 원래 의도는 접근성이었다
//
// 옛 플러터의 조건은 `action != null && accessibleNavigation` 이었다 — **화면 낭독기**를 쓰는
// 사람이 버튼까지 짚어 갈 시간이 필요하기 때문이다. 그 카브아웃은 옳다. 지금 판은 그것을
// 모두에게 적용해 버린 것이 문제다. 그래서 여기서 **옛 조건 그대로** 돌려준다.
//
// 값은 말풍선을 띄우는 순간에 정해진다. 옛 판은 시간이 다 됐을 때 다시 봤지만("in case the
// setting changed"), 말풍선이 떠 있는 몇 초 사이에 낭독기를 켜는 경우까지 맞출 필요는 없다.
import 'package:flutter/material.dart';

/// [SnackBar.persist] 에 넣을 값 — **낭독기를 쓸 때만 참**이다.
///
/// 버튼이 달린 말풍선을 만들 때 반드시 적는다:
///
/// ```dart
/// SnackBar(
///   content: Text('산책이 기록됐어요'),
///   duration: const Duration(milliseconds: 3200),
///   action: SnackBarAction(label: '보기', onPressed: _openRecords),
///   persist: snackBarPersists(context),
/// )
/// ```
///
/// 안 적으면 `snackbar_action_must_not_persist_test.dart` 가 빨간불을 낸다 — 이건 눈으로
/// 지킬 수 있는 종류가 아니다. 새 말풍선을 만드는 사람이 플러터의 이 기본값을 알 이유가 없다.
bool snackBarPersists(BuildContext context) => MediaQuery.accessibleNavigationOf(context);
