import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';

/// 글 상세 (postDetail) — 반려 커뮤니티 글 1건 + 반응 + 댓글 스레드.
class PostDetailScreen extends StatefulWidget {
  final PetPost post;
  const PostDetailScreen({super.key, required this.post});
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

/// 화면 로컬 더미 댓글 모델. (추후 백엔드 연동)
class _Comment {
  final String nick;
  final String text;
  const _Comment(this.nick, this.text);
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _ctrl = TextEditingController();

  // 반응 선택 상태(로컬 토글). kPetReactions와 동일 순서.
  late List<int> _reactions = List.of(widget.post.reactions);
  final Set<int> _picked = {};

  // 더미 댓글 시드.
  late List<_Comment> _cmts = const [
    _Comment('초코맘', '와 코스 정보 감사해요! 이번 주말에 저희 아이랑 가봐야겠어요.'),
    _Comment('두부아빠', '배변봉투통 위치 꿀팁이네요. 중형견도 편하게 걸을 만한가요?'),
    _Comment('산책러', '아침 시간대 정말 한적해서 좋더라고요. 물그릇도 챙겨가시면 좋아요.'),
  ].toList();

  static const _avatarColors = [
    [Color(0xFF8FB6FF), Color(0xFF5B79F5)],
    [Color(0xFFBBA0FF), Color(0xFF7E68F0)],
    [Color(0xFF7FE6CC), Color(0xFF33BFA6)],
    [Color(0xFFFF9FCF), Color(0xFFCE7DF5)],
  ];

  static const _warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _cmts = [..._cmts, _Comment('나', t)];
      _ctrl.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _toggleReaction(int i) {
    setState(() {
      if (_picked.contains(i)) {
        _picked.remove(i);
        _reactions[i] = (_reactions[i] - 1).clamp(0, 1 << 30);
      } else {
        _picked.add(i);
        _reactions[i] = _reactions[i] + 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            // 헤더 (뒤로가기)
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
                const Text('산책 이야기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                children: [
                  _postCard(p),
                  const SizedBox(height: 14),
                  _reactionRow(),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Icon(Icons.forum_outlined, size: 17, color: Color(0xFFFF8F63)),
                    const SizedBox(width: 7),
                    Text('댓글 ${_cmts.length}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  ]),
                  const SizedBox(height: 12),
                  for (final c in _cmts) ...[_commentCard(c), const SizedBox(height: 10)],
                  if (_cmts.isEmpty)
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

  Widget _postCard(PetPost p) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 작성자
        Row(children: [
          _avatar(p.nick, 44),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nick, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 3),
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
          Text(p.date, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
        const SizedBox(height: 14),
        // 제목
        Text(p.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.3, color: T.textPrimary)),
        const SizedBox(height: 8),
        // 본문
        Text(p.body, style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xCC463C64))),
      ]),
    );
  }

  Widget _boardChip(String board) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x1AFF8F63),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pets, size: 11, color: Color(0xFFE07A4E)),
        const SizedBox(width: 4),
        Text(board, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFE07A4E))),
      ]),
    );
  }

  // 반응 버튼 줄 (kPetReactions).
  Widget _reactionRow() {
    const icons = [Icons.thumb_up_alt_outlined, Icons.favorite_outline, Icons.emoji_emotions_outlined];
    return Row(children: [
      for (var i = 0; i < kPetReactions.length; i++) ...[
        if (i > 0) const SizedBox(width: 9),
        Expanded(child: _reactionBtn(i, icons[i % icons.length])),
      ],
    ]);
  }

  Widget _reactionBtn(int i, IconData icon) {
    final on = _picked.contains(i);
    return GestureDetector(
      onTap: () => _toggleReaction(i),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: on ? _warm : null,
          color: on ? null : const Color(0xC9FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Colors.transparent : const Color(0x1F8C7BFF)),
          boxShadow: on
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 6))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: on ? Colors.white : T.textSecondary),
          const SizedBox(width: 6),
          Text(kPetReactions[i],
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
          const SizedBox(width: 5),
          Text('${_reactions[i]}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : T.textMuted)),
        ]),
      ),
    );
  }

  Widget _commentCard(_Comment c) {
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
            Text(c.text, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xCC463C64))),
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
                hintText: '우리 아이 이야기를 나눠보세요',
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
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)]),
            ),
            child: const Icon(Icons.send, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
