// lib/v2/screens/consent_screen.dart
//
// 로그인한 계정에게 처음 한 번 받는 동의 — 이슈 #180.
//
// ## 왜 만들었나
//
// v2 에는 동의를 받는 자리가 **하나도 없었다.** 로그인은 카카오·구글뿐이고 그 흐름에
// 약관을 보여 주는 화면이 없다. 동의 체크박스가 있는 회원가입 화면은
// `features/auth/presentation/sign_up_screen.dart` 인데 v2 에서 그리로 가는 길이 없다
// (#184). 즉 이 앱은 아무 동의 없이 위치를 수집하고 있었다.
//
// ## 왜 위치를 필수로 두는가
//
// 산책 기록이 이 앱의 본체다. 위치 없이 남는 것은 손입력 거리·시간뿐이고, 그건
// "포루프를 쓴다" 고 하기 어렵다. 선택으로 두면 화면마다 "위치 동의를 안 한 사람" 분기가
// 생기고, 그 분기를 한 곳만 빠뜨려도 **동의 없이 좌표가 나간다.**
//
// 대신 **일시 중단은 언제든 켤 수 있다**(프로필 화면). 위치정보법 제24조가 요구하는
// 것이 그 기능이고, 그것이 실제로 동작한다(#185).
//
// ## 왜 회원가입이 아니라 여기인가
//
// 소셜 로그인은 우리가 만드는 화면이 아니다. 카카오·구글 화면 중간에 우리 약관을 끼워
// 넣을 수 없다. 그래서 **돌아온 직후, 앱을 쓰기 전**이 우리가 가질 수 있는 가장 이른
// 자리다.
//
// ## 왜 만 14세를 여기서 묻는가 (#682)
//
// **개인정보 보호법 제22조의2 제1항** — 만 14세 미만 아동의 개인정보를 처리하려면
// 법정대리인의 동의를 받아야 한다. 우리에게는 법정대리인 동의를 받을 장치가 없다.
// 그러면 남는 답은 하나다. **만 14세 이상만 받는다.**
//
// 묻는 자리가 여기여야 하는 이유도 위와 같다. 나이를 묻는 회원가입 화면
// (`features/auth/presentation/sign_up_screen.dart`)은 v2 에서 그리로 가는 길이 없어서
// (#184) 모든 계정의 `age_group` 이 NULL 이다. 그래서 처리방침 10항이 "가입 시 만 14세
// 미만 여부를 확인한다" 고 적고 있는데도 **아무도 확인받은 적이 없었다.** 처리방침이
// 거짓말을 하지 않게 만드는 것이 이 줄이다.
//
// 자기 신고다 — 우리는 주민등록번호도 본인확인도 받지 않으므로 이 이상은 확인할 수
// 없다. 그래도 "만 14세 미만은 쓸 수 없는 서비스" 라고 **말하고 받은 답**이 남는다는
// 점이 아무것도 안 묻는 것과 다르다.
//
// ## 왜 "[필수]" 가 아니라 "동의 필수" 인가 (#682)
//
// 소개 끝에 나오는 접근권한 안내(`settings/permission_notice_screen.dart`)도 항목을
// 필수와 선택으로 나눈다. 거기서는 **위치가 선택**이다 — 권한을 거부해도 앱이 돌기
// 때문이다. 그런데 여기서는 위치기반서비스 이용약관이 필수다. 사장님이 실기기에서
// 그 둘을 나란히 보고 "위치는 다 선택인 것처럼 하더니 여기선 왜 또 필수냐" 고 물었다.
//
// 둘은 다른 것이다. 앞은 **기기의 기능을 켜는 허용**이고 여기는 **서비스를 쓰기 위한
// 동의**다. 방송통신위원회 안내서도 <주의> 상자로 "접근권한에 대한 동의는 해당 정보에
// 대한 수집 동의는 아니" 라고 갈라 놨다. 다만 갈라 놓은 것을 화면이 말해 주지 않으면
// 읽는 사람에게는 모순으로 남는다. 그래서 세 가지를 했다:
//
//  1. 꼬리표를 "동의 필수 / 동의 선택" 으로 바꿔 같은 두 글자가 두 화면에 따로 놀지
//     않게 했다(접근권한 화면은 "필수적 / 선택적 접근권한" 을 쓴다).
//  2. 첫머리에 [ConsentScreen.screenBoundaryNote] 로 앞 화면과 별개라고 적었다.
//  3. 위치기반서비스 줄 아래에 [ConsentScreen.locationPermissionNote] 를 붙여, 약관에
//     동의해도 권한은 따로 묻고 거부해도 앱을 쓸 수 있다고 적었다.
//
// **위치기반서비스 약관을 선택으로 내리지는 않았다.** 그건 따로 판단할 일이다.
library;

import 'package:flutter/material.dart';

import '../data/consent_gate.dart';
import '../data/location_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import 'settings/legal_document_screen.dart';
import 'settings/permission_notice_screen.dart';

class ConsentScreen extends StatefulWidget {
  final int userId;

  /// 동의가 끝났을 때. 라우터가 다음 자리로 보낸다.
  final VoidCallback onAgreed;

  /// **테스트만 넘긴다.**
  final ConsentGate? gate;

  const ConsentScreen({
    super.key,
    required this.userId,
    required this.onAgreed,
    this.gate,
  });

  /// 이 화면이 앞 화면과 무엇이 다른지. (#682)
  ///
  /// 소개 끝에 나오는 [PermissionNoticeScreen] 도 항목을 필수와 선택으로 나눈다. 거기서
  /// 말하는 필수/선택은 **기기 권한**이고 여기 것은 **약관 동의**다. 같은 두 글자가 뜻이
  /// 달라서 "아까는 위치가 선택이라더니 여기선 왜 필수냐" 로 읽혔다. 그래서 이 화면은
  /// 꼬리표를 "동의 필수 / 동의 선택" 으로 쓰고, 경계를 이 한 줄로 적는다.
  static const String screenBoundaryNote =
      '앞에서 본 ‘${PermissionNoticeScreen.menuLabel}’ 와는 별개예요. '
      '여기는 서비스를 쓰기 위한 동의예요.';

  /// 위치기반서비스 이용약관 줄에 붙는 한 줄. (#682)
  ///
  /// 짝이 되는 문장은 [kLocationIsNotTheTerms] 다 — 저쪽은 권한 화면에서 "약관과 별개" 라
  /// 말하고, 이쪽은 동의 화면에서 "권한은 따로 묻는다" 고 말한다. 한쪽만 고치면 다시
  /// 어긋나므로 두 문장 다 검사가 붙들고 있다.
  ///
  /// **이 줄은 약속이다.** 약관에 동의해도 위치 권한 대화상자는 따로 뜨고(권한을 여는
  /// 것은 OS 다), 거부해도 앱은 돈다 — 라우터가 위치 권한을 보지 않는다.
  static const String locationPermissionNote = '약관에 동의해도 기기의 위치 권한은 앱에서 '
      '따로 물어봐요. 거부해도 앱을 쓸 수 있고, 산책 경로 기록과 주변 찾기만 못 해요.';

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  late final ConsentGate _gate = widget.gate ?? const ConsentGate();

  /// 만 14세 이상이라는 **자기 신고**다(#682). 개인정보 보호법 제22조의2 가 만 14세
  /// 미만이면 법정대리인 동의를 요구하는데 우리에겐 그 장치가 없다 — 그래서 문서 동의가
  /// 아니라 가입 자격이고, [LegalDocument] 가 없어 전문 보기도 없다.
  bool _age = false;

  bool _terms = false;
  bool _privacy = false;
  bool _location = false;
  bool _marketing = false;
  bool _sending = false;

  bool get _allRequired => _age && _terms && _privacy && _location;
  bool get _allChecked => _allRequired && _marketing;

  void _toggleAll(bool next) => setState(() {
        _age = next;
        _terms = next;
        _privacy = next;
        _location = next;
        _marketing = next;
      });

  Future<void> _agree() async {
    if (!_allRequired || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);

    final ok = await _gate.markAgreed(widget.userId, marketing: _marketing);
    if (!mounted) return;
    if (!ok) {
      // 삼키지 않는다 — 넘어가 버리면 다음 실행에 또 뜨고, 사용자는 "동의했는데 왜
      // 또 묻지" 를 겪는다.
      setState(() => _sending = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('동의를 저장하지 못했어요. 다시 시도해 주세요'),
        duration: Duration(milliseconds: 2000),
      ));
      return;
    }
    // 좌표를 얻는 길을 연다. 이 한 줄이 없으면 동의를 마치고도 산책이 안 시작된다.
    LocationService.consented.value = true;
    widget.onAgreed();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 뒤로 나갈 수 없다. 나가면 동의 없이 앱을 쓰게 된다 — 라우터가 다시 여기로
      // 보내겠지만, 그 한 프레임 사이에 화면이 깜빡인다.
      canPop: false,
      child: Scaffold(
        backgroundColor: T.bgTop,
        body: AuroraBackground(
          child: SafeArea(
            child: Column(children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  children: [
                    const Text('서비스 이용에 동의해 주세요',
                        style: TextStyle(
                            fontSize: 22,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                            color: T.textPrimary)),
                    const SizedBox(height: 10),
                    // 좌표가 **기기 밖으로 안 나간다**는 것을 여기서 말한다. 예전에는 "위치 수집" 이라고만
                    // 적어서 서버로 보낸다는 뜻으로 읽혔다 — 실제로는 LocationUploadPolicy 가 막고 있어
                    // 산책을 저장해도 `path` 키가 요청에서 빠진다(#235 · UPLOAD_LOCATION 기본 false).
                    // 위치기반서비스사업 신고를 마치고 그 값을 켜는 날 이 문장도 함께 고친다.
                    //
                    // "멈출 수 있어요" 는 사실이다 — me_screen 의 '위치 정보 수집 일시 중단' 토글이
                    // LocationService.setPaused 로 디스크에 남긴다.
                    const Text(
                      '포루프는 산책 경로를 기록하기 위해 위치를 사용해요.\n'
                      '경로는 기기 안에만 남고 서버로 보내지 않아요.\n'
                      '위치 이용은 프로필에서 언제든 멈출 수 있어요.',
                      style: TextStyle(fontSize: 13.5, height: 1.6, color: T.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    // 위 문단과 따로 둔다 — 위 문단은 #653 이 실제 동작과 견주는 약속이라
                    // 문장을 섞지 않는다.
                    const Text(ConsentScreen.screenBoundaryNote,
                        style: TextStyle(fontSize: 12.5, height: 1.6, color: T.textMuted)),
                    const SizedBox(height: 22),
                    _allRow(),
                    const SizedBox(height: 10),
                    _card([
                      // 맨 위다 — 나머지 셋은 "이 서비스를 쓸 수 있는 사람" 에게 묻는
                      // 것이고, 이 줄이 그 자격을 정한다(#682).
                      _row('만 14세 이상입니다',
                          required_: true,
                          value: _age,
                          onChanged: (v) => setState(() => _age = v)),
                      _divider(),
                      _row('이용약관',
                          required_: true,
                          value: _terms,
                          onChanged: (v) => setState(() => _terms = v),
                          doc: LegalDocument.terms),
                      _divider(),
                      _row('개인정보처리방침',
                          required_: true,
                          value: _privacy,
                          onChanged: (v) => setState(() => _privacy = v),
                          doc: LegalDocument.privacy),
                      _divider(),
                      _row('위치기반서비스 이용약관',
                          required_: true,
                          value: _location,
                          onChanged: (v) => setState(() => _location = v),
                          doc: LegalDocument.location,
                          // 사장님이 걸린 자리다 — 앞 화면에서 위치가 선택이었는데
                          // 여기서 필수라 모순으로 읽혔다. 둘은 다른 것이다(#682).
                          note: ConsentScreen.locationPermissionNote),
                      _divider(),
                      _row('마케팅 정보 수신',
                          required_: false,
                          value: _marketing,
                          onChanged: (v) => setState(() => _marketing = v),
                          doc: LegalDocument.marketing),
                    ]),
                    const SizedBox(height: 14),
                    // "각 항목" 이 아니다 — 만 14세 줄에는 읽을 전문이 없어 화살표도
                    // 없다(#682). 이 화면의 안내문은 약속이라 사실만 적는다.
                    const Text('약관 항목의 화살표를 눌러 전문을 읽을 수 있어요.',
                        style: TextStyle(fontSize: 12, color: T.textMuted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: GestureDetector(
                  onTap: _agree,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // 필수를 다 안 채웠으면 회색이다. 켜 두고 눌렀을 때 막으면
                      // 사용자는 무엇이 모자란지 모른 채 다시 누른다.
                      gradient: _allRequired && !_sending
                          ? const LinearGradient(
                              begin: Alignment(-0.8, -1),
                              end: Alignment(0.8, 1),
                              colors: [T.warmStart, T.warmEnd],
                            )
                          : null,
                      color: _allRequired && !_sending ? null : const Color(0x33463C64),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _sending ? '저장 중…' : '동의하고 시작하기',
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _allRow() => GestureDetector(
        onTap: () => _toggleAll(!_allChecked),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.radius),
            border: Border.all(
                color: _allChecked ? T.warmMid : T.surface),
          ),
          child: Row(children: [
            _check(_allChecked),
            const SizedBox(width: 12),
            const Text('전체 동의 (선택 항목 포함)',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ]),
        ),
      );

  Widget _card(List<Widget> children) => ClipRRect(
        borderRadius: BorderRadius.circular(T.radius),
        child: GlassCard(padding: EdgeInsets.zero, child: Column(children: children)),
      );

  Widget _divider() => Container(height: 1, color: T.accentSoft);

  /// 한 줄. [doc] 이 없으면 읽을 전문이 없는 항목이다(만 14세 자기 신고 — #682).
  /// 그때도 **자리는 비워 둔다** — 화살표만 빼고 폭을 그대로 남겨서 체크·글자가 위아래
  /// 줄과 같은 선에 선다.
  Widget _row(
    String label, {
    required bool required_,
    required bool value,
    required ValueChanged<bool> onChanged,
    LegalDocument? doc,
    String? note,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(!value),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(top: 14, bottom: note == null ? 14 : 8),
                  child: Row(children: [
                    _check(value),
                    const SizedBox(width: 12),
                    // "[필수]" 가 아니라 "동의 필수" 다 — 접근권한 화면이 같은 두 글자를
                    // 기기 권한이라는 다른 뜻으로 쓴다(#682).
                    Text(required_ ? '동의 필수 ' : '동의 선택 ',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: required_ ? T.warmText : T.textMuted)),
                    Flexible(
                      child: Text(label,
                          style: const TextStyle(fontSize: 14, color: T.textPrimary)),
                    ),
                  ]),
                ),
              ),
            ),
            // 전문 보기. 동의를 받으려면 읽을 길이 있어야 한다 — 읽을 수 없는 동의는
            // 동의가 아니다.
            if (doc != null)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen(document: doc),
                )),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                  child: Icon(Icons.chevron_right, size: 20, color: T.textMuted),
                ),
              )
            else
              // 화살표(20) + 좌우 여백(4+4). 안 비워 두면 이 줄만 오른쪽으로 넓어진다.
              const SizedBox(width: 28),
          ]),
          // 한 줄 더 할 말이 있는 항목. 체크 글자와 같은 선에서 시작하게 왼쪽을 34 만큼
          // 민다(체크 22 + 사이 12).
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 0, 4, 13),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(note,
                    style: const TextStyle(
                        fontSize: 12, height: 1.5, color: T.textMuted)),
              ),
            ),
        ]),
      );

  Widget _check(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? T.warmMid : Colors.transparent,
          // 미체크는 빈 원이다 — 회색 바탕에 흰 체크는 "이미 체크된 비활성" 처럼 읽혔다(#325).
          border: on ? null : Border.all(color: const Color(0x66463C64), width: 1.6),
        ),
        child: on ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
      );
}
