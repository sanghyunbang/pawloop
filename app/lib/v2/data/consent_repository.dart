import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';
import '../../core/net/net_timeouts.dart';

/// 동의를 받는 문서 넷. 계약(`openapi.yaml`)의 `ConsentKind` 와 같은 이름이다.
///
/// `MARKETING` 만 선택이다. 서버는 그 구분을 모른다 — 필수인지 판정하는 자리는
/// [ConsentGate] 다.
enum ConsentKind { terms, privacy, location, marketing }

extension ConsentKindWire on ConsentKind {
  /// 계약의 문자열. 서버와 이 문자열로 만난다.
  String get wire => name.toUpperCase();

  static ConsentKind? fromWire(String? s) {
    for (final k in ConsentKind.values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

/// 서버가 돌려준 문서 하나의 지금 상태 — 계약의 `Consent`.
class ServerConsent {
  final ConsentKind kind;
  final String version;
  final bool agreed;
  final DateTime at;

  const ServerConsent({
    required this.kind,
    required this.version,
    required this.agreed,
    required this.at,
  });

  static ServerConsent? tryParse(Map<String, dynamic> j) {
    final kind = ConsentKindWire.fromWire(j['kind'] as String?);
    final version = j['version'];
    final agreed = j['agreed'];
    final at = DateTime.tryParse('${j['at'] ?? ''}');
    if (kind == null || version is! String || agreed is! bool || at == null) {
      return null;
    }
    return ServerConsent(kind: kind, version: version, agreed: agreed, at: at);
  }
}

/// 서버에 보낼 항목 하나 — 계약의 `ConsentInput`.
class ConsentEntry {
  final ConsentKind kind;
  final String version;
  final bool agreed;

  const ConsentEntry({required this.kind, required this.version, required this.agreed});

  Map<String, Object> toJson() => {'kind': kind.wire, 'version': version, 'agreed': agreed};
}

/// 서버가 동의를 안 받아 주었다. 화면은 이유를 구분할 필요가 없다 — 다시 시도하게 할 뿐이다.
class ConsentFailure implements Exception {
  final int? statusCode;
  const ConsentFailure([this.statusCode]);

  @override
  String toString() => 'ConsentFailure(${statusCode ?? 'network'})';
}

/// `GET/PUT /api/consents` — 이슈 #190.
///
/// ## 이 저장소가 아는 것
///
/// "서버가 이 계정에 대해 어느 문서의 어느 버전을 언제 동의로 적어 두었나" 뿐이다.
/// **문서의 지금 버전은 여기 없다** — 그건 [LegalDocument] 가 들고 있고, 둘을 견줘서
/// 재동의를 정하는 자리는 [ConsentGate] 다. 서버도 그 버전을 모른다(ADR-0020).
///
/// ## 좌표가 없다
///
/// 요청에 실리는 것은 문서 이름·버전·불리언이다. 그래서 `LocationUploadPolicy` 를 지나지
/// 않는다 — 보낼 좌표가 없다.
class ConsentRepository {
  ConsentRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = _stripTrailingSlash(baseUrl ?? Env.apiBase),
        _authed = client ?? AuthedClient.instance;

  final String baseUrl;
  final AuthedClient _authed;

  /// 응답 전체의 상한. 동의 화면이 이 뒤에 서 있다 — 무한정 기다리게 하면 안 된다.
  static const Duration timeout = NetTimeouts.standard;

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// 문서별 마지막 기록. 한 번도 안 적은 문서는 목록에 없다.
  Future<List<ServerConsent>> fetch() async {
    final json = await _send(() => _authed.getJson(Uri.parse('$baseUrl/api/consents')));
    return _parseList(json);
  }

  /// 동의(또는 철회)를 적고, 적은 뒤의 상태를 돌려받는다.
  Future<List<ServerConsent>> record(List<ConsentEntry> entries) async {
    final json = await _send(() => _authed.putJson(
          Uri.parse('$baseUrl/api/consents'),
          body: {'consents': entries.map((e) => e.toJson()).toList()},
        ));
    return _parseList(json);
  }

  static List<ServerConsent> _parseList(Object? json) {
    if (json is! Map<String, dynamic>) throw const ConsentFailure();
    final raw = json['consents'];
    if (raw is! List) throw const ConsentFailure();
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ServerConsent.tryParse)
        .whereType<ServerConsent>()
        .toList();
  }

  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } catch (_) {
      throw const ConsentFailure();
    }
    if (res.statusCode != 200) throw ConsentFailure(res.statusCode);
    try {
      // bodyBytes + utf8 로 읽는다. `res.body` 는 charset 없는 응답을 latin-1 로 읽는다(#81).
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const ConsentFailure();
    }
  }
}
