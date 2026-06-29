import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/community.dart';
import '../widgets/aurora.dart';
import 'post_detail_screen.dart';

/// 커뮤니티 (feed) — 비슷한 마음의 장소일기. 카드/리스트 토글.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String feedCat = '전체';
  String view = 'card'; // 'card' | 'list'

  static const _pink = LinearGradient(colors: [Color(0xFFFF8FB0), Color(0xFFFF9FCF)]);

  List<CommunityPost> get _posts =>
      kCommunityPosts.where((p) => feedCat == '전체' || p.cats.contains(feedCat)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('커뮤니티', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const Spacer(),
                  _viewToggle(),
                ]),
                const SizedBox(height: 4),
                const Text('비슷한 마음을 가진 사람들과 이야기를 나눠요.',
                    style: TextStyle(fontSize: 13, color: Color(0xC2463C64))),
                const SizedBox(height: 14),
                _catFilters(),
                const SizedBox(height: 8),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                children: [
                  for (final p in _posts) ...[
                    view == 'card' ? _card(p) : _row(p),
                    SizedBox(height: view == 'card' ? 14 : 10),
                  ],
                ],
              ),
            ),
            _bottomNav(),
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
          decoration: BoxDecoration(gradient: on ? _pink : null, borderRadius: BorderRadius.circular(11)),
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

  Widget _catFilters() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in kCommunities)
        GestureDetector(
          onTap: () => setState(() => feedCat = c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: feedCat == c ? _pink : null,
              color: feedCat == c ? null : const Color(0xC2FFFFFF),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: feedCat == c ? Colors.transparent : const Color(0x66FFFFFF)),
            ),
            child: Text(c,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: feedCat == c ? Colors.white : T.textSecondary)),
          ),
        ),
    ]);
  }

  void _open(CommunityPost p) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)),
      );

  Widget _avatar(CommunityPost p, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: kEmotions[p.to].grad),
        child: Text(p.nick.characters.first,
            style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  Widget _catChip(String c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: catColor(c).withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(c, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: catColor(c))),
      );

  Widget _miniDot(Emotion e) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
        child: Text(e.emoji, style: const TextStyle(fontSize: 12)),
      );

  Widget _shift(CommunityPost p, {double dot = 24}) {
    final f = kEmotions[p.from], t = kEmotions[p.to];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _miniDot(f),
      const SizedBox(width: 6),
      const Icon(Icons.arrow_forward, size: 14, color: T.textMuted),
      const SizedBox(width: 6),
      _miniDot(t),
      const SizedBox(width: 8),
      Text('${f.label} → ${t.label}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
    ]);
  }

  Widget _card(CommunityPost p) {
    return GlassCard(
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
                const Text('2026.06.27', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
              ]),
              const SizedBox(height: 5),
              Row(children: [
                _catChip(p.community),
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
        _shift(p),
        const SizedBox(height: 11),
        Text(p.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 5),
        Text(p.story, style: const TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xCC463C64))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (int i = 0; i < 3; i++) _reactionChip(i, p.base[i]),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: const Color(0x14785AA0)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _open(p),
          child: Row(children: [
            const Icon(Icons.chat_bubble_outline, size: 16, color: T.textMuted),
            const SizedBox(width: 6),
            Text('댓글 ${p.commentCount}개 · 자세히 보기',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ),
      ]),
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
        Text(kReactionEmojis[i], style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(kReactionLabels[i], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.textSecondary)),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: T.textMuted)),
        ],
      ]),
    );
  }

  Widget _row(CommunityPost p) {
    final f = kEmotions[p.from], t = kEmotions[p.to];
    return GestureDetector(
      onTap: () => _open(p),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
        child: Row(children: [
          _miniDot(f),
          const SizedBox(width: 5),
          const Icon(Icons.arrow_forward, size: 13, color: T.textMuted),
          const SizedBox(width: 5),
          _miniDot(t),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 5),
              Row(children: [
                _catChip(p.community),
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

  Widget _bottomNav() {
    const accent = Color(0xFF8E7BFF);
    Widget item(IconData icon, String label, bool active) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 23, color: active ? accent : T.textMuted),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w800 : FontWeight.w500, color: active ? accent : T.textMuted)),
          ]),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 8 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xE6FFFFFF),
        border: Border(top: BorderSide(color: Color(0x22785AA0))),
      ),
      child: Row(children: [
        item(Icons.wb_sunny_outlined, '오늘', false),
        item(Icons.explore_outlined, '탐색', false),
        Expanded(
          child: Center(
            child: Container(
              width: 48, height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9FCF), Color(0xFFFF8FA8)]),
                boxShadow: [BoxShadow(color: Color(0x4DFF8FA8), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 24),
            ),
          ),
        ),
        item(Icons.chat_bubble_outline, '커뮤니티', true),
        item(Icons.show_chart, '흐름', false),
      ]),
    );
  }
}
