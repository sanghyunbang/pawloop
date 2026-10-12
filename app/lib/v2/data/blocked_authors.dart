// lib/v2/data/blocked_authors.dart
//
// 이 세션에서 차단한 사람 — 애플 App Review Guideline 1.2.
//
// ## 왜 필요한가
//
// 1.2 는 "차단한 사람의 콘텐츠는 피드에서 **즉시** 사라져야 한다" 고 요구한다. 서버는 차단한 사람의
// 글·댓글을 목록에서 빼고, 옛 서버는 `hiddenByBlock` 을 붙여 보낸다 — 그런데 둘 다 **다음에 불러올
// 때** 의 이야기다. 차단을 누른 순간 이미 그려져 있는 목록(피드 · 장소의 글 · 저장한 글 · 아이
// 사진첩 · 홈의 이웃 사진)에는 그 사람의 글이 그대로 남는다.
//
// 다시 불러오면 지워지지만, 그러면 '더 보기' 로 쌓은 장과 스크롤이 날아간다 — `kCommunityRev` 가
// "바뀌었을 때만" 다시 읽는 이유와 같다(#548). 그래서 차단이 성공하면 그 사람의 id 를 여기 적고,
// 목록들이 이 값을 듣고 **이미 그린 것에서** 뺀다. 서버를 다시 부르지 않는다.
//
// ## 이 파일은 id 만 든다
//
// 무엇을 숨기는지의 규칙은 `community_repository.dart` 의 `CommunityPost.hiddenForViewer` 다 — 서버가
// 붙인 표시와 여기 적힌 id 를 함께 본다. 이 파일이 커뮤니티 모델을 모르는 것은 일부러다: 세션을 지우는
// `session_traces.dart` 가 여기를 부르는데, 거기까지 커뮤니티 저장소를 끌고 가지 않으려고.
//
// ## 한계 — 그대로 적는다
//
//  - **메모리에만 있다.** 앱을 다시 켜면 비고, 그때부터는 서버가 뺀다. 정본은 서버의 `user_block` 이다.
//  - **채팅의 "가리기" 는 여기 안 적힌다.** 채팅 화면은 자기 저장소로 같은 `POST /api/blocks` 를
//    부른다. 채팅에서 가린 사람의 글은 커뮤니티 목록을 다음에 불러올 때 빠진다.
//  - **채팅의 "가리기 해제" 도 여기를 안 지운다.** 같은 세션 안에서 커뮤니티에서 차단하고 채팅에서
//    풀면, 앱을 다시 켤 때까지 커뮤니티에서는 계속 안 보인다.
//  - **로그아웃 · 탈퇴 · 세션 만료에 비운다**(`clearSessionTraces`). 다음 사람에게 앞사람의 차단이
//    적용되면 안 된다.
library;

import 'package:flutter/foundation.dart';

class BlockedAuthors {
  BlockedAuthors._();

  static final ValueNotifier<Set<int>> _ids = ValueNotifier<Set<int>>(const <int>{});

  /// 차단한 사람들. 목록 화면들이 듣고, 바뀌면 다시 그린다.
  static ValueListenable<Set<int>> get ids => _ids;

  /// 이 세션에서 이 사람을 차단했는가.
  static bool contains(int userId) => _ids.value.contains(userId);

  /// 차단이 **성공한 뒤에** 부른다. 실패했는데 적으면 화면에서는 사라졌는데 서버는 모르는 상태가 된다.
  ///
  /// 탈퇴한 사람(`userId` 0)은 적지 않는다 — 차단 버튼이 안 뜨는 사람이고, 0 을 적으면 탈퇴한 모든
  /// 사람의 글이 한꺼번에 사라진다.
  static void add(int userId) {
    if (userId <= 0 || _ids.value.contains(userId)) return;
    _ids.value = Set<int>.unmodifiable({..._ids.value, userId});
  }

  /// 세션이 끝났다. `clearSessionTraces` 가 부른다.
  static void clear() {
    if (_ids.value.isEmpty) return;
    _ids.value = const <int>{};
  }
}
