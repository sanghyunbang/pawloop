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

import '../../theme/app_tokens.dart';

/// 앱이 들고 있는 법적 문서.
enum LegalDocument {
  terms('이용약관', 'assets/terms/terms_ko.md'),
  privacy('개인정보처리방침', 'assets/terms/privacy_ko.md'),

  /// 위치정보법 제18조가 요구하는 문서. **이용약관과 따로 있어야 한다** — 법이
  /// "위치기반서비스 이용약관에 명시하고 동의를 받으라" 고 정하고 있어서, 일반
  /// 이용약관 안에 한 조로 넣으면 그 요건을 채웠다고 말하기 어렵다.
  location('위치기반서비스 이용약관', 'assets/terms/location_ko.md'),

  marketing('마케팅 정보 수신 동의', 'assets/terms/marketing_ko.md');

  /// 화면 제목이자 `pubspec.yaml` 에 등재된 asset 경로.
  final String title;
  final String assetPath;

  const LegalDocument(this.title, this.assetPath);
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
                    child: SelectableText(
                      _body!,
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
