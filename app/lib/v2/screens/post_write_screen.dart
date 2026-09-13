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

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/community_repository.dart';
import '../data/course_repository.dart';
import '../data/location_upload_policy.dart';
import '../data/image_prep.dart';
import '../data/media_picker.dart';
import '../data/post_media_repository.dart';
import '../widgets/course_picker_sheet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/post_media_field.dart';
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

/// 글 고치기를 여는 문 — 이슈 #243.
///
/// **로그인을 다시 안 묻는다.** 고칠 글이 있다는 것은 이미 로그인했다는 뜻이고, 내 글인지는
/// 부르는 쪽이 이미 `_isMine` 으로 가렸다. 진짜 판정은 서버가 403 으로 한다.
///
/// 고쳐진 글을 돌려준다. 부르는 쪽은 그것으로 화면을 다시 그리면 된다. **안 고치고
/// 나왔으면 `null`** 이다 — 그때는 아무것도 안 바뀌었으므로 다시 그릴 이유도 없다.
Future<CommunityPost?> editPost(
  BuildContext context,
  CommunityPost post, {
  CommunityRepository? repository,
}) {
  return Navigator.of(context).push<CommunityPost>(
    MaterialPageRoute(
      builder: (_) => PostWriteScreen(repository: repository, editing: post),
    ),
  );
}

class PostWriteScreen extends StatefulWidget {
  /// 테스트가 가짜 서버를 넣는 자리. 앱에서는 부른 화면이 자기 것을 넘긴다.
  final CommunityRepository? repository;

  /// 코스 저장소. 테스트가 꽂는 자리다 (#339).
  final CourseRepository? courses;

  /// 처음 골라 둘 게시판. 사용자가 바꿀 수 있다.
  final CommunityBoard? initialBoard;

  /// 장소에서 왔을 때의 표시 이름. `PostInput.loc` 으로 그대로 나간다.
  final String? loc;

  /// 장소에서 왔을 때의 `Place.contentId`. **지도의 진짜 장소일 때만 채워진다.**
  final String? contentId;

  /// 고칠 글 — 이슈 #243. `null` 이면 새 글이다.
  ///
  /// **`loc`·`contentId` 는 편집에서 못 바꾼다.** 계약이 `PostPatch` 에서 그 둘을 뺐다 —
  /// 비우기와 안 바꿈을 구별할 방법이 아직 없어서다. 화면은 그것을 <b>읽기 전용으로
  /// 보여만 준다</b>(장소 카드).
  final CommunityPost? editing;

  /// 사진 업로드 저장소 (#429). 테스트가 `MockClient` 를 꽂은 것을 넘긴다.
  final PostMediaRepository? media;

  /// 사진 고르기 (#429). 테스트가 가짜를 꽂는 자리 — 위젯 테스트에는 갤러리가 없다.
  final MediaPicker? picker;

  /// 사진 다시 인코딩 (#429). 기본은 격리 스레드의 `ImagePrep.prepare` — 위젯 테스트는 격리
  /// 스레드의 결과를 못 받으므로(`FakeAsync`) 같은 일을 하는 동기 버전을 꽂는다.
  final ImagePreparer? prepare;

  const PostWriteScreen({
    super.key,
    this.repository,
    this.courses,
    this.initialBoard,
    this.loc,
    this.contentId,
    this.editing,
    this.media,
    this.picker,
    this.prepare,
  });

  bool get isEditing => editing != null;

  @override
  State<PostWriteScreen> createState() => _PostWriteScreenState();
}

class _PostWriteScreenState extends State<PostWriteScreen> {
  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();

  late final _title = TextEditingController(text: widget.editing?.title ?? '');
  late final _body = TextEditingController(text: widget.editing?.body ?? '');

  /// 처음 고른 값. 장소에서 왔으면 동반장소, 아니면 부른 쪽이 준 것, 그것도 없으면 자유다.
  ///
  /// 미리 고르는 이유는 계약이 `board` 를 required 로 두기 때문이다. 안 고른 상태를
  /// 허용하면 다 쓰고 올리기를 누른 뒤에 "게시판을 골라 주세요" 를 만난다.
  late CommunityBoard _board = widget.editing?.board ??
      (widget.contentId != null || widget.loc != null
          ? (widget.initialBoard ?? CommunityBoard.petPlace)
          : (widget.initialBoard ?? CommunityBoard.free));

  /// 붙일 코스 (#339). 산책로 후기에서만 고를 수 있다 — 다른 게시판에 경로를 붙이는 것은
  /// 뜻이 흐리다. 고쳐 쓰는 글에서는 이미 붙어 있는 것을 그대로 둔다(붙이기·떼기는
  /// 별도 오퍼레이션이라 이 화면의 저장과 섞지 않는다).
  Course? _course;

  late final PostMediaRepository _media = widget.media ?? PostMediaRepository();
  late final MediaPicker _picker = widget.picker ?? ImagePickerMediaPicker();

  /// 붙일 사진 (#429). 고쳐 쓰는 글은 이미 붙어 있던 것으로 시작한다.
  late PostMediaSelection _mediaSel = PostMediaSelection(
    ids: [for (final m in widget.editing?.media ?? const []) m.id],
    busy: false,
    hasFailure: false,
  );

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

  /// 장소 이름. 새 글이면 부른 쪽이 준 것, 편집이면 <b>글에 이미 붙어 있는 것</b>이다.
  ///
  /// 편집에서도 보여 주는 이유는 그 글이 어느 장소의 글인지가 맥락이기 때문이다.
  /// <b>바꿀 수는 없다</b> — 계약이 `PostPatch` 에서 `loc`·`contentId` 를 뺐다.
  String? get _placeName => widget.editing?.loc ?? widget.loc;

  String get _submitLabel {
    if (_sending) return widget.isEditing ? '고치는 중…' : '올리는 중…';
    return widget.isEditing ? '고치기' : '올리기';
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
    // 사진이 아직 올라가는 중이면 id 가 없다. 그대로 보내면 사진 없는 글이 조용히 올라간다.
    if (_mediaSel.busy) {
      setState(() => _error = '사진을 올리는 중이에요 · 잠시만요');
      return;
    }
    if (_mediaSel.hasFailure) {
      setState(() => _error = '못 올린 사진이 있어요 · 다시 올리거나 떼 주세요');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final post = widget.isEditing
          ? await _saveEdit(title, body)
          : await _repo.createPost(
              courseId: _board == CommunityBoard.walkReview ? _course?.id : null,
              board: _board,
              title: title,
              body: body,
              loc: widget.loc,
              contentId: widget.contentId,
              mediaIds: _mediaSel.ids,
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

  /// 고친 것만 보낸다 — 이슈 #243.
  ///
  /// **안 바뀐 키는 안 싣는다.** 계약이 `PostPatch` 를 `minProperties: 1` 로 두었고,
  /// 다 실으면 그 사이 다른 기기에서 고친 값을 조용히 되돌린다(ADR-0017 규약 4).
  ///
  /// **하나도 안 고쳤으면 요청을 안 보내고 `null` 을 돌려준다.** 서버가 400 을 주는데,
  /// 그건 사용자가 볼 이유가 없는 실패다 — 아무것도 안 고친 것은 잘못이 아니다.
  /// 부르는 쪽은 `null` 을 "바뀐 것 없음" 으로 읽어 다시 그리지 않는다.
  Future<CommunityPost?> _saveEdit(String title, String body) {
    final original = widget.editing!;
    // 사진은 목록이 달라졌을 때만 싣는다 — 안 실으면 안 바뀌고, 실으면 통째로 갈아 끼운다.
    final originalIds = [for (final m in original.media) m.id];
    final mediaChanged = !listEquals(originalIds, _mediaSel.ids);
    return _repo.updatePost(
      original.id,
      mediaIds: mediaChanged ? _mediaSel.ids : null,
      board: _board == original.board ? null : _board,
      title: title == original.title ? null : title,
      body: body == original.body ? null : body,
    );
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
                  _visibilityNotice(),
                  if (_placeName != null) ...[
                    _placeCard(),
                    const SizedBox(height: 14),
                  ],
                  _label('게시판'),
                  _boardChips(),
                  // 산책로 후기에만 붙인다 — 다른 게시판에 경로는 뜻이 흐리다(#339).
                  if (_board == CommunityBoard.walkReview &&
                      LocationUploadPolicy.sharesRoutes) ...[
                    const SizedBox(height: 12),
                    _courseRow(),
                  ],
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
                  const SizedBox(height: 14),
                  // 고르는 순간 올라가기 시작한다. 글을 저장할 때는 올라간 id 만 싣는다 (#429).
                  PostMediaField(
                    repository: _media,
                    picker: _picker,
                    initial: widget.editing?.media ?? const [],
                    prepare: widget.prepare ?? ImagePrep.prepare,
                    onChanged: (sel) => setState(() => _mediaSel = sel),
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
          Text(widget.isEditing ? '글 고치기' : '새 글',
              style: const TextStyle(
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
              _placeName!,
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


  /// 이 화면에서 쓴 것이 <b>어디까지 보이는지</b> 한 줄로 — 이슈 #253.
  ///
  /// ## 왜 창이 아니라 상시 고지인가
  ///
  /// 동의는 이미 받았다. 로그인한 사람은 예외 없이 `ConsentScreen` 을 지나고
  /// (`auth_redirect.dart` 가 다른 어떤 규칙보다 먼저 붙잡는다), 이용약관 제7조4가
  /// 공개 범위를 적는다. 여기서 창을 하나 더 띄우면 **같은 사람에게 두 번 묻는 것**이다.
  ///
  /// 대신 사실이 일어나는 자리에서 매번 말한다. 동의 창은 한 번 누르면 두 번째 글부터
  /// 아무 말도 안 하는데, 게시물이 게스트에게도 보인다는 것은 **쓸 때마다** 알아야 하는
  /// 사실이다.
  Widget _visibilityNotice() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Text(
        '여기 쓴 글과 댓글은 로그인하지 않은 사람에게도 보여요. 닉네임이 함께 표시되고, 탈퇴해도 글은 남아요.',
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: T.textMuted,
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: T.textSecondary)),
      );

  /// 게시판 다섯. **'전체' 는 없다** — 그건 목록의 필터이지 글이 올라갈 곳이 아니다.
  /// 산책로 후기일 때만 나오는 줄. 고른 코스가 있으면 이름과 거리를, 없으면 권유를 보여 준다.
  Widget _courseRow() {
    final course = _course;
    return GestureDetector(
      onTap: _pickCourse,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x1F8C7BFF)),
        ),
        child: Row(children: [
          const Icon(Icons.route_rounded, size: 17, color: Color(0xFFE07A4E)),
          const SizedBox(width: 10),
          Expanded(
            child: course == null
                ? const Text('내 코스 붙이기 — 걸었던 길을 함께 보여 줘요',
                    style: TextStyle(fontSize: 13.5, color: T.textSecondary))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(course.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                    const SizedBox(height: 2),
                    Text('${course.km.toStringAsFixed(2)}km · 공개',
                        style: const TextStyle(fontSize: 12, color: T.textMuted)),
                  ]),
          ),
          if (course != null)
            GestureDetector(
              onTap: () => setState(() => _course = null),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('빼기',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textMuted)),
              ),
            )
          else
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBB3CC)),
        ]),
      ),
    );
  }

  Future<void> _pickCourse() async {
    final picked = await CoursePickerSheet.open(context, courses: widget.courses);
    if (picked == null || !mounted) return;
    setState(() => _course = picked);
  }

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
          child: Text(_submitLabel,
              style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      );
}
