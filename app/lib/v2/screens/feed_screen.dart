import 'package:flutter/material.dart';

import '../domain/date_label.dart';
import '../data/community_repository.dart';
import '../data/neighborhood_store.dart';
import '../domain/neighborhood.dart';
import '../widgets/post_course_card.dart';
import '../widgets/post_media_strip.dart';
import '../widgets/post_photo_wall.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import '../data/crew_repository.dart';
import 'crew_section.dart';
import 'post_detail_screen.dart';
import 'post_write_screen.dart';

/// 커뮤니티 (feed) — 반려인들의 산책·동반장소·건강 이야기. 카드/리스트 토글.
///
/// **서버에서 온다** (이슈 #171). 2026-09 이전에는 `kPetPosts` 상수 4건을 걸렀고,
/// 그래서 누가 글을 써도 아무에게도 안 보였다.
///
/// 게시판 칩의 한글은 **화면 문구**다. 서버로 나가는 값은 `CommunityBoard.wire`
/// (`walk_review` 등)이고 둘을 묶어 두는 자리는 그 enum 하나다(ADR-0016).
class FeedScreen extends StatefulWidget {
  /// 테스트가 가짜 서버를 넣는 자리. 앱에서는 `null` 이라 기본 리포지토리가 선다.
  final CommunityRepository? repository;

  /// 내 동네를 읽는 자리 (#342). **테스트만 넘긴다.**
  final NeighborhoodStore? neighborhoods;

  /// 크루 갈래가 쓸 서버 (#417). **테스트만 넘긴다** — 안 넘기면 갈래를 열 때 진짜
  /// 리포지토리가 선다. 여기 자리를 만드는 이유는 하나다: 이 자리가 없으면 "탭을 안
  /// 늘리고 커뮤니티 안에 넣었다" 를 끝까지 걸어 보는 검사를 쓸 수 없고, 그러면 갈래가
  /// 통째로 검사 밖에 남는다.
  final CrewRepository? crews;

  const FeedScreen({
    super.key,
    this.repository,
    this.neighborhoods,
    this.crews,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

/// 커뮤니티 안의 갈래 둘.
enum _Section { posts, crews }

class _FeedScreenState extends State<FeedScreen> {
  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();

  /// 지금 보고 있는 갈래. 커뮤니티 안에서 **이야기와 크루**가 자리를 나눈다(#417).
  ///
  /// 탭을 여섯째로 늘리지 않은 이유는 라벨이 접히기 때문이다 — #396 에서 다섯 탭이
  /// 360dp·글자 1.5배에서 이미 한계였다. 사장님이 "소모임은 커뮤니티에 넣을 수 있지
  /// 않나" 라고 한 것도 같은 자리다.
  _Section _section = _Section.posts;

  /// `null` 이면 전체.
  CommunityBoard? _board;

  /// "우리 동네" 만 볼까 (#342). 동네를 고른 사람에게만 칩이 보인다 —
  /// 안 고른 채로 켜면 서버가 400 이고, 그건 사용자 잘못이 아니다.
  bool _myNeighborhood = false;

  /// 내가 고른 동네. `null` 이면 칩 자체가 없다.
  Neighborhood? _mine;
  String _view = 'card'; // 'card' | 'list' | 'grid'(사진 벽, #451)

  /// 이 배율부터 **보조 정보를 접는다** — 카드 머리말의 동네, 필터 줄의 "N개의 글", 동네
  /// 칩의 글자.
  ///
  /// 1.3 은 홈·트래킹 패널과 같은 문턱이다(#396 · #402) — 화면마다 다르면 같은 배율에서
  /// 어떤 곳은 접히고 어떤 곳은 안 접혀 사용자가 규칙을 못 읽는다. 무엇을 접는지는 줄마다
  /// 다르다: 닉네임(누가)·날짜(언제)·게시판 이름·글쓰기(누르는 것)는 남기고, 빼도 뜻이 서는
  /// 보조 정보만 접는다. 남긴 글자를 [Expanded]·[Flexible] 로 감싼 것은 **바닥**이다 — 더
  /// 좁아도 노란 줄무늬 대신 말줄임으로 끝난다(#433).
  static const double _foldFrom = 1.3;

  bool _folded(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(11) >= 11 * _foldFrom;

  List<CommunityPost> _posts = const [];
  String? _nextCursor;
  bool _hasMore = false;

  bool _loading = true;
  bool _loadingMore = false;

  /// 못 불러온 이유. **빈 목록으로 그리지 않는다** — 빈 목록은 "아직 글이 없다" 로
  /// 읽히고, 그러면 서버가 죽은 것을 아무도 모른다.
  CommunityFailure? _failure;

  /// 요청 세대. 늦게 온 응답이 화면을 되돌리는 것을 막는다.
  ///
  /// 게시판을 빠르게 두 번 바꾸면 첫 요청이 나중에 도착할 수 있다. 그러면 지금 고른
  /// 게시판의 목록 위에 **아까 게시판의 글**이 덮인다 — 사용자에게는 필터가 안 먹는
  /// 것으로 보인다. 커서도 같이 덮여서 '더 보기' 가 남의 게시판 다음 장을 붙인다.
  int _generation = 0;

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  @override
  void initState() {
    super.initState();
    _loadNeighborhood();
    kNeighborhoodRev.addListener(_loadNeighborhood);
    _load();
  }

  @override
  void dispose() {
    kNeighborhoodRev.removeListener(_loadNeighborhood);
    super.dispose();
  }

  Future<void> _loadNeighborhood() async {
    final mine = await (widget.neighborhoods ?? NeighborhoodStore()).read();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      // 동네를 지웠는데 토글이 켜져 있으면 그 뒤 모든 조회가 400 이다.
      if (mine == null) _myNeighborhood = false;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await _repo.feed(board: _board, myNeighborhood: _myNeighborhood);
      if (!mounted || generation != _generation) return;
      setState(() {
        _posts = page.items;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.feed(
          board: _board, cursor: cursor, myNeighborhood: _myNeighborhood);
      // 기다리는 동안 게시판이 바뀌었으면 이 장은 남의 것이다. 붙이면 두 게시판의
      // 글이 한 목록에 섞인다.
      if (!mounted || generation != _generation) return;
      setState(() {
        _posts = [..._posts, ...page.items];
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on CommunityFailure {
      // 다음 장을 못 받은 것은 첫 장까지 지울 이유가 아니다. 버튼만 되살린다.
      if (!mounted || generation != _generation) return;
      setState(() => _loadingMore = false);
    }
  }

  void _selectBoard(CommunityBoard? board) {
    if (_board == board) return;
    setState(() => _board = board);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(children: [
                // Expanded 가 Spacer 를 겸한다 — 제목이 flex 가 아니면 320dp·2.0배에서
                // 제목(22px×4자)과 전환·프로필이 한 줄에 안 들어가 27px 넘쳤다(#433). 이
                // 줄에는 접을 보조 정보가 없다(전환도 프로필도 누르는 것) — 그 폭·배율에서만
                // 제목이 말줄임으로 끝난다.
                const Expanded(
                  child: Text('커뮤니티',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: T.textPrimary)),
                ),
                // 카드/리스트 토글은 **글 목록의 것**이다. 크루 갈래에서 남겨 두면
                // 아무것도 안 바꾸는 버튼이 되고, 그런 버튼은 한 번 눌러 본 사람에게
                // 화면이 고장 난 것으로 보인다.
                if (_section == _Section.posts) ...[
                  _viewToggle(),
                  const SizedBox(width: 10),
                ],
                const ProfileAvatar(),
              ]),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    _section == _Section.posts ? '우리 아이들 이야기' : '동네 반려인 모임',
                    style: const TextStyle(fontSize: 13, color: T.textSecondary)),
              ),
            ),
            const SizedBox(height: 10),
            _sectionTabs(),
            const SizedBox(height: 10),
            if (_section == _Section.posts) ...[
              _boardFilter(),
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ] else
              // 갈래를 떠나면 이 위젯이 통째로 사라지고, 돌아오면 새로 선다 — 그래서
              // 목록이 다시 뜬다. 그 사이 남이 만든 크루를 안 보여 주지 않으려면 그 편이
              // 맞다. 대신 고른 범위(내 크루/우리 동네)도 함께 초기화된다.
              Expanded(
                child: CrewSection(
                  key: const Key('crew-section'),
                  repository: widget.crews,
                  neighborhoods: widget.neighborhoods,
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// 이야기 | 크루. **알약 두 개**이고 보드 필터와 모양을 맞춘다 — 같은 줄에 사는
  /// 다른 종류의 필터가 서로 다르게 생기면 어느 쪽이 더 위인지 안 읽힌다.
  Widget _sectionTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        _sectionTab(_Section.posts, '이야기'),
        const SizedBox(width: 8),
        _sectionTab(_Section.crews, '크루'),
      ]),
    );
  }

  Widget _sectionTab(_Section section, String label) {
    final on = _section == section;
    return GestureDetector(
      key: Key('community-section-${section.name}'),
      onTap: () {
        if (_section == section) return;
        setState(() => _section = section);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: on ? T.sigEnd.withValues(alpha: 0.2) : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? T.sigEnd : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: on ? T.textPrimary : T.textMuted)),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final failure = _failure;
    if (failure != null) {
      return _failureView(failure);
    }
    if (_posts.isEmpty) {
      return _emptyView();
    }
    final padding = EdgeInsets.fromLTRB(12, 4, 12, MediaQuery.of(context).padding.bottom + 100);
    // 사진 벽 — 사진·영상이 있는 글만 두 열로(#451). 한 화면에 여섯~여덟 장이 보인다.
    if (_view == 'grid') {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: padding,
          children: [
            if (PostPhotoWall.withMedia(_posts).isEmpty)
              _photoEmptyView()
            else
              PostPhotoWall(posts: _posts, onTap: _open),
            if (_hasMore) _moreButton(),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: padding,
        children: [
          for (final post in _posts) ...[
            _view == 'card' ? _card(post) : _row(post),
            SizedBox(height: _view == 'card' ? 14 : 10),
          ],
          if (_hasMore) _moreButton(),
        ],
      ),
    );
  }

  /// 글은 있는데 사진 있는 글이 없을 때. "글이 없다" 와 다른 말이다 — 사진을 붙이면 된다.
  Widget _photoEmptyView() => Container(
        key: const Key('feed-photo-empty'),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: T.cardBg,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: T.cardBorder),
        ),
        child: const Column(children: [
          Icon(Icons.photo_library_outlined, size: 32, color: T.textFaint),
          SizedBox(height: 10),
          Text('사진이 있는 글이 아직 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
          SizedBox(height: 4),
          Text('글쓰기에서 사진을 붙이면 여기 벽에 걸려요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: T.textSecondary)),
        ]),
      );

  /// 글이 하나도 없을 때.
  ///
  /// **'불러오지 못했어요' 와 다른 문구여야 한다.** 빈 것과 못 불러온 것은 사용자가 할 일이
  /// 다르다 — 하나는 쓰면 되고 하나는 기다리면 된다. `pet.dart` 가 산책 더미를 지우며 남긴
  /// 규칙이 같은 말을 한다: "0 은 '산책을 한 번도 안 했다' 로 읽힌다".
  ///
  /// 어느 게시판이 비었는지 말한다. '자유' 를 골랐는데 그냥 "글이 없어요" 라고만 하면
  /// 앱 전체가 빈 것처럼 읽힌다(#173).
  Widget _emptyView() {
    final board = _board;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            board == null
                ? '아직 글이 없어요'
                : '아직 ${board.label} 게시판에 글이 없어요',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text('첫 이야기를 남겨보세요',
              style: TextStyle(fontSize: 13, color: T.textMuted)),
          const SizedBox(height: 14),
          _writeButton(label: '글쓰기', big: true),
        ]),
      ),
    );
  }

  /// 글쓰기로 가는 버튼. 두 자리에서 같은 것을 쓴다 — 게시판 줄과 빈 화면.
  ///
  /// 떠 있는 FAB 을 안 만든 이유는 셸이 화면 위에 네비 띠를 덮기 때문이다
  /// (`main_shell` 의 알약이 bottom+8~74, 가운데 버튼이 bottom+38~96). 그 띠는 Stack 의
  /// **마지막** 자식이라 그 안에 그린 것은 눌리지 않는다.
  Widget _writeButton({required String label, bool big = false}) {
    return GestureDetector(
      onTap: _openWrite,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: big ? 20 : 13, vertical: big ? 11 : 7),
        decoration: BoxDecoration(
            gradient: _warm, borderRadius: BorderRadius.circular(big ? 14 : 11)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_outlined, size: big ? 17 : 14, color: Colors.white),
          SizedBox(width: big ? 7 : 5),
          Text(label,
              style: TextStyle(
                  fontSize: big ? 14 : 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ]),
      ),
    );
  }

  /// 글쓰기 화면을 연다. 미로그인 판정은 [writePost] 안에 한 곳만 있다.
  ///
  /// 방금 쓴 글이 목록에 보여야 한다(#172 완료 조건 6). 지금 고른 게시판을 들고 가서
  /// 사용자가 다시 고르지 않게 한다.
  Future<void> _openWrite() async {
    final written = await writePost(
      context,
      repository: _repo,
      initialBoard: _board,
    );
    if (!mounted || written == null) return;
    await _load();
  }

  /// 못 불러왔을 때의 화면.
  ///
  /// 빈 목록이 아니라 **이유와 다시 시도**다. `pet.dart` 가 산책 더미를 지우며 남긴
  /// 규칙이 그것이다 — "0 은 '산책을 한 번도 안 했다' 로 읽힌다".
  Widget _failureView(CommunityFailure failure) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 34, color: T.textMuted),
          const SizedBox(height: 12),
          Text(
            failure.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
          ),
          if (failure.retryable) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                    gradient: _warm, borderRadius: BorderRadius.circular(13)),
                child: const Text('다시 시도',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _moreButton() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Center(
          child: GestureDetector(
            onTap: _loadingMore ? null : _loadMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: T.cardBorder),
              ),
              child: Text(_loadingMore ? '불러오는 중…' : '더 보기',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: T.textSecondary)),
            ),
          ),
        ),
      );

  Widget _viewToggle() {
    Widget seg(String value, IconData icon) {
      final on = _view == value;
      return GestureDetector(
        key: Key('feed-view-$value'),
        onTap: () => setState(() => _view = value),
        child: Container(
          width: 42,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: on ? _warm : null,
              borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 20, color: on ? Colors.white : T.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: T.cardBorder),
      ),
      child: Row(children: [
        seg('card', Icons.view_agenda_outlined),
        seg('list', Icons.format_list_bulleted),
        // 사진 벽 — 핀터레스트·반려견 판의 격자(#451)
        seg('grid', Icons.grid_view_rounded),
      ]),
    );
  }

  // 보드 필터: 가로로 무한정 늘지 않도록 '전체 ▾' 버튼 + 바텀시트.
  /// "우리 동네" 토글. 켜면 같은 구의 글만 온다 — 구 코드는 안 보낸다(#342).
  ///
  /// [folded] 면 글자를 접고 아이콘만 남긴다 — 켜졌는지는 색이 말한다(#433).
  Widget _neighborhoodChip({required bool folded}) {
    final mine = _mine!;
    const teal = Color(0xFF0B7A75);
    return GestureDetector(
      onTap: () {
        setState(() => _myNeighborhood = !_myNeighborhood);
        _load();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _myNeighborhood ? teal : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _myNeighborhood ? Colors.transparent : const Color(0x330B7A75)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.home_work_outlined,
              size: 14, color: _myNeighborhood ? Colors.white : teal),
          if (!folded) ...[
            const SizedBox(width: 5),
            Text(mine.districtLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _myNeighborhood ? Colors.white : teal)),
          ],
        ]),
      ),
    );
  }

  Widget _boardFilter() {
    final folded = _folded(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        // 칩 둘은 **옆으로 스크롤하는 줄** 안에 있다 — 글쓰기가 오른쪽 끝에 남고, 칩은 좁으면
        // 잘리는 대신 밀려 들어간다. 칩을 Flexible 로 두면 Row 가 필요와 상관없이 몫을
        // 나눠 줘서 320dp 에서는 보통 배율에서도 "전체" 가 말줄임이 됐다(#433).
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: _openBoardSheet,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: T.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: T.cardBorder),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.tune, size: 16, color: T.textSecondary),
                    const SizedBox(width: 7),
                    Text(_board?.label ?? '전체',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: T.textSecondary)),
                    const SizedBox(width: 5),
                    const Icon(Icons.expand_more, size: 16, color: T.textMuted),
                  ]),
                ),
              ),
              // 동네를 고른 사람에게만 보인다 (#342).
              if (_mine != null) ...[
                const SizedBox(width: 8),
                _neighborhoodChip(folded: folded),
              ],
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // "N개의 글" 은 보조 정보다 — 1.3배부터 접는다. 게시판 이름과 글쓰기는 누르는 것이라
        // 남긴다.
        if (_failure == null && !folded) ...[
          Text('${_posts.length}개의 글',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: T.textMuted)),
          const SizedBox(width: 10),
        ],
        _writeButton(label: '글쓰기'),
      ]),
    );
  }

  void _openBoardSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
            color: T.surfaceBright,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                          color: const Color(0x2E281E30),
                          borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 16),
              const Text('게시판',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: T.textPrimary)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _boardOption(sheetCtx, null, '전체'),
                for (final board in CommunityBoard.values)
                  _boardOption(sheetCtx, board, board.label),
              ]),
            ]),
      ),
    );
  }

  Widget _boardOption(BuildContext sheetCtx, CommunityBoard? board, String label) {
    final on = _board == board;
    return GestureDetector(
      onTap: () {
        Navigator.pop(sheetCtx);
        _selectBoard(board);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          gradient: on ? _warm : null,
          color: on ? null : T.surface,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : T.textSecondary)),
      ),
    );
  }

  Future<void> _open(CommunityPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post, repository: _repo),
      ),
    );
    // 상세에서 **실제로 뭔가 바뀌었을 때만** 다시 부른다.
    //
    // 예전에는 무조건 불렀다. 그러면 글 하나를 열어 보고 나온 것만으로 '더 보기' 로
    // 쌓아 둔 장이 전부 사라지고 스크롤이 맨 위로 돌아간다 — 목록을 훑어보는 사람에게
    // 그건 앱이 자기를 되돌리는 것으로 느껴진다.
    if (mounted && changed == true) await _load();
  }

  // 닉네임 원형 아바타 (닉 첫 글자, 따뜻한 그라데이션).
  Widget _avatar(CommunityPost post, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(shape: BoxShape.circle, gradient: _warm),
        child: Text(_initial(post.author.nickname),
            style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      );

  /// 아바타 글자. 닉네임이 빈 문자열이면 `characters.first` 가 던진다 — 서버가
  /// 탈퇴한 사람에게 '알 수 없음' 을 주므로 빈 값이 올 일은 없지만, 카드 하나 때문에
  /// 목록이 죽는 것은 막는다.
  static String _initial(String nickname) =>
      nickname.isEmpty ? '?' : nickname.characters.first;

  /// 보드별 색. 키가 아니라 enum 으로 가른다 — 문자열로 가르면 서버가 값을 바꿀 때
  /// `default` 로 조용히 떨어진다.
  Color _boardColor(CommunityBoard? board) => switch (board) {
        CommunityBoard.walkReview => const Color(0xFF33BFA6),
        CommunityBoard.petPlace => const Color(0xFFFF7E6B),
        CommunityBoard.health => const Color(0xFF5B8DEF),
        CommunityBoard.free => T.accent,
        CommunityBoard.brag => const Color(0xFFEFA13C),
        null => T.warmMid,
      };

  Widget _boardChip(CommunityBoard? board) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: _boardColor(board).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8)),
        child: Text(board?.label ?? '기타',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _boardColor(board))),
      );

  /// 목록의 날짜. 시각까지는 안 그린다 — 카드 한 줄에 들어가야 한다.
  Widget _card(CommunityPost post) {
    return GestureDetector(
      onTap: () => _open(post),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(post, 40),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      // 닉네임(누가)과 날짜(언제)는 남고, 동네는 1.3배부터 접는다 — 셋 다
                      // flex 가 아닌 채로는 360dp·2.0배에서 58px 넘쳤다(#433). 닉네임을
                      // Flexible 로 감싼 것은 바닥이다 — 긴 닉네임은 말줄임으로 끝나고
                      // 날짜는 오른쪽 끝에 그대로다.
                      Expanded(
                        child: Row(children: [
                          Flexible(
                            child: Text(post.author.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: T.textPrimary)),
                          ),
                          // 글쓴이의 동네 — **구까지만** (#342). 안 골랐으면 자리가 없다.
                          if (post.authorDistrict != null && !_folded(context)) ...[
                            const SizedBox(width: 6),
                            Text(post.authorDistrict!,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0B7A75))),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text(dateLabel(post.createdAt),
                          style: const TextStyle(
                              fontSize: 11.5, color: T.textMuted)),
                    ]),
                    const SizedBox(height: 5),
                    Row(children: [
                      _boardChip(post.board),
                      if (post.loc != null) ...[
                        const SizedBox(width: 7),
                        const Icon(Icons.place_outlined,
                            size: 13, color: T.textMuted),
                        const SizedBox(width: 2),
                        // Flexible 이 없으면 긴 장소 이름이 Row 를 넘쳐 노란 줄무늬가
                        // 뜬다. 아래 리스트 뷰는 진작부터 이 모양이었다.
                        Flexible(
                          child: Text(post.loc!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: T.textMuted)),
                        ),
                      ],
                    ]),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(post.title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: T.textPrimary)),
          const SizedBox(height: 5),
          Text(post.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.5, color: T.textSecondary)),
          // 붙은 사진·영상 (#429). 한 장이면 크게, 넷 넘으면 +N.
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: 12),
            PostMediaStrip(media: post.media),
          ],
          // 붙은 코스가 있으면 그림 한 장 (#339). 비공개로 되돌렸거나 지웠으면 안 온다.
          if (post.course != null) ...[
            const SizedBox(height: 12),
            PostCourseCard(course: post.course!),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final reaction in CommunityReaction.values)
              _reactionChip(reaction, post.reactions),
          ]),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0x14785AA0)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.chat_bubble_outline, size: 16, color: T.textMuted),
            const SizedBox(width: 6),
            // Expanded 가 Spacer 를 겸한다. flex 가 아니면 Row 가 글자에 폭을 무한대로
            // 줘서 기기 글자 크기를 키우면 오른쪽으로 넘치고, Spacer 는 남은 공간이
            // 음수여도 0 까지만 줄어든다 — 360dp·1.5배에서 4px 넘쳤다(#432).
            // 두 줄로 접지 않는다 — 한글은 음절 사이에서 줄이 바뀌어 "보/기" 로 갈라진다.
            // 줄어드는 것은 뒤쪽 안내("자세히 보기")이고 개수는 앞에 있어 남는다.
            Expanded(
              child: Text('댓글 ${post.commentCount}개 · 자세히 보기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: T.textSecondary)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ]),
      ),
    );
  }

  Widget _reactionChip(CommunityReaction reaction, ReactionSummary summary) {
    final count = summary.countOf(reaction);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: T.cardBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(reaction.label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: T.textSecondary)),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Text('$count',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: T.textMuted)),
        ],
      ]),
    );
  }

  Widget _row(CommunityPost post) {
    return GestureDetector(
      onTap: () => _open(post),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
        child: Row(children: [
          _avatar(post, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: T.textPrimary)),
                  const SizedBox(height: 5),
                  Row(children: [
                    _boardChip(post.board),
                    if (post.loc != null) ...[
                      const SizedBox(width: 7),
                      const Icon(Icons.place_outlined,
                          size: 12, color: T.textMuted),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(post.loc!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: T.textMuted)),
                      ),
                    ],
                    const SizedBox(width: 8),
                    const Icon(Icons.chat_bubble_outline,
                        size: 13, color: T.textMuted),
                    const SizedBox(width: 3),
                    Text('${post.commentCount}',
                        style: const TextStyle(
                            fontSize: 12, color: T.textMuted)),
                  ]),
                ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
        ]),
      ),
    );
  }
}
