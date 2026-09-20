// 커뮤니티 글 카드 — 피드(`feed_screen.dart`)에서 꺼낸 것, 이슈 #729.
//
// 피드 안에 `_card` 로 살던 것을 그대로 옮겼다. 장소 페이지('이 장소의 글')가 **같은 카드**를
// 써야 해서다 — 두 벌이면 한쪽만 고쳐지고, 그게 "장소 화면은 왜 다르지" 가 된다.
//
// 이 위젯은 **상태를 안 든다.** 반응 · 저장 · 두 번 탭 하트는 부르는 쪽(`PostListActions`)이
// 하고, 여기는 그리고 콜백만 부른다. 키(`bookmark-`, `reaction-`, `post-dog-`, `blocked-post-`,
// `post-comment-count-`)는 피드 검사들이 보던 그대로다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart';
import '../domain/date_label.dart';
import '../theme/app_tokens.dart';
import 'aurora.dart';
import 'like_burst.dart';
import 'post_course_card.dart';
import 'post_media_strip.dart';

/// 글 하나 — 사진(있으면 먼저) · 작성자 줄 · 게시판/아이/장소 · 제목 · 본문 두 줄 · 코스 · 액션 한 줄.
class PostCard extends StatelessWidget {
  final CommunityPost post;

  /// 큰 배율에서 반응 이름 · 동네를 접는다(#433). 피드가 `MediaQuery` 로 정한다.
  final bool folded;

  /// 두 번 탭 하트의 트리거 — 오를 때마다 한 번 튄다(`LikeBurst`).
  final int burst;

  final VoidCallback onOpen;
  final VoidCallback onDoubleTapLike;
  final void Function(CommunityReaction reaction) onToggleReaction;
  final VoidCallback onToggleBookmark;

  const PostCard({
    super.key,
    required this.post,
    required this.onOpen,
    required this.onDoubleTapLike,
    required this.onToggleReaction,
    required this.onToggleBookmark,
    this.folded = false,
    this.burst = 0,
  });

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  @override
  Widget build(BuildContext context) {
    if (post.hiddenByBlock) return blockedPostCard(post, onOpen: onOpen);
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 사진·영상이 있으면 **사진이 먼저**다(#451). 목록에서는 **정사각까지만** — 세로 사진
          // 하나가 화면 절반을 먹으면 한 화면에 글이 하나뿐이었다(#465, Reddit 의 카드). 여러 장은
          // 캐러셀(Instagram). 원본은 전체 보기에서.
          if (post.media.isNotEmpty) ...[
            Stack(children: [
              PostMediaStrip(media: post.media, minAspect: 1, onDoubleTap: onDoubleTapLike),
              // 두 번 탭 하트 — 사진 위에서 튄다.
              Positioned.fill(child: LikeBurst(trigger: burst)),
            ]),
            const SizedBox(height: 10),
          ],
          // 작성자 줄 — 아바타 28(예전 40) · 닉네임 · 동네 · 날짜. 닉네임은 Flexible 이라 좁으면
          // 말줄임으로 끝나고 날짜는 오른쪽 끝에 그대로다(#433). 동네는 1.3배부터 접는다.
          // 게시판 칩은 다음 줄에 장소와 함께 — 2.0배·320dp 에서는 칩과 날짜가 한 줄에 못 들어간다.
          Row(children: [
            postAvatar(post, 28),
            const SizedBox(width: 8),
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(post.author.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                ),
                // 글쓴이의 동네 — **구까지만** (#342). 안 골랐으면 자리가 없다.
                if (post.authorDistrict != null && !folded) ...[
                  const SizedBox(width: 6),
                  Text(post.authorDistrict!,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0B7A75))),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Text(dateLabel(post.createdAt), style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            boardChip(post.board),
            // 찍힌 아이 (#451 5번) — 사진(없으면 발바닥) + 이름. 아이 사진첩으로 모이는 표식이다.
            if (post.dog case final dog?) ...[
              const SizedBox(width: 7),
              _dogTag(dog),
            ],
            if (post.loc != null) ...[
              const SizedBox(width: 7),
              const Icon(Icons.place_outlined, size: 12, color: T.textMuted),
              const SizedBox(width: 2),
              // Flexible 이 없으면 긴 장소 이름이 Row 를 넘쳐 노란 줄무늬가 뜬다.
              Flexible(
                child: Text(post.loc!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Text(post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 3),
          // 본문은 두 줄까지(#465) — 나머지는 상세에서.
          Text(post.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary)),
          // 붙은 코스가 있으면 그림 한 장 (#339). 비공개로 되돌렸거나 지웠으면 안 온다.
          if (post.course != null) ...[
            const SizedBox(height: 10),
            PostCourseCard(course: post.course!),
          ],
          const SizedBox(height: 10),
          // 액션 **한 줄** — 왼쪽은 반응(아이콘 · 이름 · 수), 오른쪽 끝은 댓글 수와 화살표(Reddit 의
          // 액션 바, #465). 반응은 가로 스크롤 줄이라 어떤 배율에서도 안 넘치고(#433 의 방식), 1.3배부터
          // 이름을 접어 아이콘·수만 남긴다. 화살표는 오른쪽 끝에 그대로다 — "더 볼 수 있다" 는 신호(#432).
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final reaction in CommunityReaction.values) ...[
                    _reactionInline(reaction),
                    const SizedBox(width: 14),
                  ],
                ]),
              ),
            ),
            const SizedBox(width: 6),
            // 저장 — "내 사진첩" (#451 4번). 누르면 켜고 끈다, 카드는 안 열린다. 세지 않는다.
            GestureDetector(
              key: Key('bookmark-${post.id}'),
              onTap: onToggleBookmark,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Icon(post.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 18, color: post.bookmarked ? T.accent : T.textMuted),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chat_bubble_outline, size: 16, color: T.textMuted),
            const SizedBox(width: 4),
            Text('${post.commentCount}',
                key: Key('post-comment-count-${post.id}'),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ]),
      ),
    );
  }

  /// 반응 하나 — 아이콘 · 이름 · 수. **누르면 켜고 끈다** — 카드를 열지 않는다(안쪽 탭이 이긴다).
  /// 내가 누른 것은 채운 아이콘에 강조색이다.
  Widget _reactionInline(CommunityReaction reaction) {
    final summary = post.reactions;
    final count = summary.countOf(reaction);
    final mine = summary.isMine(reaction);
    final color = mine ? T.accent : T.textMuted;
    return GestureDetector(
      key: Key('reaction-${reaction.wire}-${post.id}'),
      onTap: () => onToggleReaction(reaction),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(reactionIcon(reaction, mine), size: 16, color: color),
          if (!folded) ...[
            const SizedBox(width: 4),
            Text(reaction.label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: mine ? T.accent : T.textSecondary)),
          ],
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ],
        ]),
      ),
    );
  }

  Widget _dogTag(PostDog dog) => Container(
        key: Key('post-dog-${dog.id}'),
        padding: const EdgeInsets.fromLTRB(3, 2, 8, 2),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.cardBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipOval(
            child: SizedBox(
              width: 16,
              height: 16,
              child: dog.avatarUrl == null
                  ? Image.asset('assets/emoji/paw.png', width: 16, height: 16)
                  : Image.network(dog.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset('assets/emoji/paw.png', width: 16, height: 16)),
            ),
          ),
          const SizedBox(width: 4),
          Text(dog.name,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: T.textSecondary)),
        ]),
      );

  /// 닉네임 원형 아바타 (닉 첫 글자, 따뜻한 그라데이션). 피드의 한 줄 카드도 쓴다.
  static Widget postAvatar(CommunityPost post, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _warm),
        child: Text(_initial(post.author.nickname),
            style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  /// 아바타 글자. 닉네임이 빈 문자열이면 `characters.first` 가 던진다 — 서버가 탈퇴한 사람에게
  /// '알 수 없음' 을 주므로 빈 값이 올 일은 없지만, 카드 하나 때문에 목록이 죽는 것은 막는다.
  static String _initial(String nickname) => nickname.isEmpty ? '?' : nickname.characters.first;

  /// 보드별 색. 키가 아니라 enum 으로 가른다 — 문자열로 가르면 서버가 값을 바꿀 때 `default` 로
  /// 조용히 떨어진다.
  static Color boardColor(CommunityBoard? board) => switch (board) {
        CommunityBoard.walkReview => const Color(0xFF33BFA6),
        CommunityBoard.petPlace => const Color(0xFFFF7E6B),
        CommunityBoard.health => const Color(0xFF5B8DEF),
        CommunityBoard.free => T.accent,
        CommunityBoard.brag => const Color(0xFFEFA13C),
        null => T.warmMid,
      };

  static Widget boardChip(CommunityBoard? board) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: boardColor(board).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(board?.label ?? '기타',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: boardColor(board))),
      );

  static IconData reactionIcon(CommunityReaction reaction, bool mine) => switch (reaction) {
        CommunityReaction.help => mine ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
        CommunityReaction.cute => mine ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        CommunityReaction.empathy => mine ? Icons.handshake_rounded : Icons.handshake_outlined,
      };
}

/// 가린 사람의 글 — 목록에서는 **글도 사진도 안 그린다**.
///
/// 서버는 읽는 사람 기준으로 `hiddenByBlock` 을 계산해 붙여 보내는데, 목록이 그 값을 안 보던
/// 시절이 있었다(2026-09-18 사장님 실기기 신고). **사진을 빼는 것이 핵심이다** — 글자만 접고
/// 사진을 남기면 가장 불쾌할 수 있는 것이 그대로 남는다. 제목도 뺀다. 여기서는 펴지 않는다 —
/// 목록의 탭은 글을 여는 동작이라 "눌러서 보기" 와 부딪친다. 펴는 것은 상세에 있다.
Widget blockedPostCard(CommunityPost post, {required VoidCallback onOpen}) => GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
        child: Row(children: [
          const Icon(Icons.visibility_off_rounded, size: 18, color: T.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text('가린 사람의 글입니다 · 눌러서 보기',
                key: Key('blocked-post-${post.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: T.textMuted)),
          ),
        ]),
      ),
    );
