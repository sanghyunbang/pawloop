// lib/v2/screens/display_name_screen.dart
//
// 표시 이름 바꾸기 — 이슈 #665.
//
// ## 없던 화면이다
//
// 서버는 `PUT /auth/me` 로 닉네임을 받을 준비가 돼 있었는데 앱에 들어갈 문이 없었다. 옛
// 편집 폼은 레거시 셸과 함께 지웠고(#94) v2 에 대체가 안 생겼다. 그래서 소셜로 가입한
// 사람은 **공급자가 준 이름**(카카오 닉네임)을 그대로 쓸 수밖에 없었다.
//
// ## 이 화면이 바꾸는 것은 하나다
//
// `nickname` 하나만 바꾼다. 서버에는 `name` 도 있지만 앱이 화면에 그리는 값은 닉네임
// 하나라, 둘을 나란히 놓으면 "이름과 별명이 뭐가 다른가" 를 사람이 정해야 하는데 답이 없다.
// 성별·나이·여행타입은 여행온 시절의 칸이라 #648 과 함께 볼 것들이고, 프로필 사진은 업로드
// 배선이 따로다(#430·#431).
//
// ## 두 가지를 반드시 지킨다
//
//  1. **저장이 실패하면 안 닫는다.** 바뀐 줄 알고 나가면, 사용자는 옛 이름으로 글을 쓰면서
//     자기가 새 이름이라고 믿는다.
//  2. **빈 이름은 안 보낸다.** 서버는 빈 닉네임을 "안 바꿈" 으로 읽고 200 을 주므로,
//     보내면 아무것도 안 바뀌었는데 화면이 "바꿨어요" 라고 말한다([ProfileStore] 참조).
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/profile_store.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

class DisplayNameScreen extends StatefulWidget {
  /// 테스트가 가짜 서버를 꽂는 자리. 운영 경로에서는 null 이다(#332 와 같은 방식).
  final ProfileStore? store;

  const DisplayNameScreen({super.key, this.store});

  @override
  State<DisplayNameScreen> createState() => _DisplayNameScreenState();
}

class _DisplayNameScreenState extends State<DisplayNameScreen> {
  /// 오류 문구·오류 테두리 색. 이 화면의 코랄은 "눌러라" 가 아니라 "여기가 틀렸다" 다.
  static const _coral = Color(0xFFD9401F);

  late final ProfileStore _store = widget.store ?? ProfileStore();
  late final TextEditingController _name;

  /// 저장 왕복 중. 두 번 눌러 두 번 보내는 것을 막는다.
  bool _saving = false;

  /// 방금 실패한 이유. 성공하면 화면이 닫히므로 이 값이 남는 경우는 실패뿐이다.
  String? _error;

  /// 입력칸에 실제로 들어 있는 이름(앞뒤 공백 없음).
  String get _typed => _name.text.trim();

  @override
  void initState() {
    super.initState();
    // 빈 칸에서 시작하지 않는다 — 지금 이름을 보여 줘야 "무엇을 바꾸는가" 가 보인다.
    _name = TextEditingController(text: AuthState.user?.nickname ?? '');
    _name.addListener(_onTyped);
  }

  /// 글자 수와 버튼 상태를 다시 그리고, 옛 실패 문구는 치운다 — 남겨 두면 방금 고친
  /// 이름까지 틀린 것처럼 보인다.
  void _onTyped() => setState(() => _error = null);

  @override
  void dispose() {
    _name.removeListener(_onTyped);
    _name.dispose();
    super.dispose();
  }

  /// 저장. **성공했을 때만 닫는다.**
  Future<void> _save() async {
    if (_saving) return;
    if (_typed.isEmpty) {
      // 이유를 말한다. 아무 일도 안 일어나면 사용자는 버튼이 고장 난 줄 안다.
      setState(() => _error = ProfileStore.emptyNameReason);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await _store.saveNickname(_typed);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _saving = false;
        _error = result.reason;
      });
      return;
    }

    // 서버가 돌려준 나로 갈아 끼운다 — 프로필과 홈이 즉시 새 이름을 그린다.
    final applied = AuthState.applyUpdatedUser(result.user ?? const {});

    // messenger 와 navigator 는 await 뒤에 `context` 로 찾지 않는다(#63 과 같은 자리).
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.showSnackBar(SnackBar(
      // 200 을 받았는데 본문이 계약과 다르면 저장은 된 것이고 앱의 사본만 낡은 것이다.
      // 그 차이를 삼키면 화면이 거짓말을 한다.
      content: Text(applied ? '표시 이름을 바꿨어요' : '저장했어요 · 새 이름은 잠시 뒤에 보여요'),
      duration: const Duration(milliseconds: 1800),
    ));
    navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                children: [
                  const SizedBox(height: 6),
                  _field(),
                  const SizedBox(height: 10),
                  if (_error != null) _errorLine(_error!),
                  const SizedBox(height: 14),
                  _snapshotNote(),
                  const SizedBox(height: 26),
                  _saveButton(),
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
                color: T.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: T.cardBorder),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            '내 정보 수정',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: T.textPrimary,
            ),
          ),
        ]),
      );

  Widget _field() {
    final used = _name.text.characters.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '표시 이름',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: T.textSecondary,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '$used/${ProfileStore.maxNicknameLength}',
          style: const TextStyle(fontSize: 12, color: T.textMuted),
        ),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _error == null ? T.accentLine : _coral),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          key: const Key('display-name-field'),
          controller: _name,
          enabled: !_saving,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          // 앱이 **먼저** 막는다. 정본은 서버의 `User.MAX_NICKNAME_LENGTH` 이고(#229),
          // 그래도 넘어간 값은 서버가 400 과 함께 이유를 돌려준다.
          maxLength: ProfileStore.maxNicknameLength,
          style: const TextStyle(fontSize: 15, color: T.textPrimary),
          decoration: const InputDecoration(
            hintText: '다른 사람에게 보일 이름',
            hintStyle: TextStyle(fontSize: 15, color: T.textMuted),
            border: InputBorder.none,
            isDense: true,
            counterText: '', // 글자 수는 위 라벨 줄에 이미 있다.
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    ]);
  }

  Widget _errorLine(String message) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, size: 15, color: _coral),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: _coral),
            ),
          ),
        ]),
      );

  /// 바꿔도 안 바뀌는 것을 **미리** 말한다.
  ///
  /// `post.handle` 과 `chat_message.sender_name` 은 글을 쓰던 때의 이름을 찍어 두는
  /// 자리다(스냅샷). 그게 맞는 설계지만, 이름을 바꾼 사람은 옛 글까지 바뀔 것이라고
  /// 생각하기 쉽다. 바꾼 뒤에 알게 되면 "안 바뀌었다" 로 읽힌다.
  Widget _snapshotNote() => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: T.cardBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Icon(Icons.history_edu_outlined, size: 16, color: T.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '이미 쓴 글과 보낸 채팅에는 그때 이름이 그대로 남아요. '
              '새 이름은 지금부터 쓰는 곳에 보여요.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: T.textMuted),
            ),
          ),
        ]),
      );

  /// 저장 버튼.
  ///
  /// 빈 이름일 때 **눌리지 않게 만들지 않는다.** 눌러서 이유를 듣는 편이, 왜 안 눌리는지
  /// 모른 채 버튼을 두드리는 것보다 낫다. 대신 흐리게 그려서 지금은 보낼 수 없다는 것을 보인다.
  Widget _saveButton() {
    final ready = _typed.isNotEmpty && !_saving;
    return GestureDetector(
      key: const Key('display-name-save'),
      onTap: _save,
      child: Opacity(
        opacity: ready ? 1 : 0.55,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: T.sig,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: T.sigGlow, blurRadius: 24, offset: Offset(0, 12)),
            ],
          ),
          child: Text(
            _saving ? '저장 중…' : '저장',
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
