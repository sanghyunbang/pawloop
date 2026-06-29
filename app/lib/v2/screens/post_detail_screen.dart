import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/community.dart';
import '../widgets/aurora.dart';

/// 장소일기 (postDetail) — 글 1건 + 스레드 댓글.
class PostDetailScreen extends StatefulWidget {
  final CommunityPost post;
  const PostDetailScreen({super.key, required this.post});
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _ctrl = TextEditingController();
  late List<PostComment> cmts = List.of(widget.post.cmts);

  static const _avatarColors = [
    [Color(0xFF8FB6FF), Color(0xFF5B79F5)],
    [Color(0xFFBBA0FF), Color(0xFF7E68F0)],
    [Color(0xFF7FE6CC), Color(0xFF33BFA6)],
    [Color(0xFFFF9FCF), Color(0xFFCE7DF5)],
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      cmts = [...cmts, PostComment('나', t)];
      _ctrl.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xB3FFFFFF),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0x80FFFFFF)),
                    ),
                    child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('장소일기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                children: [
                  _postCard(p),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Icon(Icons.forum_outlined, size: 17, color: Color(0xFF8E7BFF)),
                    const SizedBox(width: 7),
                    Text('댓글 ${cmts.length}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  ]),
                  const SizedBox(height: 12),
                  for (final c in cmts) ...[_commentCard(c), const SizedBox(height: 10)],
                  if (cmts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('첫 댓글을 남겨보세요.', style: TextStyle(color: T.textMuted))),
                    ),
                ],
              ),
            ),
            _inputBar(),
          ]),
        ),
      ),
    );
  }

  Widget _avatar(String nick, double size) {
    final c = _avatarColors[nick.hashCode.abs() % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
      ),
      child: Text(nick.characters.first, style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }

  Widget _postCard(CommunityPost p) {
    final f = kEmotions[p.from], t = kEmotions[p.to];
    Widget dot(Emotion e) => Container(
          width: 24, height: 24, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
          child: Text(e.emoji, style: const TextStyle(fontSize: 12)));
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: t.grad),
            child: Text(p.nick.characters.first, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nick, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
              if (p.loc != null) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 13, color: T.textMuted),
                  const SizedBox(width: 2),
                  Text(p.loc!, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                ]),
              ],
            ]),
          ),
          const Text('2026.06.27', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          dot(f),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 14, color: T.textMuted),
          const SizedBox(width: 6),
          dot(t),
          const SizedBox(width: 8),
          Text('${f.label} → ${t.label}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
        ]),
        const SizedBox(height: 12),
        Text(p.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 6),
        Text(p.story, style: const TextStyle(fontSize: 14, height: 1.55, color: Color(0xCC463C64))),
      ]),
    );
  }

  Widget _commentCard(PostComment c) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatar(c.nick, 34),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.nick, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(c.text, style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xCC463C64))),
          ]),
        ),
      ]),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xF0FFFFFF),
        border: Border(top: BorderSide(color: Color(0x22785AA0))),
      ),
      child: Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1ECF7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 14, color: T.textPrimary),
              decoration: const InputDecoration(
                hintText: '따뜻한 한마디를 남겨보세요',
                hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9E7D), Color(0xFFFF8FB0)]),
            ),
            child: const Icon(Icons.send, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
