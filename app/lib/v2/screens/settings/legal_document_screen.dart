// lib/v2/screens/settings/legal_document_screen.dart
//
// 약관·처리방침 원문을 보여 준다 — 이슈 #165.
//
// ## 정본은 assets 다, 화면에 박힌 문자열이 아니다
//
// `features/profile/.../terms_screen.dart` 가 같은 것을 **하드코딩 템플릿**으로 들고
// 있었다. 그 안의 값이 지금 전부 틀렸다.
//
//     const String kAppName = 'Heat Trip';                  // 지금은 Pawloop 이다
//     const String kContactEmail = 'support@example.com';   // 존재하지 않는 주소
//     const String kCompanyName = 'CetaceaLab';
//
// 진짜 약관은 `assets/terms/*.md` 에 있고 회원가입 화면이 그것을 읽는다
// (`sign_up_screen.dart:438`). **원문이 두 벌이면 어느 쪽이 사용자와 맺은 계약인지
// 말할 수 없다.** 그래서 이 화면은 asset 하나만 읽는다.
//
// 심사자가 보는 것이 이 화면이다 — 거기 적힌 연락처로 실제로 연락이 닿아야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/consent_repository.dart' show ConsentKind;
import '../../theme/app_tokens.dart';

/// 앱이 들고 있는 법적 문서.
///
/// ## 버전이 여기 있는 이유 (이슈 #190)
///
/// 동의는 서버에 **버전과 함께** 남는다. 서버는 문서의 지금 버전을 모르고, 앱이 자기가 든
/// 버전과 서버 기록을 견줘서 재동의를 정한다(ADR-0020). 그래서 지금 버전은 앱 안에 딱 한
/// 곳 — 여기 — 에 있어야 한다.
///
/// 이 값은 문서 파일 머리의 `버전: vX.Y` 와 **같아야 한다.**
/// `legal_document_versions_test.dart` 가 파일을 읽어 견준다. 문서를 고치고 여기를 안
/// 올리면 그 검사가 빨간불이고, 여기를 올리면 이미 동의한 사람 전원이 다음 로그인에
/// 다시 동의 화면을 본다 — 그것이 의도다.
enum LegalDocument {
  terms('이용약관', 'assets/terms/terms_ko.md', ConsentKind.terms, 'v1.3'),
  privacy('개인정보처리방침', 'assets/terms/privacy_ko.md', ConsentKind.privacy, 'v1.11'),

  /// 위치정보법 제18조가 요구하는 문서. **이용약관과 따로 있어야 한다** — 법이
  /// "위치기반서비스 이용약관에 명시하고 동의를 받으라" 고 정하고 있어서, 일반
  /// 이용약관 안에 한 조로 넣으면 그 요건을 채웠다고 말하기 어렵다.
  location('위치기반서비스 이용약관', 'assets/terms/location_ko.md', ConsentKind.location, 'v1.4'),

  marketing('마케팅 정보 수신 동의', 'assets/terms/marketing_ko.md', ConsentKind.marketing, 'v1.0');

  /// 화면 제목이자 `pubspec.yaml` 에 등재된 asset 경로.
  final String title;
  final String assetPath;

  /// 서버에 보내는 문서 이름.
  final ConsentKind kind;

  /// 지금 버전. 파일 머리의 `버전:` 과 같다.
  final String version;

  const LegalDocument(this.title, this.assetPath, this.kind, this.version);
}

class LegalDocumentScreen extends StatefulWidget {
  final LegalDocument document;

  const LegalDocumentScreen({super.key, required this.document});

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  String? _body;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await rootBundle.loadString(widget.document.assetPath);
      if (!mounted) return;
      setState(() => _body = body);
    } catch (_) {
      // 못 읽었다고 빈 화면을 보여 주지 않는다 — 사용자는 약관이 없는 줄 안다.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.document.title),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: T.textPrimary,
      ),
      body: SafeArea(
        child: _failed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '문서를 불러오지 못했어요',
                    style: TextStyle(fontSize: 14, color: T.textSecondary),
                  ),
                ),
              )
            : _body == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    // `SelectableText.rich` 다 — 약관은 **복사할 수 있어야** 한다(신고·문의에
                    // 붙여 넣는다). 굵게만 해석하고 나머지는 글자 그대로다.
                    child: SelectableText.rich(
                      TextSpan(children: boldSpans(_body!)),
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.65,
                        color: T.textPrimary,
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// 마크다운의 `**굵게**` 만 해석한다 — 이슈 #550.
///
/// ## 왜 필요한가
///
/// 문서는 `assets/terms/*.md` 인데 화면은 그대로 글자로 그렸다. 그래서 약관 본문에
/// `별도의 **위치기반서비스 이용약관**에서 정합니다` 처럼 **별표가 그대로** 보였다.
/// 네 문서에서 마흔한 줄이었다.
///
/// **이 화면은 심사에서 열린다.** 애플·구글 심사자가 보는 것이 정확히 이 화면이고,
/// 사용자도 문제가 생겼을 때 여기를 읽는다. 게다가 별표가 붙은 자리는 일부러 강조한
/// 자리라("만 14세 미만", "별도의 위치기반서비스 이용약관"), 강조가 필요해서 붙인 것이
/// 오히려 읽기를 방해하고 있었다.
///
/// ## 왜 마크다운 라이브러리를 안 넣나
///
/// 네 문서가 쓰는 문법이 **굵게와 목록뿐**이다(홑별표 · 머리글 · 표 · 링크가 하나도 없다).
/// 목록(`- `)은 글머리표로 그대로 읽힌다. 의존성을 더할 이유가 없다.
///
/// 짝이 없는 `**` 는 **그대로 둔다** — 지우면 문서가 조용히 달라진다. 그 경우는
/// `legal_document_markdown_test` 가 문서를 읽어 빨간불로 알린다.
List<TextSpan> boldSpans(String source) {
  const bold = TextStyle(fontWeight: FontWeight.w800);
  final out = <TextSpan>[];
  // `at` 은 **아직 안 실은** 자리, `from` 은 찾기 시작할 자리다. 둘을 나눠 두지 않으면
  // 빈 강조를 건너뛸 때 그 앞 글자가 통째로 사라진다(`가****나` → `**나`).
  var at = 0;
  var from = 0;

  while (true) {
    final open = source.indexOf('**', from);
    if (open < 0) break;
    final close = source.indexOf('**', open + 2);
    // 짝이 없다 — 남은 글자를 그대로 싣고 끝낸다.
    if (close < 0) break;
    // `****` 처럼 속이 빈 것은 강조가 아니다. 찾는 자리만 옮기고 글자는 그대로 둔다.
    if (close == open + 2) {
      from = open + 2;
      continue;
    }
    if (open > at) out.add(TextSpan(text: source.substring(at, open)));
    out.add(TextSpan(text: source.substring(open + 2, close), style: bold));
    at = close + 2;
    from = at;
  }

  if (at < source.length) out.add(TextSpan(text: source.substring(at)));
  return out;
}
