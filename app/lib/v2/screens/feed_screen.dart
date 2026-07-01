import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import 'post_detail_screen.dart';

/// 커뮤니티 (feed) — 반려인들의 산책·동반장소·건강 이야기. 카드/리스트 토글.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String feedBoard = '전체';
  String view = 'card'; // 'card' | 'list'

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1), end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  List<PetPost> get _posts =>
      kPetPosts.where((p) => feedBoard == '전체' || p.board == feedBoard).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(children: [
                const Text('커뮤니티', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const Spacer(),
                _viewToggle(),
                const SizedBox(width: 10),
                const ProfileAvatar(),
              ]),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('우리 아이들 이야기', style: TextStyle(fontSize: 13, color: Color(0xB3463C64))),
              ),
            ),
            const SizedBox(height: 10),
            _boardFilter(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(12, 4, 12, MediaQuery.of(context).padding.bottom + 100),
                children: [
                  for (final p in _posts) ...[
                    view == 'card' ? _card(p) : _row(p),
                    SizedBox(height: view == 'card' ? 14 : 10),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _viewToggle() {
    Widget seg(String v, IconData icon) {
      final on = view == v;
      return GestureDetector(
        onTap: () => setState(() => view = v),
        child: Container(
          width: 42,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: on ? _warm : null, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 20, color: on ? Colors.white : T.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xC2FFFFFF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(children: [seg('card', Icons.view_agenda_outlined), seg('list', Icons.format_list_bulleted)]),
    );
  }

  // 보드 필터: 가로로 무한정 늘지 않도록 '전체 ▾' 버튼 + 바텀시트.
  Widget _boardFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        GestureDetector(
          onTap: _openBoardSheet,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.tune, size: 16, color: T.textSecondary),
              const SizedBox(width: 7),
              Text(feedBoard, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
              const SizedBox(width: 5),
              const Icon(Icons.expand_more, size: 16, color: T.textMuted),
            ]),
          ),
        ),
        const Spacer(),
        Text('${_posts.length}개의 글',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: T.textMuted)),
      ]),
    );
  }

  void _openBoardSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(color: Color(0xFAFCFAFF), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 16),
          const Text('게시판', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in kPetBoards)
              GestureDetector(
                onTap: () { setState(() => feedBoard = b); Navigator.pop(sheetCtx); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: feedBoard == b ? _warm : null,
                    color: feedBoard == b ? null : const Color(0xFFF1ECF7),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(b, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: feedBoard == b ? Colors.white : T.textSecondary)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  void _open(PetPost p) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)),
      );

  // 닉네임 원형 아바타 (닉 첫 글자, 따뜻한 그라데이션).
  Widget _avatar(PetPost p, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _warm),
        child: Text(p.nick.characters.first,
            style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  // 보드별 색.
  Color _boardColor(String board) {
    switch (board) {
      case '산책로 후기':
        return const Color(0xFF33BFA6);
      case '동반장소':
        return const Color(0xFFFF7E6B);
      case '건강·병원':
        return const Color(0xFF5B8DEF);
      case '자유':
        return const Color(0xFF9B7BFF);
      case '자랑':
        return const Color(0xFFEFA13C);
      default:
        return const Color(0xFFFF8F63);
    }
  }

  Widget _boardChip(String board) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _boardColor(board).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(board, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _boardColor(board))),
      );

  Widget _card(PetPost p) {
    return GestureDetector(
      onTap: () => _open(p),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(p, 40),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(p.nick, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const Spacer(),
                  Text(p.date, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                ]),
                const SizedBox(height: 5),
                Row(children: [
                  _boardChip(p.board),
                  if (p.loc != null) ...[
                    const SizedBox(width: 7),
                    const Icon(Icons.place_outlined, size: 13, color: T.textMuted),
                    const SizedBox(width: 2),
                    Text(p.loc!, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                  ],
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(p.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 5),
          Text(p.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xCC463C64))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (int i = 0; i < kPetReactions.length; i++) _reactionChip(i, p.reactions[i]),
          ]),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0x14785AA0)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.chat_bubble_outline, size: 16, color: T.textMuted),
            const SizedBox(width: 6),
            Text('댓글 ${p.commentCount}개 · 자세히 보기',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ]),
      ),
    );
  }

  Widget _reactionChip(int i, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(kPetReactions[i], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.textSecondary)),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: T.textMuted)),
        ],
      ]),
    );
  }

  Widget _row(PetPost p) {
    return GestureDetector(
      onTap: () => _open(p),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
        child: Row(children: [
          _avatar(p, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 5),
              Row(children: [
                _boardChip(p.board),
                if (p.loc != null) ...[
                  const SizedBox(width: 7),
                  const Icon(Icons.place_outlined, size: 12, color: T.textMuted),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(p.loc!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(Icons.chat_bubble_outline, size: 13, color: T.textMuted),
                const SizedBox(width: 3),
                Text('${p.commentCount}', style: const TextStyle(fontSize: 12, color: T.textMuted)),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
        ]),
      ),
    );
  }
}
