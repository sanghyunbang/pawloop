// 글 목록의 동작 셋 — 반응 · 저장 · 두 번 탭 하트. 피드에서 꺼낸 것, 이슈 #729.
//
// 피드(`feed_screen.dart`)와 장소의 글(`place_posts_screen.dart`)이 **같은 카드**(`PostCard`)를
// 그리므로 카드가 부르는 동작도 같아야 한다. 규칙은 피드가 정한 그대로다:
//
//   - **낙관적 갱신을 안 한다.** 서버가 멱등한 응답으로 집계를 돌려주므로 그것을 그대로 그린다.
//   - 게스트(`reactions.mine == null`)는 "안 누른 상태" 가 아니다 — 로그인 안내만 한다.
//   - 보내는 중에는 같은 글을 또 안 보낸다(`sending*`).
//   - 두 번 탭은 **켜기만** 한다. 하트는 바로 튀고(손가락에 대한 대답), 집계는 응답이 와야 바뀐다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart';

/// 글 목록을 든 화면이 섞어 쓴다. [posts] 를 갈아 끼우는 것은 화면 몫이다 — 여기서는 `setState`
/// 로 목록의 한 항목만 바꾼다.
mixin PostListActions<T extends StatefulWidget> on State<T> {
  CommunityRepository get postsRepo;
  List<CommunityPost> get posts;
  set posts(List<CommunityPost> value);

  final Set<int> sendingReaction = {};
  final Set<int> sendingBookmark = {};

  /// 글 id → 두 번 탭 횟수. 오를 때마다 하트가 한 번 튄다(`LikeBurst`).
  final Map<int, int> bursts = {};

  int burstOf(CommunityPost post) => bursts[post.id] ?? 0;

  void toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 반응을 누르거나 뗀다. [addOnly] 면 이미 누른 것을 떼지 않는다(두 번 탭).
  Future<void> toggleReaction(CommunityPost post, CommunityReaction reaction, {bool addOnly = false}) async {
    if (post.reactions.mine == null) {
      toast('로그인하면 반응을 남길 수 있어요');
      return;
    }
    if (sendingReaction.contains(post.id)) return;
    final mine = post.reactions.isMine(reaction);
    if (mine && addOnly) return;
    setState(() => sendingReaction.add(post.id));
    try {
      final summary =
          mine ? await postsRepo.removeReaction(post.id, reaction) : await postsRepo.addReaction(post.id, reaction);
      if (!mounted) return;
      setState(() {
        posts = [for (final p in posts) p.id == post.id ? p.copyWith(reactions: summary) : p];
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      toast(failure.message);
    } finally {
      if (mounted) setState(() => sendingReaction.remove(post.id));
    }
  }

  /// 사진 두 번 탭 = 귀여워요 (Instagram, #451 4번).
  void doubleTapLike(CommunityPost post) {
    if (post.reactions.mine == null) {
      toast('로그인하면 반응을 남길 수 있어요');
      return;
    }
    setState(() => bursts[post.id] = (bursts[post.id] ?? 0) + 1);
    toggleReaction(post, CommunityReaction.cute, addOnly: true);
  }

  /// 저장을 켜고 끈다 — 응답의 상태를 그린다. 실패했을 때 켜진 채 남는 거짓은 안 만든다.
  Future<void> toggleBookmark(CommunityPost post) async {
    if (post.reactions.mine == null) {
      toast('로그인하면 글을 저장할 수 있어요');
      return;
    }
    if (sendingBookmark.contains(post.id)) return;
    setState(() => sendingBookmark.add(post.id));
    try {
      final on = post.bookmarked ? await postsRepo.unbookmark(post.id) : await postsRepo.bookmark(post.id);
      if (!mounted) return;
      setState(() {
        posts = [for (final p in posts) p.id == post.id ? p.copyWith(bookmarked: on) : p];
      });
      toast(on ? '저장했어요 — 내 정보 > 저장한 글' : '저장을 뺐어요');
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      toast(failure.message);
    } finally {
      if (mounted) setState(() => sendingBookmark.remove(post.id));
    }
  }
}
