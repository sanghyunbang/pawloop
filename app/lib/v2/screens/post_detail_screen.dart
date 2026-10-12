import 'package:flutter/material.dart';
import '../data/auth_state.dart';
import '../data/blocked_authors.dart';
import '../data/community_repository.dart';
import '../widgets/post_course_card.dart';
import '../widgets/post_media_strip.dart';
import '../domain/date_label.dart';
import '../widgets/message_actions_sheet.dart';
import 'login_screen.dart';
import 'post_write_screen.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 차단 확인 창의 본문 — 무엇이 일어나는지 셋(사라짐 · 운영자 알림 · 상대 비고지). 검사가 붙든다.
const String blockConfirmMessage =
    '이 사람의 글과 댓글이 내 화면에서 사라지고, 운영자에게 알림이 갑니다. 상대에게는 알리지 않습니다.';

/// 차단한 사람의 글을 직접 열었을 때 그 자리에 남는 한 줄.
const String hiddenPostMessage = '차단한 사용자의 글이에요';

/// 글 상세 (postDetail) — 커뮤니티 글 1건 + 반응 + 댓글 스레드.
///
/// **서버에서 온다** (이슈 #171). 2026-09 이전에는 반응이 화면 로컬 토글이었고 댓글은
/// `_cmts` 리스트에만 쌓였다 — 화면을 나가면 사라졌고, 그 사실을 이 파일이 스스로
/// "화면 로컬 더미 댓글 모델. (추후 백엔드 연동)" 이라고 적고 있었다.
///
/// ## 게스트인지 서버에게 묻는다
///
/// `post.reactions.mine` 이 `null` 이면 게스트다. `AuthState` 를 안 보는 이유는, 그
/// 값과 이 응답이 어긋날 수 있어서다 — 토큰이 만료된 채 읽기만 하면 앱은 자기가
/// 로그인했다고 믿지만 서버는 게스트로 대접한다. 화면은 **서버가 방금 말한 것**을
/// 따른다.
///
/// ## 차단한 사람의 글·댓글 — 애플 지침 1.2
///
/// 남의 글과 댓글에는 신고와 **따로** "차단" 이 있다(신고 시트 안의 체크칸도 그대로 있다). 차단하면
/// 그 사람의 댓글은 이 화면에서 바로 빠지고, 그 사람의 글이면 내용 대신 "차단한 사용자의 글이에요" 만
/// 남는다 — 접어 두고 "눌러서 보기" 로 펴던 것을 1.2 가 "즉시 사라져야 한다" 로 막았다. 목록들도 같은
/// 순간 그 사람의 글을 뺀다([BlockedAuthors]).
class PostDetailScreen extends StatefulWidget {
  final CommunityPost post;

  /// 목록 화면이 자기 리포지토리를 넘긴다. 테스트는 가짜 서버를 넣는다.
  final CommunityRepository? repository;

  const PostDetailScreen({super.key, required this.post, this.repository});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _ctrl = TextEditingController();

  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();

  late CommunityPost _post = widget.post;

  List<CommunityComment> _comments = const [];
  bool _loadingComments = true;
  bool _loadingMoreComments = false;
  String? _commentCursor;
  bool _hasMoreComments = false;
  CommunityFailure? _commentsFailure;

  /// 이 화면에서 <b>서버의 값을 바꿨는가.</b> 목록이 이 값으로 새로고침 여부를 정한다 —
  /// 열어 보기만 하고 나온 것까지 새로 부르면 '더 보기' 로 쌓아 둔 장이 다 날아간다.
  bool _changed = false;

  /// 반응·댓글을 보내는 중. 두 번 눌러 두 줄이 되는 것을 막는다.
  bool _sending = false;

  static const _avatarColors = [
    [Color(0xFF8FB6FF), Color(0xFF5B79F5)],
    [Color(0xFFBBA0FF), Color(0xFF7E68F0)],
    [Color(0xFF7FE6CC), Color(0xFF33BFA6)],
    [Color(0xFFFF9FCF), Color(0xFFCE7DF5)],
  ];

  static const _warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [T.warmStart, T.warmEnd],
  );

  /// 서버가 방금 이 요청을 게스트로 봤는가.
  bool get _isGuest => _post.reactions.mine == null;

  @override
  void initState() {
    super.initState();
    // 이 화면에서든 다른 곳에서든 차단이 일어나면 다시 그린다 — 글이 가려지고 댓글이 빠진다.
    BlockedAuthors.ids.addListener(_onBlocksChanged);
    _refreshPost();
    _loadComments();
  }

  void _onBlocksChanged() {
    if (mounted) setState(() {});
  }

  /// 글을 다시 읽는다. <b>목록이 넘긴 것은 그때의 세션으로 읽은 값이다.</b>
  ///
  /// 목록을 게스트로 훑다가 글쓰기에서 로그인하고 돌아오면, 목록의 글들은 여전히
  /// `mine == null` 인 게스트 응답이다. 그 값을 그대로 들고 상세로 들어가면
  /// 로그인한 사람에게 "로그인하면 …" 안내가 뜨고 반응도 못 누른다.
  ///
  /// 실패하면 넘겨받은 값 그대로 그린다 — 화면이 안 뜨는 것보다 낫고, 댓글 쪽이
  /// 이미 실패를 말한다.
  Future<void> _refreshPost() async {
    try {
      final fresh = await _repo.post(widget.post.id);
      if (!mounted) return;
      setState(() => _post = fresh);
    } on CommunityFailure {
      // 넘겨받은 값으로 계속한다.
    }
  }

  @override
  void dispose() {
    BlockedAuthors.ids.removeListener(_onBlocksChanged);
    _ctrl.dispose();
    // 나가면서 **한 번** 알린다(#548). 바뀔 때마다 알리면 반응을 세 번 누른 동안 목록이 세 번
    // 다시 읽는다. 다음 프레임으로 미루는 것은, 지금 이 순간이 위젯을 걷어내는 중이라
    // 듣는 쪽의 `setState` 가 그 안에서 터지기 때문이다.
    if (_changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyCommunityChanged());
    }
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentsFailure = null;
    });
    try {
      final page = await _repo.comments(_post.id);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _commentCursor = page.nextCursor;
        _hasMoreComments = page.hasMore;
        _loadingComments = false;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _commentsFailure = failure;
        _loadingComments = false;
      });
    }
  }

  /// 댓글 다음 장.
  ///
  /// 이게 없던 동안 <b>21번째 댓글부터는 볼 방법이 아예 없었다.</b> 게다가 목록 카드가
  /// 서버의 전체 댓글 수를 보여 주므로, "댓글 34개" 를 보고 들어와 20개만 있는 화면을
  /// 만나게 된다 — 사용자는 댓글이 지워졌다고 읽는다.
  Future<void> _loadMoreComments() async {
    final cursor = _commentCursor;
    if (cursor == null || _loadingMoreComments) return;
    setState(() => _loadingMoreComments = true);
    try {
      final page = await _repo.comments(_post.id, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.items];
        _commentCursor = page.nextCursor;
        _hasMoreComments = page.hasMore;
        _loadingMoreComments = false;
      });
    } on CommunityFailure {
      // 다음 장을 못 받은 것은 앞 장까지 지울 이유가 아니다.
      if (!mounted) return;
      setState(() => _loadingMoreComments = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _repo.addComment(_post.id, text);
      if (!mounted) return;
      setState(() {
        // 목록의 끝에 붙인다 — 댓글은 오래된 것부터라 새 것이 마지막이다.
        _comments = [..._comments, comment];
        _post = _post.copyWith(commentCount: _post.commentCount + 1);
        _ctrl.clear();
        _sending = false;
        _changed = true;
      });
      FocusScope.of(context).unfocus();
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 반응을 누르거나 뗀다.
  ///
  /// **낙관적 갱신을 안 한다.** 서버가 멱등한 응답으로 집계를 돌려주므로 그것을
  /// 그대로 그린다 — 로컬에서 세면 남이 같은 시간에 누른 것이 안 보이고, 실패했을 때
  /// 되돌릴 자리가 생긴다.
  Future<void> _toggleReaction(CommunityReaction reaction) async {
    if (_sending) return;
    if (_isGuest) {
      if (!await _askLogin('반응을 남길 수 있어요')) return;
    }
    setState(() => _sending = true);
    try {
      final summary = _post.reactions.isMine(reaction)
          ? await _repo.removeReaction(_post.id, reaction)
          : await _repo.addReaction(_post.id, reaction);
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(reactions: summary);
        _sending = false;
        _changed = true;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 내가 쓴 것인가 — 이슈 #211.
  ///
  /// `PersonRef.userId` 와 내 id 를 견준다. ADR-0017 규약 5 가 `author` 를 `PersonRef` 로
  /// 통일한 이유가 정확히 이것이다 — 그전에는 닉네임뿐이라 앱이 문자열 `'나'` 를 표식으로
  /// 썼고, 닉네임이 '나' 인 사람이 오면 남의 댓글이 내 것으로 보였다.
  ///
  /// **틀려도 안전하다.** 여기서 잘못 보여 줘도 서버가 403 을 주고 화면이 그 이유를 말한다.
  /// 이건 보여 줄지 말지의 판정이지 권한 판정이 아니다.
  bool _isMine(PersonRef author) {
    final me = AuthState.user?.id;
    return me != null && !author.isWithdrawn && author.userId == me;
  }

  Widget _deleteButton({required VoidCallback onTap}) => GestureDetector(
        onTap: _sending ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text('삭제',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD9534F))),
        ),
      );

  /// 글 삭제. **되돌릴 수 없고 남의 댓글까지 사라지므로** 한 번 묻는다.
  Future<void> _confirmDeletePost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('이 글을 지울까요?'),
        content: Text(
          _post.commentCount > 0
              ? '댓글 ${_post.commentCount}개도 함께 사라져요. 되돌릴 수 없어요.'
              : '되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('그대로 두기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('지우기',
                style: TextStyle(color: Color(0xFFD9534F))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await _repo.deletePost(_post.id);
      if (!mounted) return;
      // 목록으로 돌아간다. 이 글은 이제 없으므로 상세에 머물 자리가 없다.
      _changed = true;
      Navigator.of(context).pop(true);
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 댓글 삭제. 남의 것을 지우지 않으므로 묻지 않는다 — 되돌릴 수 없다는 것은 같지만
  /// 잃는 것이 내 한 줄이고, 확인 창이 매번 뜨면 그것이 더 성가시다.
  Future<void> _confirmDeleteComment(CommunityComment comment) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _repo.deleteComment(_post.id, comment.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c.id != comment.id).toList();
        _post = _post.copyWith(
            commentCount: _post.commentCount > 0 ? _post.commentCount - 1 : 0);
        _sending = false;
        _changed = true;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 수정 버튼 — 이슈 #243. <b>내 글에만</b> 뜬다(삭제와 같은 분기).
  ///
  /// 댓글에는 없다 — 계약에 댓글 수정 경로가 없다.
  Widget _editButton({required VoidCallback onTap}) => GestureDetector(
        onTap: _sending ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text('수정',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: T.textSecondary)),
        ),
      );

  /// 글쓰기 화면을 <b>편집 모드로 재사용</b>한다 — 두 벌이면 상한도 문구도 갈린다.
  ///
  /// 안 고치고 나오면 {@code null} 이 온다. 그때는 아무것도 안 바뀌었으므로 다시 그리지
  /// 않는다 — `_changed` 도 안 세운다.
  Future<void> _editPost() async {
    final updated = await editPost(context, _post, repository: _repo);
    if (!mounted || updated == null) return;
    setState(() {
      _post = updated;
      _changed = true;
    });
    _toast('글을 고쳤어요');
  }

  /// 저장 버튼 — 반응 버튼과 같은 높이의 네모. 켜져 있으면 채운 책갈피에 강조색 테두리다.
  Widget _bookmarkButton() => GestureDetector(
        key: const Key('detail-bookmark'),
        onTap: _sending ? null : _toggleBookmark,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _post.bookmarked ? T.accentSoft : T.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _post.bookmarked ? T.accent : T.line),
          ),
          child: Icon(
              _post.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              size: 20,
              color: _post.bookmarked ? T.accent : T.textSecondary),
        ),
      );

  /// 저장을 켜고 끈다 — 반응과 같은 규칙: 응답의 상태를 그린다. 둘 다 멱등이라 재시도가 안전하다.
  Future<void> _toggleBookmark() async {
    if (_sending) return;
    if (_isGuest) {
      if (!await _askLogin('글을 저장할 수 있어요')) return;
    }
    setState(() => _sending = true);
    try {
      final on = _post.bookmarked
          ? await _repo.unbookmark(_post.id)
          : await _repo.bookmark(_post.id);
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(bookmarked: on);
        _sending = false;
        _changed = true;
      });
      _toast(on ? '저장했어요 — 내 정보 > 저장한 글' : '저장을 뺐어요');
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 신고 버튼 — 이슈 #166.
  ///
  /// **삭제와 반대 조건에 있다.** 삭제는 `_isMine` 안이고 신고는 밖이다 — 같은 칸에 두되
  /// 조건이 반대라, 남의 글에는 신고가·내 글에는 삭제가 뜬다. 초안은 이것을 "삭제 버튼
  /// 옆" 이라고만 적었는데 그대로 만들면 **자기 글에만 신고가 뜨는 앱**이 된다.
  Widget _reportButton({required VoidCallback onTap}) => GestureDetector(
        onTap: _sending ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text('신고',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: T.textMuted)),
        ),
      );

  /// 신고할 수 있는가.
  ///
  /// **내 것이 아니어야 하고, 작성자가 살아 있어야 한다.** 탈퇴한 사람의 글은 신고해도
  /// 조치할 대상이 없다 — 그 글을 내리는 것은 관리이고 #166 의 다음 조각이다.
  ///
  /// **게스트에게도 보인다.** 눌렀을 때 로그인을 안내한다 — 버튼을 숨기면 게스트는 이 앱에
  /// 신고 수단이 있다는 것 자체를 모른다.
  bool _canReport(PersonRef author) => !author.isWithdrawn && !_isMine(author);

  Future<void> _reportPost() async {
    final choice = await _askReport(_post.author.nickname, '이 글');
    if (choice == null) return;
    await _submitReport(
        () => _repo.reportPost(_post.id, choice.reason, memo: choice.memo),
        alsoBlock: choice.alsoBlock ? _post.author.userId : null);
  }

  Future<void> _reportComment(CommunityComment comment) async {
    final choice = await _askReport(comment.author.nickname, '이 댓글');
    if (choice == null) return;
    await _submitReport(
        () => _repo.reportComment(_post.id, comment.id, choice.reason, memo: choice.memo),
        alsoBlock: choice.alsoBlock ? comment.author.userId : null);
  }

  /// 사유를 묻는다. 채팅과 **같은 시트**를 쓴다 — 두 벌이면 문구도 사유 목록도 갈린다.
  ///
  /// 차단 칸(시트에서는 "가리기")이 함께 있다. 차단은 **사람 단위**라 커뮤니티에서는 그 사람의
  /// 글·댓글이 사라지고 채팅에서는 접힌다(`POST /api/blocks`, #166 · 애플 지침 1.2). 신고와 따로
  /// 차단하는 버튼도 있다([_blockButton]).
  Future<ReportChoice?> _askReport(String who, String subject) async {
    if (_isGuest) {
      if (!await _askLogin('신고할 수 있어요')) return null;
      if (!mounted) return null;
    }
    return ReportSheet.show(context,
        senderName: who, subject: subject, canBlock: true);
  }

  Future<void> _submitReport(Future<void> Function() send, {int? alsoBlock}) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await send();
      // **신고가 성공한 뒤에만 차단한다.** 순서가 반대면 신고가 실패했을 때 "차단됐는데
      // 접수는 안 된" 상태가 되고, 사용자는 접수됐다고 믿는다 — 채팅이 같은 순서다.
      if (alsoBlock != null) {
        await _repo.blockUser(alsoBlock);
        // 차단이 **성공한 뒤에** 적는다 — 목록들이 듣고 그 사람의 글을 곧바로 뺀다(1.2).
        BlockedAuthors.add(alsoBlock);
      }
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(alsoBlock == null
          ? '신고를 접수했어요. 상대에게는 알리지 않습니다'
          : '신고를 접수하고 이 사람을 차단했어요');
      if (alsoBlock != null) {
        await _refreshPost();
      }
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 차단 버튼 — 애플 지침 1.2 ("악성 이용자를 차단하는 수단"). **신고와 따로** 보인다.
  ///
  /// 신고 시트 안에도 차단 칸이 있지만, 신고할 생각이 없는 사람은 그 시트를 열지 않는다 — 차단이
  /// 있다는 것 자체를 모른다. 그래서 신고 옆에 같은 모양으로 둔다. 조건도 신고와 같다
  /// ([_canReport]): 내 것이 아니고 작성자가 살아 있어야 한다.
  Widget _blockButton({required VoidCallback onTap, required Key key}) => GestureDetector(
        key: key,
        onTap: _sending ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text('차단',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: T.textMuted)),
        ),
      );

  /// 한 번 묻고 차단한다.
  ///
  /// 확인 창이 **무엇이 일어나는지 셋을 다 말한다** — 이 사람의 글·댓글이 내 화면에서 사라진다 ·
  /// 운영자에게 알림이 간다 · 상대에게는 알리지 않는다. 1.2 가 요구하는 것이 앞의 둘이고, 셋째는
  /// 차단할지 말지를 정하는 데 결정적이다(신고 시트와 같은 말).
  ///
  /// 차단이 **성공한 뒤에만** [BlockedAuthors] 에 적는다. 먼저 적으면 실패했을 때 화면에서는 사라졌는데
  /// 서버는 모르는 상태가 되고, 다음에 불러올 때 되살아난다.
  Future<void> _block(PersonRef author) async {
    if (_sending) return;
    if (_isGuest) {
      if (!await _askLogin('차단할 수 있어요')) return;
      if (!mounted) return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${author.nickname} 님을 차단할까요?'),
        content: const Text(blockConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const Key('block-confirm'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('차단하기', style: TextStyle(color: Color(0xFFD9534F))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await _repo.blockUser(author.userId);
      BlockedAuthors.add(author.userId);
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('차단했어요. 이 사람의 글과 댓글이 더 이상 보이지 않아요');
      // 댓글 수를 서버에 다시 묻는다 — 서버는 차단한 사람의 댓글을 세지 않는다.
      await _refreshPost();
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 게스트가 반응·신고를 누르면 — `writePost()` 와 같은 길이다: 안내 → 로그인 화면 →
  /// 돌아오면 글을 다시 읽는다(#331). 토스트만 띄우면 로그인할 곳을 찾아 헤맨다.
  /// 로그인 화면은 pop 을 먼저 하고 completeLogin() 을 부르므로 [AuthState.settle] 을 기다린다.
  Future<bool> _askLogin(String what) async {
    final navigator = Navigator.of(context);
    // 이유는 로그인 화면이 들고 있는다(#517) — 스낵바는 전환 뒤 1.3초만 남는다.
    await navigator.push(
        MaterialPageRoute(builder: (_) => LoginScreen(reason: '로그인하면 $what')));
    await AuthState.settle();
    if (!mounted || !AuthState.isAuthenticated) return false;
    // 서버가 다시 말해야 게스트가 아니다 — `_isGuest` 는 응답의 `mine` 에서 나온다.
    await _refreshPost();
    return mounted && !_isGuest;
  }

  /// 이 글을 그리지 않는가 — 서버가 차단 표시를 붙였거나, 이 세션에서 작성자를 차단했다.
  bool get _postHidden => _post.hiddenForViewer;

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final hidden = _postHidden;
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 헤더 (뒤로가기)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(_changed),
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: T.surface,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: T.cardBorder),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: T.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // 제목 표시줄은 게시판 이름이다(#331). "산책 이야기" 는 어느 글에서나
                    // 같아서 지금 어디를 보는지 말해 주지 않았다.
                    Text(
                      post.board?.label ?? '커뮤니티',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // 차단한 사람의 글 — 내용 · 반응 · 댓글 · 입력칸 없이 한 줄만. 펼치는 길이 없다(1.2).
              if (hidden)
                Expanded(child: _hiddenPost())
              else ...[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                    children: [
                      _postCard(post),
                      const SizedBox(height: 14),
                      _reactionRow(),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(
                            Icons.forum_outlined,
                            size: 17,
                            color: T.warmMid,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            // 서버가 센 값이다. 화면에 몇 장을 불러왔든 글의 댓글 수는
                            // 하나다 — 목록 카드의 숫자와도 그래야 같다.
                            '댓글 ${_post.commentCount}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: T.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._commentSection(),
                    ],
                  ),
                ),
                _inputBar(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 댓글 자리. 못 불러왔으면 **빈 스레드가 아니라 이유**를 그린다 — 빈 스레드는
  /// "아직 댓글이 없다" 로 읽힌다.
  List<Widget> _commentSection() {
    if (_loadingComments) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final failure = _commentsFailure;
    if (failure != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(children: [
            Text(failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: T.textSecondary)),
            if (failure.retryable) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _loadComments,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                      gradient: _warm, borderRadius: BorderRadius.circular(12)),
                  child: const Text('다시 시도',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ],
          ]),
        ),
      ];
    }
    // 차단한 사람의 댓글은 접지 않고 뺀다(1.2). 서버가 이미 빼고 보내지만(옛 서버는 표시만 붙인다),
    // 이 화면에서 방금 차단한 사람의 댓글은 이미 받아 둔 목록에 남아 있다.
    final visible = visibleComments(_comments);
    if (visible.isEmpty && !_hasMoreComments) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('첫 댓글을 남겨보세요.',
                style: TextStyle(color: T.textMuted)),
          ),
        ),
      ];
    }
    return [
      for (final comment in visible) ...[
        _commentCard(comment),
        const SizedBox(height: 10),
      ],
      if (_hasMoreComments)
        Center(
          child: GestureDetector(
            onTap: _loadingMoreComments ? null : _loadMoreComments,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: T.cardBorder),
              ),
              child: Text(_loadingMoreComments ? '불러오는 중…' : '댓글 더 보기',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: T.textSecondary)),
            ),
          ),
        ),
    ];
  }

  Widget _avatar(String nickname, double size) {
    final colors =
        _avatarColors[nickname.hashCode.abs() % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Text(
        nickname.isEmpty ? '?' : nickname.characters.first,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 상세의 날짜. 목록과 달리 시각까지 그린다 — 스레드를 읽는 사람은 순서를 본다.
  Widget _postCard(CommunityPost post) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 작성자
          Row(
            children: [
              _avatar(post.author.nickname, 44),
              const SizedBox(width: 11),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.nickname,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // 좁아지면 칩과 장소가 함께 줄어든다 — 칩이 먼저 아이콘 자리까지 잃지 않게 몫을 더 준다.
                        Flexible(flex: 2, child: _boardChip(post.board)),
                        if (post.loc != null) ...[
                          const SizedBox(width: 7),
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: T.textMuted,
                          ),
                          const SizedBox(width: 2),
                          // 장소 이름은 줄인다 — 폰 폭(411)에서 날짜까지 한 줄이라 넘쳤다(#331).
                          Flexible(
                            child: Text(
                              post.loc!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: T.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 날짜도 줄어들 수 있어야 한다 — 왼쪽 열이 게시판 칩·장소를 다 쥐고 있어 폰 폭에서
              // 넘쳤다(#331). 실제 글꼴에서는 "9월 1일 16:30" 이 다 들어간다.
              Flexible(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      dateTimeLabel(post.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 11.5, color: T.textMuted),
                    ),
                    // 고친 글인지 읽는 사람이 알아야 한다 — 이미 달린 댓글이 무엇에 대한
                    // 말이었는지 되짚을 수 있는 유일한 단서다. 서버는 **값이 실제로 달라진
                    // 경우에만** updatedAt 을 만든다(#211). 날짜 **아래**에 둔다 — 옆에 두면
                    // 신고 · 차단이 함께 서는 머리줄이 폰 폭에서 넘쳤다.
                    if (post.updatedAt != null)
                      const Text('수정됨',
                          style: TextStyle(fontSize: 11.5, color: T.textMuted)),
                  ],
                ),
              ),
              if (_isMine(post.author)) ...[
                const SizedBox(width: 8),
                _editButton(onTap: _editPost),
                const SizedBox(width: 8),
                _deleteButton(onTap: _confirmDeletePost),
              ] else if (_canReport(post.author)) ...[
                const SizedBox(width: 8),
                _reportButton(onTap: _reportPost),
                const SizedBox(width: 8),
                _blockButton(key: const Key('block-post'), onTap: () => _block(post.author)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // 제목
          Text(
            post.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: T.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // 본문. 차단한 사람의 글이면 이 카드까지 오지 않는다 — build 가 [_hiddenPost] 를 그린다.
          Text(
            post.body,
            style: const TextStyle(fontSize: 14, height: 1.6, color: T.textSecondary),
          ),
          // 붙은 사진·영상 (#429). 누르면 전체 보기.
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: 14),
            PostMediaStrip(media: post.media),
          ],
          // 붙은 코스 (#339). 누르면 지도가 아니라 그림만 크게 — 상세에서 온전한 선을
          // 다시 부르는 것은 "다시 걷기"(다음 조각)의 일이다.
          if (post.course != null) ...[
            const SizedBox(height: 14),
            PostCourseCard(course: post.course!),
          ],
        ],
      ),
    );
  }

  /// 차단한 사람의 글을 직접 열었을 때(링크 · 알림 · 방금 차단). **제목도 본문도 사진도 없다.**
  ///
  /// 예전에는 "가린 사람의 글입니다. 눌러서 보기" 로 접어 두고 누르면 폈다. 1.2 는 차단한 사람의
  /// 콘텐츠가 사라지기를 요구하므로 펴는 길을 없앴다. 다시 보려면 차단을 풀어야 한다.
  Widget _hiddenPost() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        children: [
          GlassCard(
            key: const Key('hidden-post'),
            child: Row(children: [
              const Icon(Icons.block_rounded, size: 20, color: T.textMuted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(hiddenPostMessage,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
              ),
            ]),
          ),
        ],
      );

  Widget _boardChip(CommunityBoard? board) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x1AFF8F63),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pets, size: 11, color: T.warmText),
          const SizedBox(width: 4),
          // 머리줄에 수정됨 · 신고 · 차단이 함께 서면 칩 자리가 좁아진다 — 넘치지 않고 말줄임으로 끝난다.
          Flexible(
            child: Text(
              board?.label ?? '기타',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: T.warmText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 반응 셋. **동시에 여러 개를 누를 수 있다**(ADR-0016 결정 2) — 서로 배타적인
  /// 개념이 아니라서 하나만 켜지는 라디오로 만들지 않는다.
  Widget _reactionRow() {
    const icons = {
      CommunityReaction.help: Icons.thumb_up_alt_outlined,
      CommunityReaction.cute: Icons.favorite_outline,
      CommunityReaction.empathy: Icons.emoji_emotions_outlined,
    };
    return Row(
      children: [
        for (final reaction in CommunityReaction.values) ...[
          if (reaction != CommunityReaction.values.first)
            const SizedBox(width: 9),
          Expanded(child: _reactionBtn(reaction, icons[reaction]!)),
        ],
        // 저장 — "내 사진첩" (#451 4번). 반응 줄 끝의 네모 하나. 내 글도 남의 글도, 게스트에게도
        // 보인다(눌러야 로그인 안내가 뜬다 — 숨기면 저장이 있다는 것 자체를 모른다). 머리말에
        // 두면 390dp 에서 날짜 줄이 넘쳤다 — 여기서는 반응 셋이 Expanded 라 줄어든다.
        const SizedBox(width: 9),
        _bookmarkButton(),
      ],
    );
  }

  Widget _reactionBtn(CommunityReaction reaction, IconData icon) {
    // 게스트에게는 **꺼진 채로** 그린다. mine 이 null 인 것을 "안 눌렀음" 으로
    // 뭉개면 로그인한 사람의 화면과 구별되지 않는다.
    final on = _post.reactions.isMine(reaction);
    return GestureDetector(
      onTap: () => _toggleReaction(reaction),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: on ? _warm : null,
          color: on ? null : T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? Colors.transparent : T.line,
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: on ? Colors.white : T.textSecondary),
            const SizedBox(width: 6),
            // 유일한 Flexible — 저장 네모(#451 4번)가 들어와 칸이 좁아지면 이름이 말줄임으로
            // 끝난다. 실제 글꼴에서는 390dp 에서도 통째로 들어간다(테스트 글꼴이 더 넓다).
            Flexible(
              child: Text(
                reaction.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : T.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${_post.reactions.countOf(reaction)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : T.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentCard(CommunityComment comment) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: T.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(comment.author.nickname, 34),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 닉네임 아래에 시각 — 신고 옆에 차단이 들어오며 한 줄에 넷(닉네임 · 신고 · 차단 ·
                    // 시각)이 서면 폰 폭 · 큰 글자에서 넘쳤다. 둘 다 길면 말줄임으로 끝난다.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment.author.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: T.textPrimary,
                            ),
                          ),
                          Text(
                            dateTimeLabel(comment.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: T.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isMine(comment.author)) ...[
                      const SizedBox(width: 8),
                      _deleteButton(onTap: () => _confirmDeleteComment(comment)),
                    ] else if (_canReport(comment.author)) ...[
                      const SizedBox(width: 8),
                      _reportButton(onTap: () => _reportComment(comment)),
                      const SizedBox(width: 8),
                      _blockButton(
                          key: Key('block-comment-${comment.id}'),
                          onTap: () => _block(comment.author)),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.body,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    // 게스트에게 입력칸을 주고 보낼 때 401 을 내면, 쓴 글자를 잃고 나서야 로그인이
    // 필요한 것을 안다. 아예 안 그린다.
    if (_isGuest) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: T.cardBg,
          border: Border(top: BorderSide(color: Color(0x22785AA0))),
        ),
        child: const Text(
          '로그인하면 댓글과 반응을 남길 수 있어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: T.textSecondary,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: T.cardBg,
        border: Border(top: BorderSide(color: Color(0x22785AA0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 댓글도 게스트에게 보인다 — 커뮤니티 UGC 의 대부분이 댓글이다 (#253).
          // 글쓰기 화면과 같은 사실을 같은 자리에서 말한다.
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text('로그인하지 않은 사람에게도 보여요',
                style: TextStyle(fontSize: 11, color: T.textMuted)),
          ),
          Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _ctrl,
                maxLength: CommunityRepository.maxCommentLength,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 14, color: T.textPrimary),
                decoration: const InputDecoration(
                  hintText: '우리 아이 이야기를 나눠보세요',
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                  border: InputBorder.none,
                  counterText: '',
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
              // gradient 가 있으면 color 는 무시된다 — 보내는 중 표시가 안 보였다.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _sending ? null : _warm,
                color: _sending ? T.textFaint : null,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
          ]),
        ],
      ),
    );
  }
}
