// lib/v2/screens/post_write_screen.dart
//
// 커뮤니티 글쓰기 — 이슈 #172.
//
// ## 왜 새로 만드나
//
// `mvp-scope.md` 와 `roadmap.md` 가 이 화면을 `create_screen.dart` 라고 지목하고 있었다.
// 그 파일은 **산책 기록 작성**이다 — `walk_outbox`·`walk_sync` 를 import 하고 저장 버튼이
// '산책 기록 저장하기' 이며, 안에 board·post 라는 개념이 0건이다. 호출부 둘도 전부 산책
// 축이다. 한 번도 커뮤니티 글쓰기였던 적이 없다(#175).
//
// ## 폼 규칙은 v2 의 방식을 따른다
//
// `Form`/`TextFormField`/`GlobalKey<FormState>` 를 쓰지 않는다 — v2 에 그 셋을 쓰는 화면이
// 하나도 없다(레거시 `features/` 에만 있다). 평범한 `TextField` + 컨트롤러 + `_submit()`
// 첫머리의 손검사다. `pet_registration_sheet` 가 같은 모양이고, 실패도 스낵바가 아니라
// **폼 안의 빨간 한 줄**로 말한다 — 폼에서 스낵바는 입력칸을 가린다.
//
// ## 길이는 저장소 상수를 본다
//
// 숫자를 여기 적지 않는다. `CommunityRepository` 가 계약·서버 `@Size` 와 같은 수를 들고
// 있고, 갈리면 `CommunityContractSpecTest` 가 빨간불을 낸다. 여기서 안 막으면 상한을 넘긴
// 사람이 올리기를 누른 뒤에야 400 을 받는다(#161).
library;

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import 'login_screen.dart';

/// 글쓰기를 여는 **유일한 문**. 미로그인이면 로그인부터 안내한다.
///
/// `start_walk.dart` 와 같은 모양이다. 진입점이 셋이라(피드의 버튼, 빈 목록의 안내,
/// 장소 시트의 '이 장소로 글쓰기') 각 자리에서 로그인을 따로 따지면 한 곳을 빠뜨리는 날이
/// 온다 — 그러면 다 쓰고 올리기를 누른 다음에야 벽을 만난다.
///
/// 새 글을 올렸으면 그것을 돌려준다. 부르는 쪽은 목록을 새로 불러오면 된다.
Future<CommunityPost?> writePost(
  BuildContext context, {
  CommunityRepository? repository,
  CommunityBoard? initialBoard,
  String? loc,
  String? contentId,
}) async {
  if (!AuthState.isAuthenticated) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('로그인하면 글을 남길 수 있어요'),
        duration: Duration(milliseconds: 1600),
      ),
    );
    await navigator.push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    // 로그인 화면은 **pop 을 먼저 하고** 그 뒤에 completeLogin() 을 부른다. 여기서
    // 바로 물으면 성공한 로그인도 아직 false 다 — 그러면 다 하고 돌아온 사람에게
    // 아무 일도 안 일어난다.
    await AuthState.settle();

    // 그냥 돌아왔을 수 있다. 그러면 열지 않는다.
    if (!AuthState.isAuthenticated) return null;
    if (!context.mounted) return null;
  }

  if (!context.mounted) return null;
  return Navigator.of(context).push<CommunityPost>(
    MaterialPageRoute(
      builder: (_) => PostWriteScreen(
        repository: repository,
        initialBoard: initialBoard,
        loc: loc,
        contentId: contentId,
      ),
    ),
  );
}

class PostWriteScreen extends StatefulWidget {
  /// 테스트가 가짜 서버를 넣는 자리. 앱에서는 부른 화면이 자기 것을 넘긴다.
  final CommunityRepository? repository;

  /// 처음 골라 둘 게시판. 사용자가 바꿀 수 있다.
  final CommunityBoard? initialBoard;

  /// 장소에서 왔을 때의 표시 이름. `PostInput.loc` 으로 그대로 나간다.
  final String? loc;

  /// 장소에서 왔을 때의 `Place.contentId`. **지도의 진짜 장소일 때만 채워진다.**
  final String? contentId;

  const PostWriteScreen({
    super.key,
    this.repository,
    this.initialBoard,
    this.loc,
    this.contentId,
  });

  @override
  State<PostWriteScreen> createState() => _PostWriteScreenState();
}

class _PostWriteScreenState extends State<PostWriteScreen> {
  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();

  final _title = TextEditingController();
  final _body = TextEditingController();

  /// 처음 고른 값. 장소에서 왔으면 동반장소, 아니면 부른 쪽이 준 것, 그것도 없으면 자유다.
  ///
  /// 미리 고르는 이유는 계약이 `board` 를 required 로 두기 때문이다. 안 고른 상태를
  /// 허용하면 다 쓰고 올리기를 누른 뒤에 "게시판을 골라 주세요" 를 만난다.
  late CommunityBoard _board = widget.contentId != null || widget.loc != null
      ? (widget.initialBoard ?? CommunityBoard.petPlace)
      : (widget.initialBoard ?? CommunityBoard.free);

  bool _sending = false;
  String? _error;

  static const _warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;

    final title = _title.text.trim();
    final body = _body.text.trim();

    // 계약의 required 와 같은 규칙이다. 서버도 @NotBlank 로 막지만, 여기서 막아야
    // 사용자가 올리기를 누르기 전에 안다.
    if (title.isEmpty) {
      setState(() => _error = '제목을 적어 주세요');
      return;
    }
    if (body.isEmpty) {
      setState(() => _error = '본문을 적어 주세요');
      return;
    }

    // 입력칸의 maxLength 로는 부족하다. Flutter 는 **글자(grapheme)** 단위로 자르는데
    // 서버의 @Size 는 자바 String.length() — 즉 **UTF-16 코드 단위**로 센다. 이모지가
    // 섞이면 화면에서는 상한 안인데 서버가 400 을 낸다. 그때 사용자는 다 쓰고 나서야
    // 알게 되고, 무엇을 지워야 하는지도 모른다.
    if (title.length > CommunityRepository.maxTitleLength) {
      setState(() => _error = '제목이 너무 길어요 · 이모지는 여러 글자로 세어져요');
      return;
    }
    if (body.length > CommunityRepository.maxBodyLength) {
      setState(() => _error = '본문이 너무 길어요 · 이모지는 여러 글자로 세어져요');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final post = await _repo.createPost(
        board: _board,
        title: title,
        body: body,
        loc: widget.loc,
        contentId: widget.contentId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(post);
    } on CommunityFailure catch (failure) {
      // 실패를 삼키지 않는다. 사용자는 왜 안 됐는지 알아야 다시 시도할지 정한다.
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  4,
                  18,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                children: [
                  if (widget.loc != null) ...[
                    _placeCard(),
                    const SizedBox(height: 14),
                  ],
                  _label('게시판'),
                  _boardChips(),
                  const SizedBox(height: 18),
                  _label('제목'),
                  TextField(
                    controller: _title,
                    maxLength: CommunityRepository.maxTitleLength,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 15, color: T.textPrimary),
                    decoration: _decoration('한 줄로 말하면 어떤 이야기인가요?'),
                  ),
                  const SizedBox(height: 14),
                  _label('본문'),
                  TextField(
                    controller: _body,
                    maxLength: CommunityRepository.maxBodyLength,
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(
                        fontSize: 14.5, height: 1.55, color: T.textPrimary),
                    decoration: _decoration(
                        '우리 아이와 있었던 일, 다녀온 곳, 궁금한 것을 적어보세요'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFD9534F)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _submitButton(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
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
              child: const Icon(Icons.arrow_back,
                  size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('새 글',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: T.textPrimary)),
        ]),
      );

  /// 장소에서 왔을 때만 뜬다. **바꿀 수 없다** — 어디서 왔는지를 보여 주는 것이지
  /// 장소를 고르는 자리가 아니다. 장소 고르기는 지도의 일이다.
  Widget _placeCard() => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.place_outlined, size: 17, color: Color(0xFFE07A4E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.loc!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: T.textSecondary),
            ),
          ),
          if (widget.contentId != null)
            const Text('장소 연결됨',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: T.textMuted)),
        ]),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: T.textSecondary)),
      );

  /// 게시판 다섯. **'전체' 는 없다** — 그건 목록의 필터이지 글이 올라갈 곳이 아니다.
  Widget _boardChips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final board in CommunityBoard.values)
            GestureDetector(
              onTap: _sending ? null : () => setState(() => _board = board),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  gradient: _board == board ? _warm : null,
                  color: _board == board ? null : const Color(0xCCFFFFFF),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0x66FFFFFF)),
                ),
                child: Text(board.label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _board == board
                            ? Colors.white
                            : T.textSecondary)),
              ),
            ),
        ],
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: T.textMuted),
        filled: true,
        fillColor: const Color(0xCCFFFFFF),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x1F8C7BFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x1F8C7BFF)),
        ),
      );

  Widget _submitButton() => GestureDetector(
        onTap: _sending ? null : _submit,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: _warm,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66FF7E8A),
                  blurRadius: 26,
                  offset: Offset(0, 12)),
            ],
          ),
          // 스피너가 아니라 문구를 바꾼다 — pet_registration_sheet 가 같은 모양이다.
          child: Text(_sending ? '올리는 중…' : '올리기',
              style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      );
}
