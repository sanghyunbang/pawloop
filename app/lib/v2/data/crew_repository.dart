// 크루 — 서버 왕복 (#417, 서버는 PR #426).
//
// ## 초대 크루의 "없다" 는 정말 없는 것처럼 다룬다
//
// 서버는 안 든 사람에게 초대 크루를 **404** 로 답한다 — 403 이면 id 를 훑어 어느 번호에
// 크루가 있는지 셀 수 있기 때문이다. 앱도 그 답을 그대로 옮긴다. "권한이 없어요" 라고
// 고쳐 말하면 서버가 감춘 것을 화면이 도로 알려 주는 셈이다.
//
// ## 정원이 찬 것과 코드가 죽은 것은 다르다
//
// 둘 다 409 지만 사용자가 할 일이 다르다 — 하나는 **자리가 나기를 기다리는 것**이고
// 하나는 **새 코드를 받는 것**이다. `InviteJoinScreen` 이 채팅에서 같은 구분을 한다.
//
// ## 409 의 뜻은 경로가 정한다
//
// 정원이 찬 것(참여) · 이미 맡은 것(품앗이 맡기) · 혼자가 아닌 것(크루 지우기)이 전부 같은
// `CONFLICT` 코드로 온다 — 서버가 상태 코드를 스스로 정해 던지면 코드가 상태에서 나온다.
// 문구로 가르면 문구를 다듬는 날 조용히 뒤집히므로, **어느 요청이었는지**로 가른다. 초대코드
// 소진만 코드가 따로 와서(`INVITE_USES_EXHAUSTED`) 그것은 코드로 가른다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';
import '../domain/crew.dart';
import '../domain/crew_favor.dart';
import '../domain/schedule.dart' show Schedule;

/// 목록이 묻는 질문 둘. 돌아오는 것은 같은 카드다.
enum CrewScope {
  /// 내가 든 크루. 기본값이다 — 크루 화면을 여는 사람 대부분은 이미 든 모임을 보러 온다.
  mine('mine'),

  /// 우리 동네 공개 크루. 동네를 안 고른 사람에게는 서버가 400 이다.
  neighborhood('neighborhood');

  const CrewScope(this.wire);

  final String wire;
}

/// 발급된 초대 — 코드와 그 코드의 사실(만료·횟수). 서버 `ChatInviteView` 의 값이다.
///
/// `FamilyInvite` 와 같은 모양이지만 **그 타입을 안 빌려 온다** — 크루 화면이
/// `family_repository` 를 부르기 시작하면 가족을 고칠 때 크루가 함께 흔들린다.
class CrewInvite {
  final String code;

  /// 서버 시각(UTC 오프셋). `null` 이면 만료 없음.
  final DateTime? expiresAt;

  /// `null` 이면 횟수 무제한.
  final int? maxUses;

  const CrewInvite({required this.code, this.expiresAt, this.maxUses});

  factory CrewInvite.fromJson(Map json) {
    final expires = json['expiresAt'];
    final uses = json['maxUses'];
    return CrewInvite(
      code: '${json['code'] ?? ''}',
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      maxUses: uses is num ? uses.toInt() : null,
    );
  }
}

/// 크루를 못 다룬 이유. 화면이 그대로 말한다 — "실패했어요" 로 뭉개지 않는다.
enum CrewFailureKind {
  /// 없거나, 안 든 사람이 본 초대 크루다. **서버는 둘을 구분하지 않는다.**
  notFound,

  /// 방장이 아니거나, 만 14세 미만이거나, 강퇴당한 방이다. [CrewFailure.message] 를 쓴다.
  forbidden,

  /// 크루 정원이 찼다. **새 코드를 받아도 소용없다** — 자리가 나야 한다.
  full,

  /// 초대코드가 만료·회수됐거나 사용 횟수를 다 썼다. 새 코드를 받으면 된다.
  inviteDead,

  /// 이미 다른 사람이 맡은 부탁이다. 화면이 낡은 것이라 목록을 다시 받으면 된다.
  taken,

  /// 크루에 다른 사람이 남아 있어 못 지운다. 방장을 넘기고 나가면 된다.
  notAlone,

  /// 동네를 안 골랐거나, 이름이 비었거나, 공개인데 동네가 없다. 품앗이라면 지난 날짜거나
  /// 내 부탁을 내가 맡으려 한 것이다.
  invalid,

  /// 연결이 없다. 다시 보내면 된다.
  network,
}

class CrewFailure implements Exception {
  final CrewFailureKind kind;

  /// 서버가 준 문구. **없으면 지어내지 않는다** — 화면이 종류로 말한다.
  final String? message;

  const CrewFailure(this.kind, {this.message});

  @override
  String toString() => 'CrewFailure($kind, $message)';
}

class CrewRepository {
  static const Duration timeout = Duration(seconds: 12);

  /// 서버의 `CrewService.MAX_NAME_LENGTH` 와 같은 값이다.
  static const int maxNameLength = 30;

  static const int maxIntroLength = 200;

  static const int minCapacity = 2;
  static const int maxCapacity = 100;
  static const int defaultCapacity = 20;

  final String baseUrl;
  final AuthedClient _authed;

  CrewRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = (baseUrl ?? Env.apiBase).replaceAll(RegExp(r'/+$'), ''),
        _authed = client ?? AuthedClient.instance;

  /// 목록 한 판.
  ///
  /// [CrewScope.neighborhood] 는 동네를 고른 사람에게만 답이 있다 — 안 골랐으면
  /// [CrewFailureKind.invalid] 다. 좌표로 대신 찾지 않는다(A안 #235).
  Future<List<Crew>> list({CrewScope scope = CrewScope.mine}) async {
    final uri = Uri.parse('$baseUrl/api/crews')
        .replace(queryParameters: {'scope': scope.wire});
    return Crew.parseList(await _send(() => _authed.getJson(uri)));
  }

  /// 크루 홈 하나. 멤버 목록은 **내가 든 크루일 때만** 채워져 온다.
  Future<Crew> detail(int crewId) async {
    return _one(await _send(
        () => _authed.getJson(Uri.parse('$baseUrl/api/crews/$crewId'))));
  }

  /// 만든다. 같은 트랜잭션에서 대화방이 함께 생기고 내가 그 방의 방장이 된다.
  ///
  /// [neighborhoodCode] 를 안 주면 **내 동네**다. 내 동네도 없는데 [visibility] 가
  /// 공개면 서버가 400 이다 — 아무도 못 찾는 공개이기 때문이다.
  Future<Crew> create({
    required String name,
    String? intro,
    String? neighborhoodCode,
    CrewVisibility visibility = CrewVisibility.invite,
    int capacity = defaultCapacity,
  }) async {
    final json = await _send(() => _authed.postJson(
          Uri.parse('$baseUrl/api/crews'),
          body: {
            'name': name,
            if (intro != null && intro.isNotEmpty) 'intro': intro,
            if (neighborhoodCode != null && neighborhoodCode.isNotEmpty)
              'neighborhoodCode': neighborhoodCode,
            'visibility': visibility.wire,
            'capacity': capacity,
          },
        ));
    return _one(json);
  }

  /// 고친다. **방장만** — 아니면 [CrewFailureKind.forbidden] 이다.
  ///
  /// **`null` 과 빈 문자열이 다르다.** 안 주면 안 바꾸고, `''` 를 주면 지운다(소개를
  /// 지우거나 동네를 떼는 유일한 방법이다). 그래서 이 메서드의 파라미터도 전부 선택이다.
  ///
  /// 이름을 바꾸면 **대화방 이름도 함께** 바뀐다 — 서버가 같은 요청에서 한다.
  Future<Crew> edit(
    int crewId, {
    String? name,
    String? intro,
    String? neighborhoodCode,
    CrewVisibility? visibility,
    int? capacity,
  }) async {
    final body = <String, Object?>{
      if (name != null) 'name': name,
      if (intro != null) 'intro': intro,
      if (neighborhoodCode != null) 'neighborhoodCode': neighborhoodCode,
      if (visibility != null) 'visibility': visibility.wire,
      if (capacity != null) 'capacity': capacity,
    };
    // 서버도 빈 본문을 400 으로 막지만, 여기서 먼저 멈추는 편이 낫다 — 아무것도 안 바뀐
    // 왕복을 보내고 400 을 받아 "고치지 못했어요" 를 띄우는 것은 사용자에게 거짓말이다.
    if (body.isEmpty) {
      throw const CrewFailure(CrewFailureKind.invalid, message: '고칠 것을 하나 이상 골라 주세요.');
    }
    return _one(await _send(
        () => _authed.patchJson(Uri.parse('$baseUrl/api/crews/$crewId'), body: body)));
  }

  /// 공개 크루에 코드 없이 들어간다. 초대 크루면 [CrewFailureKind.notFound] 다.
  Future<Crew> join(int crewId) async {
    return _one(await _send(() =>
        _authed.postJson(Uri.parse('$baseUrl/api/crews/$crewId/members/me'))));
  }

  /// 초대 코드로 들어간다. 가족방 코드로는 못 지나간다([CrewFailureKind.forbidden]).
  Future<Crew> joinByCode(String code) async {
    return _one(await _send(() => _authed
        .postJson(Uri.parse('$baseUrl/api/crews/join/${Uri.encodeComponent(code)}'))));
  }

  /// 초대 코드를 낸다. **방장만.**
  ///
  /// 경로가 `/api/crews/...` 가 아니라 `/api/chat/rooms/{roomId}/invites` 인 것은
  /// ADR-0011 때문이다 — 초대코드는 크루가 아니라 **방**에 붙고 만료·사용횟수·회수를
  /// 가진다. 크루 쪽에 같은 경로를 새로 파면 코드가 두 종류가 된다.
  ///
  /// **발급할 때마다 새 코드가 생기고 이전 코드는 안 죽는다**(#75 에서 실측). 그래서
  /// 화면에서 "새 코드 발급" 을 유출 대응 버튼처럼 광고하면 안 된다.
  ///
  /// [roomId] 는 [Crew.roomId] 다.
  Future<CrewInvite> issueInvite(int roomId) async {
    final json = await _send(() =>
        _authed.postJson(Uri.parse('$baseUrl/api/chat/rooms/$roomId/invites')));
    if (json is! Map) throw const CrewFailure(CrewFailureKind.network);
    return CrewInvite.fromJson(json);
  }

  /// 나간다. **방에서도 나간다** — 정확히는 나갈 곳이 하나뿐이다.
  ///
  /// 방장은 못 나간다([CrewFailureKind.invalid]) — 나가면 초대코드도 못 내는 방이 남는다.
  Future<void> leave(int crewId) async {
    await _send(
        () => _authed.deleteJson(Uri.parse('$baseUrl/api/crews/$crewId/members/me')));
  }

  /// 내보낸다. **방장만.** 그 사람은 다시 못 들어온다.
  Future<void> kick(int crewId, int userId) async {
    await _send(() =>
        _authed.deleteJson(Uri.parse('$baseUrl/api/crews/$crewId/members/$userId')));
  }

  /// 방장을 넘긴다. **방장만.** 그 방에 없는 사람이면 [CrewFailureKind.notFound], 자기
  /// 자신이면 [CrewFailureKind.invalid] 다.
  ///
  /// 돌아오는 크루의 [Crew.owner] 는 `false` 다 — 넘긴 뒤의 나는 평범한 멤버라 [leave] 로
  /// 나갈 수 있다. 이것이 없으면 크루를 만든 사람은 갇힌다(서버 PR #428).
  Future<Crew> transferOwner(int crewId, int userId) async {
    return _one(await _send(() =>
        _authed.putJson(Uri.parse('$baseUrl/api/crews/$crewId/owner/$userId'))));
  }

  /// 크루를 지운다. **방장이 혼자 남았을 때만** — 아니면 [CrewFailureKind.notAlone] 이다.
  ///
  /// 대화방과 품앗이, 품앗이가 달력에 남긴 줄까지 함께 사라진다. 남이 있을 때 못 지우는 것은
  /// 남의 대화를 지우는 버튼을 안 만들려는 것이다 — 그때는 넘기고 나간다.
  Future<void> delete(int crewId) async {
    await _send(() => _authed.deleteJson(Uri.parse('$baseUrl/api/crews/$crewId')),
        conflict: CrewFailureKind.notAlone);
  }

  // ─────────────────────────── 품앗이 (#417, 서버는 PR #428) ───────────────────────────

  /// 서버의 `CrewFavor.MAX_NOTE_LENGTH` 와 같은 값이다.
  static const int maxFavorNoteLength = 200;

  /// 그 크루의 부탁 — 가까운 날짜부터 50건. **멤버만** — 공개 크루라도 안 든 사람에게는
  /// [CrewFailureKind.notFound] 다(부탁에는 아이 이름과 "그날 집을 비운다" 가 적힌다).
  /// 지난 것은 서버가 뺀다.
  Future<List<CrewFavor>> favors(int crewId) async {
    return CrewFavor.parseList(await _send(
        () => _authed.getJson(Uri.parse('$baseUrl/api/crews/$crewId/favors'))));
  }

  /// 부탁을 올린다. 지난 날짜는 [CrewFailureKind.invalid], 남의 아이는
  /// [CrewFailureKind.notFound] 다.
  ///
  /// [dogId] 를 안 주면 본문에 안 싣는다 — 아이를 아직 등록 안 한 사람도 부탁할 수 있다.
  /// [note] 는 다듬어서 싣고, 비면 안 싣는다. **금액 칸이 없다** — 파일 머리말 참조.
  Future<CrewFavor> postFavor(
    int crewId, {
    required DateTime onDate,
    required CrewFavorSlot slot,
    int? dogId,
    String? note,
  }) async {
    final trimmed = note?.trim() ?? '';
    final json = await _send(() => _authed.postJson(
          Uri.parse('$baseUrl/api/crews/$crewId/favors'),
          body: {
            'onDate': Schedule.formatDate(onDate),
            'slot': slot.wire,
            if (dogId != null) 'dogId': dogId,
            if (trimmed.isNotEmpty) 'note': trimmed,
          },
        ));
    return _favor(json);
  }

  /// "제가 할게요". 이미 맡은 것이면 [CrewFailureKind.taken], 내 부탁이면
  /// [CrewFailureKind.invalid] 다.
  ///
  /// 맡는 순간 **크루 일정 한 줄**이 생긴다 — 답의 [CrewFavor.scheduleId] 가 그것이고, 그
  /// 줄은 그 크루 사람 모두의 달력에 뜬다. 앱이 일정을 따로 만들지 않는다.
  Future<CrewFavor> takeFavor(int crewId, int favorId) async {
    return _favor(await _send(
      () => _authed
          .postJson(Uri.parse('$baseUrl/api/crews/$crewId/favors/$favorId/take')),
      conflict: CrewFailureKind.taken,
    ));
  }

  /// 무른다. **맡은 사람만** — 아니면 [CrewFailureKind.forbidden] 이다. 부탁이 다시 열리고
  /// 달력의 줄은 사라진다.
  ///
  /// 올린 사람이 거둬들이는 것([cancelFavor])과 경로가 다르다 — 권한도 결과도 다르다.
  Future<CrewFavor> releaseFavor(int crewId, int favorId) async {
    return _favor(await _send(() => _authed
        .deleteJson(Uri.parse('$baseUrl/api/crews/$crewId/favors/$favorId/take'))));
  }

  /// 거둬들인다. **올린 사람만** — 부탁이 사라진다. 이미 맡은 것도 지울 수 있고, 그때 맡은
  /// 사람의 달력 줄도 함께 사라진다.
  Future<void> cancelFavor(int crewId, int favorId) async {
    await _send(() =>
        _authed.deleteJson(Uri.parse('$baseUrl/api/crews/$crewId/favors/$favorId')));
  }

  static Crew _one(Object? json) {
    final crew = Crew.tryParse(json);
    // 본문이 계약과 다르면 이유를 모르는 것이다 — 화면에 빈 크루를 그리지 않는다.
    if (crew == null) throw const CrewFailure(CrewFailureKind.network);
    return crew;
  }

  static CrewFavor _favor(Object? json) {
    final favor = CrewFavor.tryParse(json);
    if (favor == null) throw const CrewFailure(CrewFailureKind.network);
    return favor;
  }

  /// 한 번의 왕복. **상태 코드를 실패의 종류로 옮기는 곳이 여기 하나다.**
  ///
  /// [conflict] 는 409 의 뜻이다 — 파일 머리말 참조. 안 주면 정원이 찬 것이다.
  Future<Object?> _send(
    Future<http.Response> Function() request, {
    CrewFailureKind conflict = CrewFailureKind.full,
  }) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } catch (_) {
      throw const CrewFailure(CrewFailureKind.network);
    }

    final body = _decode(res.bodyBytes);
    final message = _messageOf(body);

    if (res.statusCode == 404) {
      throw CrewFailure(CrewFailureKind.notFound, message: message);
    }
    if (res.statusCode == 403) {
      throw CrewFailure(CrewFailureKind.forbidden, message: message);
    }
    if (res.statusCode == 409) {
      // 코드 소진만 서버의 어휘(`code`)로 가른다. 나머지 409 는 전부 `CONFLICT` 라 어느
      // 요청이었는지([conflict])로 가른다 — 문구로 가르면 문구를 다듬는 날 조용히 뒤집힌다.
      final code = _codeOf(body);
      throw CrewFailure(
        code == 'INVITE_USES_EXHAUSTED' ? CrewFailureKind.inviteDead : conflict,
        message: message,
      );
    }
    if (res.statusCode == 410) {
      throw CrewFailure(CrewFailureKind.inviteDead, message: message);
    }
    if (res.statusCode == 400) {
      throw CrewFailure(CrewFailureKind.invalid, message: message);
    }
    if (res.statusCode >= 400) throw const CrewFailure(CrewFailureKind.network);
    if (res.bodyBytes.isEmpty) return null;
    return body;
  }

  static Object? _decode(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String? _messageOf(Object? body) {
    if (body is Map && body['error'] is Map) {
      return (body['error'] as Map)['message'] as String?;
    }
    return null;
  }

  static String? _codeOf(Object? body) {
    if (body is Map && body['error'] is Map) {
      return (body['error'] as Map)['code'] as String?;
    }
    return null;
  }
}
