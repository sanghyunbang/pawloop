import 'package:flutter/material.dart';
import 'package:heat_trip_flutter/core/mood/mood_color.dart';
import '../data/social_repository.dart';
import '../domain/emotion_card.dart';

/// "함께" — opt-in 공유된 감정 카드 피드 + 감정 리액션.
class TogetherFeed extends StatefulWidget {
  const TogetherFeed({super.key});

  @override
  State<TogetherFeed> createState() => TogetherFeedState();
}

class TogetherFeedState extends State<TogetherFeed> {
  static const _accent = Color(0xFFFB6A3E);
  final _repo = SocialRepository();

  bool _loading = true;
  String? _error;
  List<EmotionCard> _cards = const [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await _repo.feed();
      if (mounted) {
        setState(() {
          _cards = c;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '함께 피드를 불러오지 못했어요. (서버 확인)';
        });
      }
    }
  }

  Future<void> _openComments(EmotionCard card) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CommentsSheet(
        repo: _repo,
        card: card,
        onAdded: () {
          if (mounted) {
            setState(() {
              _cards = _cards
                  .map((c) => c.id == card.id
                      ? c.copyWith(commentCount: c.commentCount + 1)
                      : c)
                  .toList();
            });
          }
        },
      ),
    );
  }

  Future<void> _react(EmotionCard card, String type) async {
    try {
      final (counts, mine) = await _repo.react(cardId: card.id, type: type);
      if (!mounted) return;
      setState(() {
        _cards = _cards
            .map((c) => c.id == card.id ? c.withReactions(counts, mine) : c)
            .toList();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('리액션에 실패했어요.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFF7B6E67))),
            ),
          ],
        ),
      );
    }
    if (_cards.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '아직 공유된 감정 카드가 없어요.\n내 기록에서 "공유"로 마음을 나눠보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF7B6E67), height: 1.5),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        itemCount: _cards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _CardTile(
          card: _cards[i],
          onReact: (t) => _react(_cards[i], t),
          onComment: () => _openComments(_cards[i]),
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final EmotionCard card;
  final void Function(String type) onReact;
  final VoidCallback onComment;
  const _CardTile(
      {required this.card, required this.onReact, required this.onComment});

  String get _when {
    final s = card.createdAt;
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: moodColor(card.moodKey),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                card.handle?.trim().isNotEmpty == true ? card.handle! : '익명',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text('· ${card.moodKey}',
                  style: TextStyle(
                      color: moodColor(card.moodKey),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
              const Spacer(),
              Text(_when,
                  style:
                      const TextStyle(color: Color(0xFFB0B0B8), fontSize: 11.5)),
            ],
          ),
          if (card.placeName?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 15, color: Color(0xFF8A8A92)),
                const SizedBox(width: 4),
                Text(card.placeName!,
                    style: const TextStyle(
                        color: Color(0xFF8A8A92), fontSize: 12.5)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(card.body,
              style: const TextStyle(height: 1.5, fontSize: 14, color: Color(0xFF333333))),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final t in Reactions.all) ...[
                _ReactionChip(
                  type: t,
                  count: card.reactions[t] ?? 0,
                  active: card.myReactions.contains(t),
                  onTap: () => onReact(t),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onComment,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.mode_comment_outlined,
                      size: 16, color: Color(0xFF8A8A92)),
                  const SizedBox(width: 6),
                  Text(
                    card.commentCount > 0 ? '댓글 ${card.commentCount}개' : '댓글 달기',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A8A92)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String type;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _ReactionChip({
    required this.type,
    required this.count,
    required this.active,
    required this.onTap,
  });

  static const _accent = Color(0xFFFB6A3E);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFE7E0) : const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? _accent : const Color(0xFFE6E6EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Reactions.emoji(type), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              Reactions.label(type),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: active ? _accent : const Color(0xFF555555),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text('$count',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: active ? _accent : const Color(0xFF8A8A92))),
            ],
          ],
        ),
      ),
    );
  }
}

/// 감정 카드 댓글 시트 (목록 + 작성).
class _CommentsSheet extends StatefulWidget {
  final SocialRepository repo;
  final EmotionCard card;
  final VoidCallback onAdded;
  const _CommentsSheet(
      {required this.repo, required this.card, required this.onAdded});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const _accent = Color(0xFFFB6A3E);
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  List<CardComment> _comments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.repo.comments(widget.card.id);
      if (mounted) setState(() {
        _comments = c;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await widget.repo.addComment(cardId: widget.card.id, body: text);
      _ctrl.clear();
      widget.onAdded();
      if (mounted) {
        setState(() {
          _comments = [..._comments, c];
          _sending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('댓글 작성에 실패했어요.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E6),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: [
                  const Text('댓글',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  Text('${_comments.length}',
                      style: const TextStyle(
                          color: _accent, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? const Center(
                          child: Text('첫 댓글을 남겨보세요.',
                              style: TextStyle(color: Color(0xFF8A8A92))))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                          itemCount: _comments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (_, i) => _CommentRow(c: _comments[i]),
                        ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: '따뜻한 한마디를 남겨주세요',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: _accent),
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final CardComment c;
  const _CommentRow({required this.c});

  @override
  Widget build(BuildContext context) {
    final when = c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              c.handle?.trim().isNotEmpty == true ? c.handle! : '익명',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const Spacer(),
            Text(when,
                style:
                    const TextStyle(color: Color(0xFFB0B0B8), fontSize: 11)),
          ],
        ),
        const SizedBox(height: 3),
        Text(c.body,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF333333), height: 1.4)),
      ],
    );
  }
}
