import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../screens/settings/legal_document_screen.dart' show LegalDocument;
import 'consent_repository.dart';

/// 계정 동의 — 이용약관 · 개인정보처리방침 · 위치기반서비스 · 마케팅(선택). 이슈 #180 · #190.
///
/// ## 왜 필요한가
///
/// 위치정보법이 요구하는 것은 두 가지다.
///
///  - 제15조 — 동의 없이 개인위치정보를 수집·이용·제공하면 3년 이하 징역 또는
///    3천만원 이하 벌금
///  - 제18조·제19조 — **위치기반서비스 이용약관에 명시하고 동의를 받아야 한다.**
///
/// 그리고 그 동의를 **받았다는 사실을 다투게 되는 상황**을 전제한다. 기기 안의 불리언은
/// 그 증빙이 아니다.
///
/// ## 서버가 정본이고 기기는 캐시다 (ADR-0020)
///
/// 동의는 `PUT /api/consents` 로 서버에 남긴다 — 문서마다 **버전과 함께**. 그래서 기기를
/// 바꿔도 다시 안 묻고, 약관이 바뀌면 다시 묻는다.
///
/// 읽을 때는 서버를 먼저 본다. 서버를 못 부르면 기기 캐시를 쓰되, **캐시에도 없으면
/// 동의 화면을 띄운다.** 그 방향의 실수(한 번 더 묻기)가 반대(동의 없이 진행)보다 낫다.
///
/// 적을 때 서버가 안 받아 주면 **넘어가지 않는다.** 기기에만 적고 넘어가면 서버는 여전히
/// 모르는 채이고, 그게 바로 이 이슈가 없애려던 상태다. 화면이 다시 시도하게 한다.
///
/// ## 재동의는 여기서 정한다
///
/// 서버는 문서의 지금 버전을 모른다. 문서는 앱이 들고 있으므로([LegalDocument.version])
/// 여기서 "서버가 적어 둔 버전 == 지금 문서 버전" 을 문서마다 견준다. 하나라도 다르거나
/// 없으면 동의 안 한 것으로 본다.
///
/// ## 계정마다 따로 센다
///
/// 한 기기를 가족이 나눠 쓸 수 있다. 계정이 바뀌었는데 앞사람의 동의가 그대로 적용되면
/// **그 사람은 약관을 본 적이 없는데 동의한 것이 된다.**
///
/// ## 옛 키(`account_consent_v1_*`)는 읽지 않는다
///
/// 버전이 없는 불리언이라 "무엇에 동의했는지" 를 말하지 못한다. 배포된 클라이언트가
/// 없어 잃는 것도 없다.
class ConsentGate {
  const ConsentGate({SharedPreferences? preferences, ConsentRepository? repository})
      : _injected = preferences,
        _injectedRepository = repository;

  final SharedPreferences? _injected;
  final ConsentRepository? _injectedRepository;

  /// 필수 셋. 이 셋이 **지금 버전으로** 전부 동의돼야 지나간다.
  static const List<LegalDocument> requiredDocuments = [
    LegalDocument.terms,
    LegalDocument.privacy,
    LegalDocument.location,
  ];

  /// 문서별로 동의한 버전을 남기는 키. 값은 `{"TERMS":"v1.2", ...}` JSON 이다.
  ///
  /// `v2` 인 이유: `v1` 은 버전 없는 불리언이었다. 키를 바꿔 옛 값이 읽히지 않게 한다.
  static String keyFor(int userId) => 'account_consent_v2_$userId';

  /// 마케팅 수신 동의(선택). **필수와 따로 센다** — 선택 항목을 필수와 한 값에 묶으면
  /// "마케팅을 안 받겠다" 가 "가입을 안 하겠다" 가 된다.
  static String marketingKeyFor(int userId) => 'account_consent_marketing_v1_$userId';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  ConsentRepository get _repository => _injectedRepository ?? ConsentRepository();

  /// 이 계정이 필수 셋에 **지금 버전으로** 동의했는가.
  ///
  /// 서버 → 캐시 순서다. 어느 쪽도 못 읽으면 "안 했다" 로 본다 — 실패를 "했다" 로 읽으면
  /// 저장소가 잠깐 삐끗한 사이에 동의 없이 위치가 수집된다.
  Future<bool> hasAgreed(int userId) async {
    final fromServer = await _fromServer(userId);
    if (fromServer != null) return _covers(fromServer);
    return _covers(await _fromCache(userId));
  }

  /// 마케팅 수신에 동의했는가. 캐시만 본다 — 필수가 아니라 서버를 한 번 더 부를 값이 아니다.
  Future<bool> marketingOptIn(int userId) async {
    try {
      return (await _prefs).getBool(marketingKeyFor(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 동의를 남긴다 — **서버에 먼저**, 성공하면 기기에도.
  ///
  /// 성공 여부를 돌려준다. 서버가 안 받아 주면 `false` 이고 기기에도 안 적는다. 삼키면
  /// 화면이 넘어간 뒤 서버는 여전히 모르는 채가 된다.
  Future<bool> markAgreed(int userId, {required bool marketing}) async {
    final entries = <ConsentEntry>[
      for (final doc in requiredDocuments)
        ConsentEntry(kind: doc.kind, version: doc.version, agreed: true),
      ConsentEntry(
          kind: LegalDocument.marketing.kind,
          version: LegalDocument.marketing.version,
          agreed: marketing),
    ];

    final List<ServerConsent> recorded;
    try {
      recorded = await _repository.record(entries);
    } catch (_) {
      return false;
    }

    // 서버가 돌려준 상태를 캐시한다 — 보낸 것이 아니라 **적힌 것**을.
    try {
      final prefs = await _prefs;
      await prefs.setString(keyFor(userId), _encode(_agreedVersions(recorded)));
      await prefs.setBool(marketingKeyFor(userId), marketing);
    } catch (_) {
      // 캐시 쓰기 실패는 삼킨다 — 서버에는 남았다. 다음 실행에 서버에서 다시 읽는다.
    }
    return _covers(_agreedVersions(recorded));
  }

  /// 이 계정의 캐시를 지운다. **로그아웃·탈퇴가 부른다.**
  ///
  /// 서버 기록은 안 지운다 — 철회는 [markAgreed] 의 반대가 아니라 별도의 기록이고,
  /// 로그아웃은 철회가 아니다. 안 지우면 같은 기기에서 계정을 지웠다가 같은 id 로 다시
  /// 만든 사람에게 앞사람의 캐시가 적용된다.
  Future<void> clear(int userId) async {
    try {
      final prefs = await _prefs;
      await prefs.remove(keyFor(userId));
      await prefs.remove(marketingKeyFor(userId));
    } catch (_) {
      // 삼킨다 — 지우지 못해도 다음 사람에게 한 번 더 묻는 쪽으로 기운다.
    }
  }

  // ─────────────────────────── 내부 ───────────────────────────

  /// 서버가 적어 둔 문서별 동의 버전. 못 부르면 `null` — "모른다" 와 "없다" 를 가른다.
  Future<Map<ConsentKind, String>?> _fromServer(int userId) async {
    final List<ServerConsent> rows;
    try {
      rows = await _repository.fetch();
    } catch (_) {
      return null;
    }
    final agreed = _agreedVersions(rows);
    // 서버가 답했으면 캐시를 그것으로 맞춘다 — 다른 기기에서 철회했을 수도 있다.
    try {
      await (await _prefs).setString(keyFor(userId), _encode(agreed));
    } catch (_) {}
    return agreed;
  }

  Future<Map<ConsentKind, String>> _fromCache(int userId) async {
    try {
      final raw = (await _prefs).getString(keyFor(userId));
      if (raw == null) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <ConsentKind, String>{};
      decoded.forEach((k, v) {
        final kind = ConsentKindWire.fromWire('$k');
        if (kind != null && v is String) out[kind] = v;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// 캐시에 적는 모양 — 키가 계약의 문자열(`TERMS`)이다.
  ///
  /// enum 을 키로 둔 채 `jsonEncode` 에 넘기면 **던진다**(JSON 키는 문자열이어야 한다). 처음에
  /// 그렇게 했고 그 예외를 캐시 쓰기의 try/catch 가 삼켜서, 캐시가 한 번도 안 적힌 채
  /// "비행기 모드에서 지나간다" 검사가 빨간불이었다. 삼키는 자리가 버그를 숨긴 예다.
  static String _encode(Map<ConsentKind, String> agreed) =>
      jsonEncode({for (final e in agreed.entries) e.key.wire: e.value});

  /// 마지막 기록이 "동의" 인 문서만 버전과 함께.
  static Map<ConsentKind, String> _agreedVersions(List<ServerConsent> rows) => {
        for (final r in rows)
          if (r.agreed) r.kind: r.version,
      };

  /// 필수 셋이 전부 **지금 버전으로** 동의됐는가.
  static bool _covers(Map<ConsentKind, String> agreed) {
    for (final doc in requiredDocuments) {
      if (agreed[doc.kind] != doc.version) return false;
    }
    return true;
  }
}
